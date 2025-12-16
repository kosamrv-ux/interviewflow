"""
Rubric validation and weight normalization for AI scoring requests.

A rubric defines how the five standard dimensions should be weighted when
computing the composite score for a particular job or interview type.

Dimension keys (must be exactly these five):
  - technical_depth
  - communication
  - problem_solving
  - culture_fit
  - coding_quality

Weights must sum to 1.0 (validated with a 0.001 tolerance for float precision).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Final

DIMENSION_KEYS: Final[tuple[str, ...]] = (
    "technical_depth",
    "communication",
    "problem_solving",
    "culture_fit",
    "coding_quality",
)

DEFAULT_RUBRIC: Final[dict[str, float]] = {
    "technical_depth": 0.35,
    "communication": 0.25,
    "problem_solving": 0.20,
    "culture_fit": 0.10,
    "coding_quality": 0.10,
}

# Interview-type-specific presets
RUBRIC_PRESETS: Final[dict[str, dict[str, float]]] = {
    "technical": {
        "technical_depth": 0.40,
        "communication": 0.15,
        "problem_solving": 0.25,
        "culture_fit": 0.05,
        "coding_quality": 0.15,
    },
    "behavioral": {
        "technical_depth": 0.10,
        "communication": 0.40,
        "problem_solving": 0.20,
        "culture_fit": 0.25,
        "coding_quality": 0.05,
    },
    "system_design": {
        "technical_depth": 0.45,
        "communication": 0.20,
        "problem_solving": 0.25,
        "culture_fit": 0.05,
        "coding_quality": 0.05,
    },
    "culture_fit": {
        "technical_depth": 0.05,
        "communication": 0.30,
        "problem_solving": 0.15,
        "culture_fit": 0.45,
        "coding_quality": 0.05,
    },
    "coding": {
        "technical_depth": 0.25,
        "communication": 0.10,
        "problem_solving": 0.20,
        "culture_fit": 0.05,
        "coding_quality": 0.40,
    },
}


class RubricValidationError(ValueError):
    """Raised when a rubric does not pass validation."""


@dataclass
class Rubric:
    """Validated rubric with per-dimension weights summing to 1.0."""

    weights: dict[str, float] = field(default_factory=lambda: dict(DEFAULT_RUBRIC))

    def __post_init__(self) -> None:
        self._validate()

    def _validate(self) -> None:
        missing = [k for k in DIMENSION_KEYS if k not in self.weights]
        if missing:
            raise RubricValidationError(
                f"Rubric is missing required dimensions: {', '.join(missing)}"
            )

        extra = [k for k in self.weights if k not in DIMENSION_KEYS]
        if extra:
            raise RubricValidationError(
                f"Rubric contains unknown dimensions: {', '.join(extra)}"
            )

        total = sum(self.weights.values())
        if abs(total - 1.0) > 0.001:
            raise RubricValidationError(
                f"Rubric weights must sum to 1.0, got {total:.4f}"
            )

    def compute_composite(self, dimension_scores: dict[str, float]) -> float:
        """
        Compute the weighted composite score from per-dimension raw scores.

        Each dimension score is expected to be in the range [0.0, 10.0].
        Missing dimension scores default to 5.0 (mid-range) rather than 0.0
        to avoid penalising candidates when a dimension wasn't assessed.

        Returns a float in [0.0, 10.0].
        """
        total = 0.0
        for dim, weight in self.weights.items():
            score = dimension_scores.get(dim, 5.0)
            total += score * weight
        return round(total, 2)

    @classmethod
    def from_dict(cls, data: dict[str, float]) -> "Rubric":
        """Construct and validate a Rubric from a plain dict."""
        return cls(weights=dict(data))

    @classmethod
    def preset(cls, interview_type: str) -> "Rubric":
        """Return a named preset, defaulting to the standard rubric."""
        weights = RUBRIC_PRESETS.get(interview_type, DEFAULT_RUBRIC)
        return cls(weights=dict(weights))
