/**
 * ScoreCard — displays the AI-generated scorecard for a candidate.
 * Domain-specific component that renders the breakdown radar + per-dimension
 * scores with rationale. Used on the ApplicationDetailPage.
 */

import {
  RadarChart,
  Radar,
  PolarGrid,
  PolarAngleAxis,
  PolarRadiusAxis,
  ResponsiveContainer,
  Tooltip,
} from "recharts";
import type { AiScore } from "@/api/client";

interface ScoreCardProps {
  score: AiScore;
  showRawBreakdown?: boolean;
}

const DIMENSION_LABELS: Record<string, string> = {
  technical_depth: "Technical Depth",
  communication: "Communication",
  problem_solving: "Problem Solving",
  culture_fit: "Culture Fit",
  role_fit: "Role Fit",
};

const ACTION_COLORS: Record<string, { bg: string; text: string }> = {
  advance: { bg: "#dcfce7", text: "#166534" },
  hold: { bg: "#fef9c3", text: "#713f12" },
  reject: { bg: "#fee2e2", text: "#991b1b" },
};

function ScoreBar({ score, maxScore = 10 }: { score: number; maxScore?: number }) {
  const pct = (score / maxScore) * 100;
  const color =
    score >= 7.5 ? "#22c55e" : score >= 5 ? "#f59e0b" : "#ef4444";

  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: "12px",
      }}
    >
      <div
        style={{
          flex: 1,
          height: "8px",
          backgroundColor: "#f3f4f6",
          borderRadius: "4px",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            width: `${pct}%`,
            height: "100%",
            backgroundColor: color,
            borderRadius: "4px",
            transition: "width 600ms ease-out",
          }}
        />
      </div>
      <span
        style={{
          fontSize: "14px",
          fontWeight: "600",
          color: "#374151",
          minWidth: "32px",
          textAlign: "right",
        }}
      >
        {score.toFixed(1)}
      </span>
    </div>
  );
}

export default function ScoreCard({
  score,
  showRawBreakdown = false,
}: ScoreCardProps) {
  const { breakdown, composite_score, recommended_action, strengths, areas_for_growth, status } = score;

  const radarData = Object.entries(breakdown).map(([key, val]) => ({
    dimension: DIMENSION_LABELS[key] ?? key,
    score: val.score,
    fullMark: 10,
  }));

  const actionStyle = ACTION_COLORS[recommended_action] ?? ACTION_COLORS.hold;

  return (
    <div
      style={{
        backgroundColor: "white",
        borderRadius: "12px",
        border: "1px solid #e5e7eb",
        padding: "24px",
        maxWidth: "720px",
      }}
    >
      {/* Header */}
      <div
        style={{
          display: "flex",
          alignItems: "flex-start",
          justifyContent: "space-between",
          marginBottom: "24px",
        }}
      >
        <div>
          <div style={{ fontSize: "13px", color: "#6b7280", marginBottom: "4px" }}>
            AI Composite Score
            {status === "overridden" && (
              <span
                style={{
                  marginLeft: "8px",
                  fontSize: "11px",
                  backgroundColor: "#fef3c7",
                  color: "#92400e",
                  padding: "2px 6px",
                  borderRadius: "4px",
                }}
              >
                OVERRIDDEN
              </span>
            )}
          </div>
          <div style={{ fontSize: "42px", fontWeight: "700", color: "#111827" }}>
            {Number(composite_score).toFixed(1)}
            <span style={{ fontSize: "18px", color: "#9ca3af" }}>/10</span>
          </div>
        </div>

        <div
          style={{
            padding: "8px 16px",
            borderRadius: "8px",
            backgroundColor: actionStyle.bg,
            color: actionStyle.text,
            fontSize: "14px",
            fontWeight: "600",
            textTransform: "uppercase",
            letterSpacing: "0.05em",
          }}
        >
          {recommended_action}
        </div>
      </div>

      {/* Radar chart */}
      <div style={{ height: "240px", marginBottom: "24px" }}>
        <ResponsiveContainer width="100%" height="100%">
          <RadarChart data={radarData} margin={{ top: 10, right: 20, bottom: 10, left: 20 }}>
            <PolarGrid stroke="#e5e7eb" />
            <PolarAngleAxis dataKey="dimension" tick={{ fontSize: 12, fill: "#6b7280" }} />
            <PolarRadiusAxis domain={[0, 10]} tick={false} axisLine={false} />
            <Radar
              name="Score"
              dataKey="score"
              stroke="#6366f1"
              fill="#6366f1"
              fillOpacity={0.2}
              strokeWidth={2}
            />
            <Tooltip
              formatter={(val: number) => [`${val.toFixed(1)}/10`, "Score"]}
              contentStyle={{ borderRadius: "8px", border: "1px solid #e5e7eb" }}
            />
          </RadarChart>
        </ResponsiveContainer>
      </div>

      {/* Per-dimension breakdown */}
      <div style={{ marginBottom: "24px" }}>
        <h3 style={{ fontSize: "14px", fontWeight: "600", color: "#374151", marginBottom: "16px" }}>
          Score Breakdown
        </h3>
        <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
          {Object.entries(breakdown).map(([key, val]) => (
            <div key={key}>
              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  marginBottom: "6px",
                }}
              >
                <span style={{ fontSize: "13px", fontWeight: "500", color: "#374151" }}>
                  {DIMENSION_LABELS[key] ?? key}
                </span>
                <span style={{ fontSize: "12px", color: "#9ca3af" }}>
                  weight: {(val.weight * 100).toFixed(0)}%
                </span>
              </div>
              <ScoreBar score={val.score} />
              {showRawBreakdown && val.rationale && (
                <p style={{ fontSize: "12px", color: "#6b7280", marginTop: "6px", lineHeight: "1.5" }}>
                  {val.rationale}
                </p>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Strengths & growth areas */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "16px" }}>
        <div>
          <h4 style={{ fontSize: "13px", fontWeight: "600", color: "#166534", marginBottom: "8px" }}>
            Strengths
          </h4>
          <ul style={{ listStyle: "none", display: "flex", flexDirection: "column", gap: "4px" }}>
            {(strengths ?? []).map((s, i) => (
              <li key={i} style={{ fontSize: "13px", color: "#374151", display: "flex", gap: "6px" }}>
                <span style={{ color: "#22c55e" }}>✓</span>
                {s}
              </li>
            ))}
          </ul>
        </div>
        <div>
          <h4 style={{ fontSize: "13px", fontWeight: "600", color: "#991b1b", marginBottom: "8px" }}>
            Areas for Growth
          </h4>
          <ul style={{ listStyle: "none", display: "flex", flexDirection: "column", gap: "4px" }}>
            {(areas_for_growth ?? []).map((a, i) => (
              <li key={i} style={{ fontSize: "13px", color: "#374151", display: "flex", gap: "6px" }}>
                <span style={{ color: "#f59e0b" }}>△</span>
                {a}
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
}
