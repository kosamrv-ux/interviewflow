"""
Core AI scoring logic.

Constructs a structured prompt from the interview transcript and code submission,
calls Vertex AI Gemini, parses the response, and returns a validated ScoreBreakdown.
"""

import json
import time
from typing import Any

import structlog
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type

from app.scoring.models import (
    ScoringRequest,
    ScoringResponse,
    ScoreBreakdown,
    DimensionScore,
)
from app.config import get_settings

logger = structlog.get_logger(__name__)
settings = get_settings()

# Lazy-import Vertex AI to avoid import errors in test environments
_vertex_model = None


def _get_vertex_model() -> Any:
    global _vertex_model
    if _vertex_model is None:
        import vertexai
        from vertexai.generative_models import GenerativeModel, GenerationConfig

        vertexai.init(
            project=settings.vertex_ai_project,
            location=settings.vertex_ai_location,
        )
        _vertex_model = GenerativeModel(
            settings.vertex_ai_model,
            generation_config=GenerationConfig(
                response_mime_type="application/json",
                temperature=0.1,  # Low temp for consistent structured output
                max_output_tokens=4096,
            ),
        )
    return _vertex_model


def _build_prompt(request: ScoringRequest) -> str:
    """Constructs the scoring prompt from the request data."""

    # Format transcript
    transcript_text = "\n".join(
        f"[{seg.speaker.upper()} {seg.start_ms // 1000}s]: {seg.text}"
        for seg in request.transcript
    )

    # Format rubric
    rubric_text = "\n".join(
        f"- {dim}: weight={info.weight:.0%}, criteria={info.criteria or 'standard'}"
        for dim, info in request.rubric.items()
    )

    # Optional code block
    code_block = ""
    if request.code_submission:
        code_block = f"""
## Code Submission ({request.code_submission.language})
```
{request.code_submission.code}
```
"""

    return f"""You are an expert technical interviewer evaluating a candidate for the role of {request.job_title}.

Analyze the following interview transcript and code submission, then produce a structured evaluation.

## Interview Transcript
{transcript_text}
{code_block}
## Evaluation Rubric
Score each dimension from 0.0 to 10.0:
{rubric_text}

## Instructions
- Be specific and evidence-based in your rationale — cite exact moments from the transcript
- composite_score must equal the weighted average of all dimension scores
- recommended_action must be one of: "advance", "reject", "hold"
- confidence is your certainty in the evaluation (0.0–1.0)
- Provide 2–4 specific strengths and 2–3 areas for growth

Respond with ONLY valid JSON matching this schema:
{{
  "composite_score": <number>,
  "breakdown": {{
    "technical_depth": {{"score": <number>, "weight": <number>, "rationale": "<string>"}},
    "communication": {{"score": <number>, "weight": <number>, "rationale": "<string>"}},
    "problem_solving": {{"score": <number>, "weight": <number>, "rationale": "<string>"}},
    "culture_fit": {{"score": <number>, "weight": <number>, "rationale": "<string>"}},
    "role_fit": {{"score": <number>, "weight": <number>, "rationale": "<string>"}}
  }},
  "strengths": ["<string>", ...],
  "areas_for_growth": ["<string>", ...],
  "recommended_action": "<advance|reject|hold>",
  "confidence": <number>
}}"""


@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=2, max=10),
    retry=retry_if_exception_type((TimeoutError, ConnectionError)),
    reraise=True,
)
async def score_interview(request: ScoringRequest) -> ScoringResponse:
    """
    Runs the full scoring pipeline for one interview session.

    1. Build structured prompt from transcript + code
    2. Call Vertex AI Gemini with JSON response mode
    3. Parse and validate the response
    4. Return a ScoringResponse
    """
    start_ms = int(time.time() * 1000)

    log = logger.bind(
        session_id=request.session_id,
        application_id=request.application_id,
        transcript_segments=len(request.transcript),
    )
    log.info("Starting AI scoring")

    prompt = _build_prompt(request)

    # In test mode, return a mock response
    if settings.environment in ("test", "development") and not settings.vertex_ai_project.startswith("interviewflow-prod"):
        raw_response = _mock_response(request)
    else:
        model = _get_vertex_model()
        response = model.generate_content(prompt)
        raw_response = response.text

    try:
        data = json.loads(raw_response)
    except json.JSONDecodeError as e:
        log.error("Failed to parse Vertex AI response as JSON", error=str(e), raw=raw_response[:500])
        raise ValueError(f"Vertex AI returned invalid JSON: {e}") from e

    processing_ms = int(time.time() * 1000) - start_ms

    breakdown = ScoreBreakdown(
        technical_depth=DimensionScore(**data["breakdown"]["technical_depth"]),
        communication=DimensionScore(**data["breakdown"]["communication"]),
        problem_solving=DimensionScore(**data["breakdown"]["problem_solving"]),
        culture_fit=DimensionScore(**data["breakdown"]["culture_fit"]),
        role_fit=DimensionScore(**data["breakdown"]["role_fit"]),
    )

    response_obj = ScoringResponse(
        composite_score=data["composite_score"],
        breakdown=breakdown,
        strengths=data.get("strengths", []),
        areas_for_growth=data.get("areas_for_growth", []),
        recommended_action=data["recommended_action"],
        confidence=data.get("confidence", 0.85),
        model=settings.vertex_ai_model,
        processing_ms=processing_ms,
        prompt_version=request.prompt_version,
    )

    log.info(
        "Scoring complete",
        composite_score=response_obj.composite_score,
        recommended_action=response_obj.recommended_action,
        processing_ms=processing_ms,
    )

    return response_obj


def _mock_response(request: ScoringRequest) -> str:
    """Returns a deterministic mock response for development/test environments."""
    rubric = request.rubric
    return json.dumps({
        "composite_score": 7.8,
        "breakdown": {
            dim: {
                "score": 7.5 + (hash(dim) % 20) / 10,
                "weight": info.weight,
                "rationale": f"[MOCK] Candidate demonstrated solid {dim.replace('_', ' ')} skills based on the transcript.",
            }
            for dim, info in rubric.items()
        },
        "strengths": [
            "Clear problem decomposition approach",
            "Strong technical vocabulary",
            "Good at asking clarifying questions",
        ],
        "areas_for_growth": [
            "Could improve conciseness in verbal explanations",
            "Edge case coverage could be stronger",
        ],
        "recommended_action": "advance",
        "confidence": 0.87,
    })
