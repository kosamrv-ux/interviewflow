import { useParams, Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import api from "@/api/client";
import type { Job, Application } from "@/api/client";
import LoadingSpinner from "@/components/LoadingSpinner";
import { formatDistanceToNow } from "date-fns";

interface JobWithMeta extends Job {
  stage_counts?: Record<string, number>;
}

export default function JobDetailPage() {
  const { jobId } = useParams<{ jobId: string }>();

  const { data: job, isLoading: jobLoading } = useQuery<JobWithMeta>({
    queryKey: ["job", jobId],
    queryFn: () => api.getJob(jobId!),
    enabled: !!jobId,
  });

  const { data: applicationsData, isLoading: appsLoading } = useQuery({
    queryKey: ["applications", { job_id: jobId }],
    queryFn: () => api.listApplications({ job_id: jobId, limit: 50 }),
    enabled: !!jobId,
  });

  const applications: Application[] = applicationsData?.data ?? [];

  if (jobLoading || appsLoading) {
    return (
      <div style={{ display: "flex", justifyContent: "center", padding: "60px" }}>
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (!job) {
    return (
      <div style={{ padding: "32px 40px", color: "#6b7280" }}>Job not found.</div>
    );
  }

  const stageCounts = job.stage_counts ?? {};

  return (
    <div style={{ padding: "32px 40px" }}>
      {/* Breadcrumb */}
      <div style={{ fontSize: "13px", color: "#6b7280", marginBottom: "20px" }}>
        <Link to="/jobs" style={{ color: "#6366f1" }}>Jobs</Link>
        <span style={{ margin: "0 6px" }}>›</span>
        <span>{job.title}</span>
      </div>

      {/* Job header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "32px" }}>
        <div>
          <h1 style={{ fontSize: "26px", fontWeight: "700", color: "#111827", margin: "0 0 8px" }}>
            {job.title}
          </h1>
          <div style={{ display: "flex", gap: "16px", flexWrap: "wrap" }}>
            {job.department && <span style={{ fontSize: "13px", color: "#6b7280" }}>📁 {job.department}</span>}
            {job.location && <span style={{ fontSize: "13px", color: "#6b7280" }}>📍 {job.location}</span>}
            <span style={{ fontSize: "13px", color: "#6b7280", textTransform: "capitalize" }}>
              🌐 {job.remote_policy}
            </span>
          </div>
        </div>
        <span style={{
          padding: "6px 14px",
          borderRadius: "6px",
          fontSize: "13px",
          fontWeight: "600",
          backgroundColor: job.status === "open" ? "#dcfce7" : "#f3f4f6",
          color: job.status === "open" ? "#166534" : "#6b7280",
          textTransform: "capitalize",
        }}>
          {job.status}
        </span>
      </div>

      {/* Pipeline stage summary */}
      <div style={{ display: "grid", gridTemplateColumns: `repeat(${job.pipeline_stages.length}, 1fr)`, gap: "12px", marginBottom: "32px" }}>
        {job.pipeline_stages.map((stage) => (
          <div key={stage} style={{
            backgroundColor: "white",
            border: "1px solid #e5e7eb",
            borderRadius: "10px",
            padding: "16px",
            textAlign: "center",
          }}>
            <div style={{ fontSize: "24px", fontWeight: "700", color: "#6366f1" }}>
              {stageCounts[stage] ?? 0}
            </div>
            <div style={{ fontSize: "12px", color: "#6b7280", textTransform: "capitalize", marginTop: "4px" }}>
              {stage}
            </div>
          </div>
        ))}
      </div>

      {/* Applications table */}
      <div style={{ backgroundColor: "white", borderRadius: "12px", border: "1px solid #e5e7eb", padding: "24px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "20px" }}>
          <h2 style={{ fontSize: "16px", fontWeight: "600", color: "#111827" }}>
            Applications ({applications.length})
          </h2>
        </div>

        {applications.length === 0 ? (
          <div style={{ textAlign: "center", padding: "40px", color: "#9ca3af" }}>
            No applications yet.
          </div>
        ) : (
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead>
              <tr style={{ borderBottom: "1px solid #f3f4f6" }}>
                {["Candidate", "Stage", "Score", "Rank", "Applied"].map((col) => (
                  <th key={col} style={{
                    fontSize: "12px", fontWeight: "600", color: "#6b7280",
                    textTransform: "uppercase", letterSpacing: "0.05em",
                    padding: "0 12px 10px 0", textAlign: "left",
                  }}>
                    {col}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {applications.map((app) => (
                <tr key={app.id} style={{ borderBottom: "1px solid #f9fafb" }}>
                  <td style={{ padding: "12px 12px 12px 0" }}>
                    <Link to={`/applications/${app.id}`} style={{ fontSize: "14px", fontWeight: "500", color: "#111827" }}>
                      {app.candidate?.full_name ?? "—"}
                    </Link>
                    {app.candidate?.email && (
                      <div style={{ fontSize: "12px", color: "#9ca3af" }}>{app.candidate.email}</div>
                    )}
                  </td>
                  <td style={{ padding: "12px 12px 12px 0" }}>
                    <span style={{
                      fontSize: "12px", fontWeight: "500",
                      backgroundColor: "#ede9fe", color: "#5b21b6",
                      padding: "3px 8px", borderRadius: "4px", textTransform: "capitalize",
                    }}>
                      {app.pipeline_stage}
                    </span>
                  </td>
                  <td style={{ padding: "12px 12px 12px 0", fontSize: "14px", fontWeight: "600", color: "#374151" }}>
                    {app.composite_score != null ? Number(app.composite_score).toFixed(1) : "—"}
                  </td>
                  <td style={{ padding: "12px 12px 12px 0", fontSize: "13px", color: "#6b7280" }}>
                    {app.rank_within_job != null ? `#${app.rank_within_job}` : "—"}
                  </td>
                  <td style={{ padding: "12px 0", fontSize: "13px", color: "#6b7280" }}>
                    {formatDistanceToNow(new Date(app.applied_at), { addSuffix: true })}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
