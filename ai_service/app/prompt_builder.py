"""
Builds structured prompts for the Gemini AI scoring model.

Combines job requirements, candidate profile, transcript, and rubric
into a carefully formatted system + user prompt pair optimized for
accurate, consistent, and structured JSON output.
"""

from __future__ import annotations

from typing import Any


SYSTEM_PROMPT = """You are an expert technical interviewer and talent evaluator for a software engineering hiring platform.

Your task is to evaluate a candidate interview transcript and produce a structured, objective assessment.

EVALUATION FRAMEWORK:
You will score the candidate on four dimensions, each on a scale of 0.0 to 1.0:

1. **Technical Competency** — depth of technical knowledge, accuracy of explanations, problem-solving approach
2. **Communication** — clarity, articulation, ability to explain complex topics, active listening
3. **Problem Solving** — systematic thinking, consideration of edge cases, creativity, handling ambiguity
4. **Cultural Fit** — alignment with collaborative values, growth mindset, professionalism, enthusiasm

RULES:
- Base your assessment ONLY on what was said in the transcript
- Do not assume knowledge the candidate did not demonstrate
- Be specific: reference actual quotes or responses from the transcript
- Scores must be consistent: a score of 0.8 should reflect clearly above-average performance
- The composite score is a weighted average: technical (40%), communication (25%), problem_solving (25%), cultural_fit (10%)

OUTPUT FORMAT:
Return ONLY valid JSON matching this exact schema:
{
  "composite_score": 0.0-1.0,
  "dimension_scores": {
    "technical": 0.0-1.0,
    "communication": 0.0-1.0,
    "problem_solving": 0.0-1.0,
    "cultural_fit": 0.0-1.0
  },
  "summary": "2-3 sentence overall assessment",
  "strengths": ["strength 1", "strength 2", "strength 3"],
  "concerns": ["concern 1", "concern 2"],
  "recommendation": "strong_hire | hire | no_hire | strong_no_hire",
  "model_version": "gemini-1.5-pro-002"
}"""


class PromptBuilder:
    """Constructs scoring prompts from interview context."""

    def build(
        self,
        *,
        job: dict[str, Any],
        candidate: dict[str, Any],
        transcript_text: str,
        transcript_stats: dict[str, Any],
        coding_snapshots: list[dict[str, Any]] | None = None,
        rubric_weights: dict[str, float] | None = None,
    ) -> tuple[str, str]:
        """
        Returns a (system_prompt, user_prompt) tuple.

        Args:
            job: Job description including title, requirements, and skills.
            candidate: Candidate profile with experience level and skills.
            transcript_text: Formatted dialogue string from TranscriptParser.
            transcript_stats: Stats dict from ParsedTranscript.stats().
            coding_snapshots: Optional list of code submission snapshots.
            rubric_weights: Optional custom scoring weights.

        Returns:
            Tuple of (system_prompt_str, user_prompt_str).
        """
        system = self._build_system(rubric_weights)
        user = self._build_user(
            job=job,
            candidate=candidate,
            transcript_text=transcript_text,
            transcript_stats=transcript_stats,
            coding_snapshots=coding_snapshots,
        )
        return system, user

    def _build_system(self, rubric_weights: dict[str, float] | None) -> str:
        if not rubric_weights:
            return SYSTEM_PROMPT

        # Override the weight description in the prompt
        weight_desc = ", ".join(
            f"{dim} ({int(w * 100)}%)" for dim, w in rubric_weights.items()
        )
        return SYSTEM_PROMPT.replace(
            "technical (40%), communication (25%), problem_solving (25%), cultural_fit (10%)",
            weight_desc,
        )

    def _build_user(
        self,
        *,
        job: dict[str, Any],
        candidate: dict[str, Any],
        transcript_text: str,
        transcript_stats: dict[str, Any],
        coding_snapshots: list[dict[str, Any]] | None,
    ) -> str:
        sections: list[str] = []

        # Job context
        sections.append(self._job_section(job))

        # Candidate profile
        sections.append(self._candidate_section(candidate))

        # Transcript metadata
        sections.append(self._stats_section(transcript_stats))

        # Coding challenges (if any)
        if coding_snapshots:
            sections.append(self._coding_section(coding_snapshots))

        # Transcript
        sections.append(f"## INTERVIEW TRANSCRIPT\n\n{transcript_text}")

        # Instruction
        sections.append(
            "## TASK\n\nEvaluate this candidate based on the transcript above. "
            "Return your assessment as JSON following the exact schema in your instructions."
        )

        return "\n\n---\n\n".join(sections)

    def _job_section(self, job: dict[str, Any]) -> str:
        skills = ", ".join(job.get("required_skills", []))
        return (
            f"## JOB REQUIREMENTS\n\n"
            f"**Title:** {job.get('title', 'N/A')}\n"
            f"**Level:** {job.get('experience_level', 'N/A')}\n"
            f"**Required Skills:** {skills or 'Not specified'}\n"
            f"**Description:** {job.get('description', 'N/A')[:500]}"
        )

    def _candidate_section(self, candidate: dict[str, Any]) -> str:
        skills = ", ".join(candidate.get("skills", []))
        return (
            f"## CANDIDATE PROFILE\n\n"
            f"**Name:** {candidate.get('full_name', 'Candidate')}\n"
            f"**Experience Level:** {candidate.get('experience_level', 'N/A')}\n"
            f"**Skills:** {skills or 'Not specified'}"
        )

    def _stats_section(self, stats: dict[str, Any]) -> str:
        duration_min = stats.get("duration_seconds", 0) / 60
        return (
            f"## SESSION METADATA\n\n"
            f"- Duration: {duration_min:.1f} minutes\n"
            f"- Candidate talk ratio: {stats.get('candidate_talk_ratio', 0):.0%}\n"
            f"- Candidate turns: {stats.get('candidate_turns', 0)}\n"
            f"- Average response length: {stats.get('avg_response_length_words', 0):.0f} words"
        )

    def _coding_section(self, snapshots: list[dict[str, Any]]) -> str:
        lines = ["## CODING CHALLENGE SUBMISSIONS\n"]
        for i, snap in enumerate(snapshots, 1):
            lines.append(f"### Submission {i}")
            lines.append(f"**Language:** {snap.get('language', 'unknown')}")
            lines.append(f"**Tests passed:** {snap.get('tests_passed', '?')}/{snap.get('tests_total', '?')}")
            code = snap.get("code", "")[:1500]
            lines.append(f"```{snap.get('language', '')}\n{code}\n```")
        return "\n".join(lines)
