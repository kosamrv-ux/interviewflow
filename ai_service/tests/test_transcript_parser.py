"""Tests for the TranscriptParser and ParsedTranscript classes."""

import pytest
from app.transcript_parser import TranscriptParser, ParsedTranscript, Turn


@pytest.fixture
def parser() -> TranscriptParser:
    return TranscriptParser()


@pytest.fixture
def sample_raw_transcript() -> dict:
    return {
        "session_id": "sess-123",
        "duration_ms": 3600000,
        "speaker_map": {"1": "interviewer", "2": "candidate"},
        "segments": [
            {
                "speaker_tag": 1,
                "start_time_ms": 0,
                "end_time_ms": 5000,
                "transcript": "Tell me about your experience with distributed systems.",
                "confidence": 0.97,
            },
            {
                "speaker_tag": 2,
                "start_time_ms": 5200,
                "end_time_ms": 45000,
                "transcript": (
                    "I have spent about four years working on distributed systems at my previous company. "
                    "We used Apache Kafka for event streaming and built microservices in Elixir."
                ),
                "confidence": 0.95,
            },
            {
                "speaker_tag": 1,
                "start_time_ms": 45500,
                "end_time_ms": 52000,
                "transcript": "How did you handle consistency challenges?",
                "confidence": 0.98,
            },
            {
                "speaker_tag": 2,
                "start_time_ms": 52500,
                "end_time_ms": 120000,
                "transcript": (
                    "We relied heavily on eventual consistency with compensating transactions. "
                    "For critical financial operations we used two-phase commit with a saga pattern."
                ),
                "confidence": 0.93,
            },
            # Low-confidence segment should be filtered
            {
                "speaker_tag": 2,
                "start_time_ms": 121000,
                "end_time_ms": 125000,
                "transcript": "mumble mumble something unclear",
                "confidence": 0.35,
            },
        ],
    }


class TestTranscriptParser:
    def test_parse_returns_parsed_transcript(self, parser, sample_raw_transcript):
        result = parser.parse(sample_raw_transcript)
        assert isinstance(result, ParsedTranscript)

    def test_parse_sets_session_id(self, parser, sample_raw_transcript):
        result = parser.parse(sample_raw_transcript)
        assert result.session_id == "sess-123"

    def test_parse_sets_duration(self, parser, sample_raw_transcript):
        result = parser.parse(sample_raw_transcript)
        assert result.duration_seconds == 3600.0

    def test_parse_filters_low_confidence_segments(self, parser, sample_raw_transcript):
        result = parser.parse(sample_raw_transcript)
        # 4 segments pass the 0.6 threshold; the 0.35 one is filtered
        assert len(result.turns) == 4

    def test_parse_assigns_correct_speaker_roles(self, parser, sample_raw_transcript):
        result = parser.parse(sample_raw_transcript)
        speakers = [t.speaker for t in result.turns]
        assert speakers[0] == "interviewer"
        assert speakers[1] == "candidate"

    def test_parse_handles_missing_speaker_map(self, parser):
        raw = {
            "session_id": "s",
            "duration_ms": 1000,
            "segments": [
                {"speaker_tag": 99, "start_time_ms": 0, "end_time_ms": 500,
                 "transcript": "Hello", "confidence": 0.9}
            ],
        }
        result = parser.parse(raw)
        assert result.turns[0].speaker == "unknown"

    def test_parse_ignores_empty_transcript_segments(self, parser):
        raw = {
            "session_id": "s",
            "duration_ms": 1000,
            "speaker_map": {"1": "interviewer"},
            "segments": [
                {"speaker_tag": 1, "start_time_ms": 0, "end_time_ms": 500,
                 "transcript": "   ", "confidence": 0.9}
            ],
        }
        result = parser.parse(raw)
        assert len(result.turns) == 0


class TestParsedTranscript:
    @pytest.fixture
    def transcript(self, parser, sample_raw_transcript):
        return parser.parse(sample_raw_transcript)

    def test_candidate_turns(self, transcript):
        assert len(transcript.candidate_turns) == 2

    def test_interviewer_turns(self, transcript):
        assert len(transcript.interviewer_turns) == 2

    def test_candidate_talk_ratio_between_0_and_1(self, transcript):
        ratio = transcript.candidate_talk_ratio
        assert 0.0 <= ratio <= 1.0

    def test_avg_response_length_is_positive(self, transcript):
        avg = transcript.avg_response_length_words
        assert avg > 0

    def test_to_prompt_text_contains_speaker_labels(self, transcript):
        text = transcript.to_prompt_text()
        assert "[INTERVIEWER]" in text
        assert "[CANDIDATE]" in text

    def test_to_prompt_text_truncates_at_word_limit(self, transcript):
        text = transcript.to_prompt_text(max_words=10)
        assert "[TRUNCATED]" in text or len(text.split()) <= 15

    def test_stats_returns_expected_keys(self, transcript):
        stats = transcript.stats()
        assert "total_turns" in stats
        assert "candidate_turns" in stats
        assert "candidate_talk_ratio" in stats
        assert "duration_seconds" in stats


class TestTurn:
    def test_word_count(self):
        turn = Turn(speaker="candidate", text="hello world foo", start_ms=0, end_ms=5000)
        assert turn.word_count == 3

    def test_duration_seconds(self):
        turn = Turn(speaker="candidate", text="test", start_ms=0, end_ms=10000)
        assert turn.duration_seconds == 10.0

    def test_words_per_minute(self):
        # 60 words in 60 seconds = 60 WPM
        text = " ".join(["word"] * 60)
        turn = Turn(speaker="candidate", text=text, start_ms=0, end_ms=60000)
        assert turn.words_per_minute == pytest.approx(60.0)
