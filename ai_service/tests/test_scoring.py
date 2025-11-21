"""Tests for the AI scoring service."""

import pytest
from httpx import AsyncClient, ASGITransport

from app.main import app
from app.scoring.models import ScoringRequest, TranscriptSegment, RubricDimension, CodeSubmission


VALID_RUBRIC = {
    "technical_depth": RubricDimension(weight=0.35, criteria="Correctness and depth"),
    "communication": RubricDimension(weight=0.25, criteria="Clarity and structure"),
    "problem_solving": RubricDimension(weight=0.20, criteria="Approach and decomposition"),
    "culture_fit": RubricDimension(weight=0.10, criteria="Values alignment"),
    "role_fit": RubricDimension(weight=0.10, criteria="Domain knowledge"),
}

VALID_TRANSCRIPT = [
    TranscriptSegment(
        speaker="interviewer",
        start_ms=0,
        end_ms=8000,
        text="Can you walk me through how you'd implement a rate limiter?",
    ),
    TranscriptSegment(
        speaker="candidate",
        start_ms=8500,
        end_ms=65000,
        text=(
            "Sure. I'd start by clarifying requirements — are we rate limiting per user, "
            "per API key, or globally? For a distributed system I'd use a token bucket "
            "algorithm backed by Redis with INCR and EXPIRE for atomic operations. "
            "The key insight is that Redis INCR is atomic, so we don't need locks..."
        ),
    ),
]


@pytest.fixture
def scoring_request() -> ScoringRequest:
    return ScoringRequest(
        session_id="session-test-123",
        application_id="app-test-456",
        job_title="Senior Backend Engineer",
        transcript=VALID_TRANSCRIPT,
        code_submission=CodeSubmission(
            language="python",
            code=(
                "class RateLimiter:\n"
                "    def __init__(self, redis_client, limit, window_seconds):\n"
                "        self.redis = redis_client\n"
                "        self.limit = limit\n"
                "        self.window = window_seconds\n\n"
                "    def is_allowed(self, key: str) -> bool:\n"
                "        current = self.redis.incr(key)\n"
                "        if current == 1:\n"
                "            self.redis.expire(key, self.window)\n"
                "        return current <= self.limit\n"
            ),
        ),
        rubric=VALID_RUBRIC,
        prompt_version="v2.1",
    )


@pytest.mark.asyncio
async def test_health_endpoint() -> None:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/health")

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert data["service"] == "ai_scoring"


@pytest.mark.asyncio
async def test_score_endpoint_returns_valid_scorecard(scoring_request: ScoringRequest) -> None:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post(
            "/score",
            json=scoring_request.model_dump(),
            headers={"x-service-secret": "dev-secret"},
        )

    assert response.status_code == 200
    data = response.json()

    assert 0.0 <= data["composite_score"] <= 10.0
    assert data["recommended_action"] in ("advance", "reject", "hold")
    assert 0.0 <= data["confidence"] <= 1.0
    assert len(data["strengths"]) >= 1
    assert len(data["areas_for_growth"]) >= 1
    assert "breakdown" in data

    for dim in ["technical_depth", "communication", "problem_solving", "culture_fit", "role_fit"]:
        assert dim in data["breakdown"]
        assert 0.0 <= data["breakdown"][dim]["score"] <= 10.0


@pytest.mark.asyncio
async def test_score_endpoint_without_code_submission(scoring_request: ScoringRequest) -> None:
    scoring_request.code_submission = None

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post(
            "/score",
            json=scoring_request.model_dump(),
        )

    assert response.status_code == 200
    assert response.json()["composite_score"] is not None


@pytest.mark.asyncio
async def test_score_rejects_invalid_rubric_weights() -> None:
    """Rubric weights that don't sum to 1.0 should fail validation."""
    invalid_rubric = {
        "technical_depth": {"weight": 0.50},
        "communication": {"weight": 0.50},
        "problem_solving": {"weight": 0.50},  # Total = 1.50, invalid
        "culture_fit": {"weight": 0.10},
        "role_fit": {"weight": 0.10},
    }
    payload = {
        "session_id": "test-session",
        "application_id": "test-app",
        "job_title": "Engineer",
        "transcript": [{"speaker": "candidate", "start_ms": 0, "end_ms": 1000, "text": "Hello"}],
        "rubric": invalid_rubric,
    }

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post("/score", json=payload)

    assert response.status_code == 422


@pytest.mark.asyncio
async def test_score_validates_empty_transcript() -> None:
    """Empty transcript is technically valid but should still score."""
    payload = {
        "session_id": "test-session",
        "application_id": "test-app",
        "job_title": "Engineer",
        "transcript": [],
        "rubric": {
            "technical_depth": {"weight": 0.35},
            "communication": {"weight": 0.25},
            "problem_solving": {"weight": 0.20},
            "culture_fit": {"weight": 0.10},
            "role_fit": {"weight": 0.10},
        },
    }

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post("/score", json=payload)

    # Should score (with low confidence from mock), not crash
    assert response.status_code == 200
