"""
Transcript parsing utilities for the InterviewFlow AI scoring service.

Converts raw WebRTC session transcripts (produced by server-side speech-to-text)
into structured turn-by-turn dialogue suitable for Gemini scoring prompts.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime
from typing import Sequence


@dataclass
class Turn:
    """A single speaker turn in the interview transcript."""

    speaker: str  # "interviewer" | "candidate" | "unknown"
    text: str
    start_ms: int
    end_ms: int
    confidence: float = 1.0

    @property
    def duration_seconds(self) -> float:
        return (self.end_ms - self.start_ms) / 1000.0

    @property
    def word_count(self) -> int:
        return len(self.text.split())

    @property
    def words_per_minute(self) -> float:
        if self.duration_seconds == 0:
            return 0.0
        return self.word_count / self.duration_seconds * 60


@dataclass
class ParsedTranscript:
    """Structured interview transcript ready for AI scoring."""

    session_id: str
    duration_seconds: float
    turns: list[Turn] = field(default_factory=list)

    @property
    def candidate_turns(self) -> list[Turn]:
        return [t for t in self.turns if t.speaker == "candidate"]

    @property
    def interviewer_turns(self) -> list[Turn]:
        return [t for t in self.turns if t.speaker == "interviewer"]

    @property
    def candidate_talk_ratio(self) -> float:
        """Fraction of total speech time attributed to the candidate."""
        candidate_ms = sum(t.end_ms - t.start_ms for t in self.candidate_turns)
        total_ms = sum(t.end_ms - t.start_ms for t in self.turns)
        if total_ms == 0:
            return 0.0
        return candidate_ms / total_ms

    @property
    def avg_response_length_words(self) -> float:
        words = [t.word_count for t in self.candidate_turns]
        if not words:
            return 0.0
        return sum(words) / len(words)

    def to_prompt_text(self, max_words: int = 8000) -> str:
        """
        Formats transcript as a structured dialogue string for the scoring prompt.
        Truncates to `max_words` to respect LLM context limits.
        """
        lines: list[str] = []
        word_count = 0

        for turn in self.turns:
            prefix = f"[{turn.speaker.upper()}]"
            line = f"{prefix} {turn.text}"
            words_in_line = turn.word_count

            if word_count + words_in_line > max_words:
                remaining = max_words - word_count
                if remaining <= 0:
                    break
                # Truncate this turn
                truncated = " ".join(turn.text.split()[:remaining])
                lines.append(f"{prefix} {truncated} [TRUNCATED]")
                break

            lines.append(line)
            word_count += words_in_line

        return "\n".join(lines)

    def stats(self) -> dict:
        return {
            "total_turns": len(self.turns),
            "candidate_turns": len(self.candidate_turns),
            "interviewer_turns": len(self.interviewer_turns),
            "duration_seconds": self.duration_seconds,
            "candidate_talk_ratio": round(self.candidate_talk_ratio, 3),
            "avg_response_length_words": round(self.avg_response_length_words, 1),
        }


class TranscriptParser:
    """
    Parses raw transcript payloads from the WebRTC transcription pipeline.

    Expected input format (from Google Cloud Speech-to-Text streaming results):
    {
        "session_id": "uuid",
        "duration_ms": 3600000,
        "segments": [
            {
                "speaker_tag": 1,
                "start_time_ms": 0,
                "end_time_ms": 4500,
                "transcript": "Tell me about your experience with distributed systems.",
                "confidence": 0.97
            },
            ...
        ],
        "speaker_map": {
            "1": "interviewer",
            "2": "candidate"
        }
    }
    """

    # Minimum confidence to include a segment
    MIN_CONFIDENCE = 0.6

    def parse(self, raw: dict) -> ParsedTranscript:
        """Parse a raw transcript payload into a structured ParsedTranscript."""
        session_id = raw.get("session_id", "unknown")
        duration_ms = raw.get("duration_ms", 0)
        speaker_map: dict[str, str] = raw.get("speaker_map", {})

        turns = []
        for segment in raw.get("segments", []):
            confidence = segment.get("confidence", 1.0)
            if confidence < self.MIN_CONFIDENCE:
                continue

            speaker_tag = str(segment.get("speaker_tag", 0))
            speaker = speaker_map.get(speaker_tag, "unknown")
            text = self._clean_text(segment.get("transcript", ""))

            if not text:
                continue

            turns.append(
                Turn(
                    speaker=speaker,
                    text=text,
                    start_ms=segment.get("start_time_ms", 0),
                    end_ms=segment.get("end_time_ms", 0),
                    confidence=confidence,
                )
            )

        return ParsedTranscript(
            session_id=session_id,
            duration_seconds=duration_ms / 1000.0,
            turns=turns,
        )

    def _clean_text(self, text: str) -> str:
        """Remove filler words and normalize whitespace."""
        # Strip leading/trailing whitespace
        text = text.strip()
        # Collapse multiple spaces
        text = re.sub(r"\s+", " ", text)
        return text
