"""
Tests for the Rubric validation and composite score computation.
"""

import pytest
from app.scoring.rubric import (
    DEFAULT_RUBRIC,
    RUBRIC_PRESETS,
    Rubric,
    RubricValidationError,
)


class TestRubricValidation:
    def test_default_rubric_is_valid(self) -> None:
        rubric = Rubric()
        assert rubric.weights == DEFAULT_RUBRIC

    def test_custom_valid_rubric(self) -> None:
        weights = {
            "technical_depth": 0.40,
            "communication": 0.20,
            "problem_solving": 0.20,
            "culture_fit": 0.10,
            "coding_quality": 0.10,
        }
        rubric = Rubric(weights=weights)
        assert rubric.weights["technical_depth"] == 0.40

    def test_raises_on_missing_dimension(self) -> None:
        weights = {
            "technical_depth": 0.50,
            "communication": 0.25,
            "problem_solving": 0.25,
            # missing culture_fit and coding_quality
        }
        with pytest.raises(RubricValidationError, match="missing required dimensions"):
            Rubric(weights=weights)

    def test_raises_on_unknown_dimension(self) -> None:
        weights = {
            "technical_depth": 0.30,
            "communication": 0.20,
            "problem_solving": 0.20,
            "culture_fit": 0.10,
            "coding_quality": 0.10,
            "charisma": 0.10,  # not a valid dimension
        }
        with pytest.raises(RubricValidationError, match="unknown dimensions"):
            Rubric(weights=weights)

    def test_raises_when_weights_dont_sum_to_one(self) -> None:
        weights = {
            "technical_depth": 0.30,
            "communication": 0.20,
            "problem_solving": 0.20,
            "culture_fit": 0.10,
            "coding_quality": 0.05,  # total = 0.85, not 1.0
        }
        with pytest.raises(RubricValidationError, match="must sum to 1.0"):
            Rubric(weights=weights)

    def test_float_precision_tolerance(self) -> None:
        # 0.1 + 0.2 + 0.2 + 0.3 + 0.2 = 1.0000000000000002 in IEEE 754
        weights = {
            "technical_depth": 0.30,
            "communication": 0.20,
            "problem_solving": 0.20,
            "culture_fit": 0.10,
            "coding_quality": 0.20,
        }
        rubric = Rubric(weights=weights)
        assert rubric.weights is not None

    def test_from_dict(self) -> None:
        rubric = Rubric.from_dict(DEFAULT_RUBRIC)
        assert rubric.weights == DEFAULT_RUBRIC


class TestRubricPresets:
    def test_all_presets_are_valid(self) -> None:
        for name, weights in RUBRIC_PRESETS.items():
            rubric = Rubric(weights=weights)
            total = sum(rubric.weights.values())
            assert abs(total - 1.0) < 0.001, f"Preset '{name}' weights don't sum to 1.0"

    def test_preset_factory(self) -> None:
        rubric = Rubric.preset("technical")
        assert rubric.weights["technical_depth"] == 0.40

    def test_unknown_preset_falls_back_to_default(self) -> None:
        rubric = Rubric.preset("made_up_type")
        assert rubric.weights == DEFAULT_RUBRIC


class TestCompositeComputation:
    def test_perfect_scores_return_ten(self) -> None:
        rubric = Rubric()
        scores = {dim: 10.0 for dim in rubric.weights}
        result = rubric.compute_composite(scores)
        assert result == 10.0

    def test_zero_scores_return_zero(self) -> None:
        rubric = Rubric()
        scores = {dim: 0.0 for dim in rubric.weights}
        result = rubric.compute_composite(scores)
        assert result == 0.0

    def test_weighted_composite_is_correct(self) -> None:
        rubric = Rubric(weights={
            "technical_depth": 0.50,
            "communication": 0.50,
            "problem_solving": 0.00,
            "culture_fit": 0.00,
            "coding_quality": 0.00,
        })
        scores = {
            "technical_depth": 8.0,
            "communication": 6.0,
            "problem_solving": 9.0,  # weight 0, shouldn't affect result
            "culture_fit": 3.0,
            "coding_quality": 3.0,
        }
        result = rubric.compute_composite(scores)
        assert result == pytest.approx(7.0, abs=0.01)

    def test_missing_dimension_defaults_to_five(self) -> None:
        rubric = Rubric(weights={
            "technical_depth": 1.00,
            "communication": 0.00,
            "problem_solving": 0.00,
            "culture_fit": 0.00,
            "coding_quality": 0.00,
        })
        # technical_depth not provided — should default to 5.0
        result = rubric.compute_composite({})
        assert result == pytest.approx(5.0, abs=0.01)

    def test_result_is_rounded_to_two_decimal_places(self) -> None:
        rubric = Rubric()
        scores = {dim: 7.333_333 for dim in rubric.weights}
        result = rubric.compute_composite(scores)
        # Should be 7.33 (rounded to 2 dp)
        assert str(result).count(".") == 1
        decimal_places = len(str(result).split(".")[1])
        assert decimal_places <= 2
