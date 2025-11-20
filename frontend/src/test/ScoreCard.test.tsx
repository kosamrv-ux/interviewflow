import { render, screen } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import ScoreCard from "@/components/ScoreCard";
import type { AiScore } from "@/api/client";

const mockScore: AiScore = {
  id: "score-abc-123",
  composite_score: 8.25,
  breakdown: {
    technical_depth: {
      score: 9.0,
      weight: 0.35,
      rationale: "Strong systems design and clean code.",
    },
    communication: {
      score: 7.5,
      weight: 0.25,
      rationale: "Clear but occasionally verbose.",
    },
    problem_solving: {
      score: 9.0,
      weight: 0.2,
      rationale: "Excellent decomposition and edge case handling.",
    },
    culture_fit: {
      score: 7.0,
      weight: 0.1,
      rationale: "Collaborative signals present.",
    },
    role_fit: {
      score: 8.0,
      weight: 0.1,
      rationale: "Strong backend background.",
    },
  },
  strengths: ["Deep distributed systems knowledge", "Clean, idiomatic code"],
  areas_for_growth: ["Active listening", "Conciseness"],
  recommended_action: "advance",
  confidence: 0.91,
  status: "completed",
  inserted_at: "2025-11-20T14:00:00Z",
};

describe("ScoreCard", () => {
  it("renders the composite score prominently", () => {
    render(<ScoreCard score={mockScore} />);
    expect(screen.getByText("8.3")).toBeInTheDocument();
  });

  it("shows the recommended action badge", () => {
    render(<ScoreCard score={mockScore} />);
    expect(
      screen.getByText((content) => content.toLowerCase().includes("advance")),
    ).toBeInTheDocument();
  });

  it("renders all 5 dimension labels", () => {
    render(<ScoreCard score={mockScore} />);
    expect(screen.getByText("Technical Depth")).toBeInTheDocument();
    expect(screen.getByText("Communication")).toBeInTheDocument();
    expect(screen.getByText("Problem Solving")).toBeInTheDocument();
    expect(screen.getByText("Culture Fit")).toBeInTheDocument();
    expect(screen.getByText("Role Fit")).toBeInTheDocument();
  });

  it("renders strengths list", () => {
    render(<ScoreCard score={mockScore} />);
    expect(
      screen.getByText("Deep distributed systems knowledge"),
    ).toBeInTheDocument();
    expect(screen.getByText("Clean, idiomatic code")).toBeInTheDocument();
  });

  it("renders growth areas", () => {
    render(<ScoreCard score={mockScore} />);
    expect(screen.getByText("Active listening")).toBeInTheDocument();
    expect(screen.getByText("Conciseness")).toBeInTheDocument();
  });

  it("shows OVERRIDDEN badge when status is overridden", () => {
    const overriddenScore = { ...mockScore, status: "overridden" as const };
    render(<ScoreCard score={overriddenScore} />);
    expect(screen.getByText("OVERRIDDEN")).toBeInTheDocument();
  });

  it("shows rationale when showRawBreakdown is true", () => {
    render(<ScoreCard score={mockScore} showRawBreakdown />);
    expect(
      screen.getByText("Strong systems design and clean code."),
    ).toBeInTheDocument();
  });

  it("does not show rationale when showRawBreakdown is false", () => {
    render(<ScoreCard score={mockScore} showRawBreakdown={false} />);
    expect(
      screen.queryByText("Strong systems design and clean code."),
    ).not.toBeInTheDocument();
  });
});
