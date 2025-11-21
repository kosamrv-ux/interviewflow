"""FastAPI router for the scoring endpoints."""

from fastapi import APIRouter, HTTPException, Header, Request
import structlog

from app.scoring.models import ScoringRequest, ScoringResponse
from app.scoring.scorer import score_interview
from app.config import get_settings

router = APIRouter(prefix="", tags=["scoring"])
logger = structlog.get_logger(__name__)
settings = get_settings()


def _verify_service_secret(x_service_secret: str | None) -> None:
    """Validates the shared secret header from the Phoenix backend."""
    if settings.environment == "production" and x_service_secret != settings.service_secret:
        raise HTTPException(status_code=401, detail="Invalid service secret")


@router.post("/score", response_model=ScoringResponse)
async def score_session(
    request: Request,
    payload: ScoringRequest,
    x_service_secret: str | None = Header(default=None),
) -> ScoringResponse:
    """
    Scores an interview session from transcript and optional code submission.

    Called by Phoenix via an Oban background job after a video session ends.
    Returns a structured scorecard that Phoenix persists as an AiScore record.
    """
    _verify_service_secret(x_service_secret)

    logger.info(
        "Scoring request received",
        session_id=payload.session_id,
        application_id=payload.application_id,
        transcript_length=len(payload.transcript),
        has_code=payload.code_submission is not None,
    )

    try:
        result = await score_interview(payload)
        return result
    except ValueError as e:
        logger.error("Scoring validation error", error=str(e), session_id=payload.session_id)
        raise HTTPException(status_code=422, detail=str(e)) from e
    except Exception as e:
        logger.error("Scoring pipeline error", error=str(e), session_id=payload.session_id)
        raise HTTPException(status_code=500, detail="Scoring pipeline failed") from e
