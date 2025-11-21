"""Pydantic schemas for the scoring request/response contract."""

from typing import Literal, Optional
from pydantic import BaseModel, Field, field_validator


class TranscriptSegment(BaseModel):
    speaker: Literal["interviewer", "candidate"]
    start_ms: int
    end_ms: int
    text: str


class CodeSubmission(BaseModel):
    language: str
    code: str


class RubricDimension(BaseModel):
    weight: float = Field(..., ge=0.0, le=1.0)
    criteria: Optional[str] = None


class ScoringRequest(BaseModel):
    session_id: str
    application_id: str
    job_title: str
    transcript: list[TranscriptSegment]
    code_submission: Optional[CodeSubmission] = None
    rubric: dict[str, RubricDimension]
    prompt_version: str = "v2.1"

    @field_validator("rubric")
    @classmethod
    def validate_rubric_weights(cls, rubric: dict[str, RubricDimension]) -> dict[str, RubricDimension]:
        total = sum(dim.weight for dim in rubric.values())
        if not (0.98 <= total <= 1.02):
            raise ValueError(f"Rubric weights must sum to 1.0 (got {total:.3f})")
        return rubric


class DimensionScore(BaseModel):
    score: float = Field(..., ge=0.0, le=10.0)
    weight: float = Field(..., ge=0.0, le=1.0)
    rationale: str


class ScoreBreakdown(BaseModel):
    technical_depth: DimensionScore
    communication: DimensionScore
    problem_solving: DimensionScore
    culture_fit: DimensionScore
    role_fit: DimensionScore


class ScoringResponse(BaseModel):
    composite_score: float = Field(..., ge=0.0, le=10.0)
    breakdown: ScoreBreakdown
    strengths: list[str]
    areas_for_growth: list[str]
    recommended_action: Literal["advance", "reject", "hold"]
    confidence: float = Field(..., ge=0.0, le=1.0)
    model: str
    processing_ms: int
    prompt_version: str

    @field_validator("composite_score", mode="before")
    @classmethod
    def round_composite(cls, v: float) -> float:
        return round(float(v), 2)
