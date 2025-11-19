/**
 * DashboardPage — Recruiter pipeline overview.
 *
 * Shows:
 * - Summary KPI cards (open jobs, active applications, interviews today)
 * - Application pipeline funnel across all open jobs
 * - Recent applications with AI scores
 */

import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { useAuthStore } from "@/hooks/useAuthStore";
import api from "@/api/client";
import type { Application, Job } from "@/api/client";
import LoadingSpinner from "@/components/LoadingSpinner";
import { formatDistanceToNow } from "date-fns";

interface KpiCardProps {
  label: string;
  value: string | number;
  sub?: string;
  accent?: string;
}

function KpiCard({ label, value, sub, accent = "#6366f1" }: KpiCardProps) {
  return (
    <div
      style={{
        backgroundColor: "white",
        borderRadius: "12px",
        border: "1px solid #e5e7eb",
        padding: "20px 24px",
        display: "flex",
        flexDirection: "column",
        gap: "6px",
      }}
    >
      <div style={{ fontSize: "13px", color: "#6b7280", fontWeight: "500" }}>
        {label}
      </div>
      <div style={{ fontSize: "32px", fontWeight: "700", color: accent }}>
        {value}
      </div>
      {sub && <div style={{ fontSize: "12px", color: "#9ca3af" }}>{sub}</div>}
    </div>
  );
}

function PipelineStageBar({
  stage,
  count,
  total,
}: {
  stage: string;
  count: number;
  total: number;
}) {
  const pct = total > 0 ? (count / total) * 100 : 0;

  return (
    <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
      <div
        style={{
          fontSize: "13px",
          color: "#374151",
          width: "90px",
          textTransform: "capitalize",
          flexShrink: 0,
        }}
      >
        {stage}
      </div>
      <div
        style={{
          flex: 1,
          height: "24px",
          backgroundColor: "#f3f4f6",
          borderRadius: "6px",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            width: `${pct}%`,
            height: "100%",
            backgroundColor: "#6366f1",
            borderRadius: "6px",
            transition: "width 400ms ease-out",
            minWidth: pct > 0 ? "4px" : "0",
          }}
        />
      </div>
      <div
        style={{
          fontSize: "13px",
          fontWeight: "600",
          color: "#374151",
          width: "28px",
          textAlign: "right",
          flexShrink: 0,
        }}
      >
        {count}
      </div>
    </div>
  );
}

function ScoreBadge({ score }: { score: number | null }) {
  if (score === null) return <span style={{ color: "#9ca3af", fontSize: "13px" }}>—</span>;

  const color =
    score >= 7.5 ? "#16a34a" : score >= 5 ? "#d97706" : "#dc2626";
  const bg =
    score >= 7.5 ? "#dcfce7" : score >= 5 ? "#fef3c7" : "#fee2e2";

  return (
    <span
      style={{
        fontSize: "13px",
        fontWeight: "600",
        color,
        backgroundColor: bg,
        padding: "2px 8px",
        borderRadius: "4px",
      }}
    >
      {Number(score).toFixed(1)}
    </span>
  );
}

export default function DashboardPage() {
  const user = useAuthStore((s) => s.user);

  const { data: jobsData, isLoading: jobsLoading } = useQuery({
    queryKey: ["jobs", { status: "open" }],
    queryFn: () => api.listJobs({ status: "open" }),
  });

  const { data: recentApps, isLoading: appsLoading } = useQuery({
    queryKey: ["applications", { status: "active", limit: 10 }],
    queryFn: () => api.listApplications({ status: "active", limit: 10 }),
  });

  const openJobs: Job[] = jobsData?.data ?? [];
  const applications: Application[] = recentApps?.data ?? [];

  // Aggregate pipeline counts across all open jobs
  const stageCounts = applications.reduce<Record<string, number>>(
    (acc, app) => {
      acc[app.pipeline_stage] = (acc[app.pipeline_stage] ?? 0) + 1;
      return acc;
    },
    {},
  );
  const totalApplications = applications.length;

  const DEFAULT_STAGES = ["applied", "screen", "interview", "offer"];
  const stages = Object.keys(stageCounts).length > 0
    ? Object.keys(stageCounts)
    : DEFAULT_STAGES;

  if (jobsLoading || appsLoading) {
    return (
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          height: "100vh",
        }}
      >
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  return (
    <div style={{ padding: "32px 40px" }}>
      {/* Header */}
      <div style={{ marginBottom: "32px" }}>
        <h1
          style={{
            fontSize: "24px",
            fontWeight: "700",
            color: "#111827",
            margin: "0 0 4px",
          }}
        >
          Good morning, {user?.full_name.split(" ")[0]} 👋
        </h1>
        <p style={{ fontSize: "14px", color: "#6b7280", margin: 0 }}>
          Here&apos;s your recruiting pipeline at a glance.
        </p>
      </div>

      {/* KPI row */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
          gap: "16px",
          marginBottom: "32px",
        }}
      >
        <KpiCard label="Open Jobs" value={openJobs.length} />
        <KpiCard
          label="Active Applications"
          value={totalApplications}
          accent="#0891b2"
        />
        <KpiCard
          label="In Interview Stage"
          value={stageCounts["interview"] ?? 0}
          sub="Awaiting scoring"
          accent="#7c3aed"
        />
        <KpiCard
          label="Offers Extended"
          value={stageCounts["offer"] ?? 0}
          accent="#059669"
        />
      </div>

      {/* Main content: pipeline funnel + recent applications */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "1fr 2fr",
          gap: "24px",
        }}
      >
        {/* Pipeline funnel */}
        <div
          style={{
            backgroundColor: "white",
            borderRadius: "12px",
            border: "1px solid #e5e7eb",
            padding: "24px",
          }}
        >
          <h2
            style={{
              fontSize: "16px",
              fontWeight: "600",
              color: "#111827",
              marginBottom: "20px",
            }}
          >
            Pipeline Overview
          </h2>
          <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
            {stages.map((stage) => (
              <PipelineStageBar
                key={stage}
                stage={stage}
                count={stageCounts[stage] ?? 0}
                total={totalApplications}
              />
            ))}
          </div>
          {totalApplications === 0 && (
            <p
              style={{
                fontSize: "13px",
                color: "#9ca3af",
                textAlign: "center",
                marginTop: "16px",
              }}
            >
              No active applications
            </p>
          )}
        </div>

        {/* Recent applications table */}
        <div
          style={{
            backgroundColor: "white",
            borderRadius: "12px",
            border: "1px solid #e5e7eb",
            padding: "24px",
          }}
        >
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center",
              marginBottom: "20px",
            }}
          >
            <h2 style={{ fontSize: "16px", fontWeight: "600", color: "#111827" }}>
              Recent Applications
            </h2>
            <Link
              to="/jobs"
              style={{ fontSize: "13px", color: "#6366f1", fontWeight: "500" }}
            >
              View all jobs →
            </Link>
          </div>

          {applications.length === 0 ? (
            <div
              style={{
                textAlign: "center",
                padding: "40px 0",
                color: "#9ca3af",
                fontSize: "14px",
              }}
            >
              <div style={{ fontSize: "40px", marginBottom: "12px" }}>📭</div>
              No applications yet. Post your first job to get started.
            </div>
          ) : (
            <table style={{ width: "100%", borderCollapse: "collapse" }}>
              <thead>
                <tr
                  style={{
                    borderBottom: "1px solid #f3f4f6",
                    textAlign: "left",
                  }}
                >
                  {["Candidate", "Stage", "Score", "Applied"].map((col) => (
                    <th
                      key={col}
                      style={{
                        fontSize: "12px",
                        fontWeight: "600",
                        color: "#6b7280",
                        textTransform: "uppercase",
                        letterSpacing: "0.05em",
                        padding: "0 0 10px",
                        paddingRight: col !== "Applied" ? "16px" : "0",
                      }}
                    >
                      {col}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {applications.map((app) => (
                  <tr
                    key={app.id}
                    style={{ borderBottom: "1px solid #f9fafb" }}
                  >
                    <td style={{ padding: "12px 16px 12px 0" }}>
                      <Link
                        to={`/applications/${app.id}`}
                        style={{
                          fontSize: "14px",
                          fontWeight: "500",
                          color: "#111827",
                        }}
                      >
                        {app.candidate?.full_name ?? "—"}
                      </Link>
                      {app.job && (
                        <div style={{ fontSize: "12px", color: "#9ca3af" }}>
                          {app.job.title}
                        </div>
                      )}
                    </td>
                    <td style={{ padding: "12px 16px 12px 0" }}>
                      <span
                        style={{
                          fontSize: "12px",
                          fontWeight: "500",
                          backgroundColor: "#ede9fe",
                          color: "#5b21b6",
                          padding: "3px 8px",
                          borderRadius: "4px",
                          textTransform: "capitalize",
                        }}
                      >
                        {app.pipeline_stage}
                      </span>
                    </td>
                    <td style={{ padding: "12px 16px 12px 0" }}>
                      <ScoreBadge score={app.composite_score} />
                    </td>
                    <td style={{ padding: "12px 0", fontSize: "13px", color: "#6b7280" }}>
                      {formatDistanceToNow(new Date(app.applied_at), {
                        addSuffix: true,
                      })}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  );
}
