/**
 * JobsPage — Lists all jobs for the company with search, filter, and creation.
 */

import { useState } from "react";
import { Link } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import api from "@/api/client";
import type { Job } from "@/api/client";
import LoadingSpinner from "@/components/LoadingSpinner";

const STATUS_LABELS: Record<string, { label: string; color: string; bg: string }> = {
  draft: { label: "Draft", color: "#92400e", bg: "#fef3c7" },
  open: { label: "Open", color: "#166534", bg: "#dcfce7" },
  paused: { label: "Paused", color: "#1e40af", bg: "#dbeafe" },
  closed: { label: "Closed", color: "#6b7280", bg: "#f3f4f6" },
  archived: { label: "Archived", color: "#9ca3af", bg: "#f9fafb" },
};

function JobStatusBadge({ status }: { status: Job["status"] }) {
  const style = STATUS_LABELS[status] ?? STATUS_LABELS.draft;
  return (
    <span
      style={{
        fontSize: "12px",
        fontWeight: "600",
        color: style.color,
        backgroundColor: style.bg,
        padding: "3px 8px",
        borderRadius: "4px",
      }}
    >
      {style.label}
    </span>
  );
}

function JobCard({ job }: { job: Job }) {
  const queryClient = useQueryClient();

  const publishMutation = useMutation({
    mutationFn: () => api.publishJob(job.id),
    onSuccess: (updatedJob) => {
      queryClient.setQueryData<{ data: Job[] }>(
        ["jobs"],
        (old) => old
          ? { ...old, data: old.data.map((j) => (j.id === updatedJob.id ? updatedJob : j)) }
          : old,
      );
    },
  });

  return (
    <div
      style={{
        backgroundColor: "white",
        borderRadius: "10px",
        border: "1px solid #e5e7eb",
        padding: "20px 24px",
        display: "flex",
        alignItems: "flex-start",
        justifyContent: "space-between",
        transition: "box-shadow 150ms",
      }}
    >
      <div style={{ flex: 1 }}>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: "10px",
            marginBottom: "6px",
          }}
        >
          <Link
            to={`/jobs/${job.id}`}
            style={{
              fontSize: "16px",
              fontWeight: "600",
              color: "#111827",
              textDecoration: "none",
            }}
          >
            {job.title}
          </Link>
          <JobStatusBadge status={job.status} />
        </div>

        <div
          style={{
            display: "flex",
            gap: "16px",
            flexWrap: "wrap",
          }}
        >
          {job.department && (
            <span style={{ fontSize: "13px", color: "#6b7280" }}>
              📁 {job.department}
            </span>
          )}
          {job.location && (
            <span style={{ fontSize: "13px", color: "#6b7280" }}>
              📍 {job.location}
            </span>
          )}
          <span style={{ fontSize: "13px", color: "#6b7280", textTransform: "capitalize" }}>
            🌐 {job.remote_policy.replace("_", " ")}
          </span>
          {job.salary_min && job.salary_max && (
            <span style={{ fontSize: "13px", color: "#6b7280" }}>
              💵 ${(job.salary_min / 100).toLocaleString()} – ${(job.salary_max / 100).toLocaleString()}
            </span>
          )}
        </div>
      </div>

      <div style={{ display: "flex", gap: "8px", flexShrink: 0, marginLeft: "16px" }}>
        {job.status === "draft" && (
          <button
            onClick={() => publishMutation.mutate()}
            disabled={publishMutation.isPending}
            style={{
              padding: "8px 16px",
              fontSize: "13px",
              fontWeight: "500",
              color: "white",
              backgroundColor: "#6366f1",
              border: "none",
              borderRadius: "6px",
              cursor: publishMutation.isPending ? "not-allowed" : "pointer",
              opacity: publishMutation.isPending ? 0.7 : 1,
            }}
          >
            {publishMutation.isPending ? "Publishing…" : "Publish"}
          </button>
        )}
        <Link
          to={`/jobs/${job.id}`}
          style={{
            padding: "8px 16px",
            fontSize: "13px",
            fontWeight: "500",
            color: "#374151",
            backgroundColor: "#f9fafb",
            border: "1px solid #e5e7eb",
            borderRadius: "6px",
            textDecoration: "none",
          }}
        >
          View
        </Link>
      </div>
    </div>
  );
}

export default function JobsPage() {
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<string>("");

  const { data, isLoading, error } = useQuery({
    queryKey: ["jobs", { search: search || undefined, status: statusFilter || undefined }],
    queryFn: () =>
      api.listJobs({
        search: search || undefined,
        status: statusFilter || undefined,
      }),
    staleTime: 15_000,
  });

  const jobs: Job[] = data?.data ?? [];

  return (
    <div style={{ padding: "32px 40px" }}>
      {/* Header */}
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "flex-start",
          marginBottom: "28px",
        }}
      >
        <div>
          <h1
            style={{
              fontSize: "24px",
              fontWeight: "700",
              color: "#111827",
              margin: "0 0 4px",
            }}
          >
            Jobs
          </h1>
          <p style={{ fontSize: "14px", color: "#6b7280", margin: 0 }}>
            {data?.meta.total ?? 0} job
            {(data?.meta.total ?? 0) !== 1 ? "s" : ""} total
          </p>
        </div>
        <Link
          to="/jobs/new"
          style={{
            padding: "10px 20px",
            fontSize: "14px",
            fontWeight: "600",
            color: "white",
            backgroundColor: "#6366f1",
            borderRadius: "8px",
            textDecoration: "none",
          }}
        >
          + Create Job
        </Link>
      </div>

      {/* Filters */}
      <div
        style={{
          display: "flex",
          gap: "12px",
          marginBottom: "24px",
        }}
      >
        <input
          type="search"
          placeholder="Search jobs..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          style={{
            flex: 1,
            maxWidth: "360px",
            padding: "9px 14px",
            fontSize: "14px",
            border: "1px solid #d1d5db",
            borderRadius: "8px",
            outline: "none",
            backgroundColor: "white",
          }}
        />
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          style={{
            padding: "9px 14px",
            fontSize: "14px",
            border: "1px solid #d1d5db",
            borderRadius: "8px",
            outline: "none",
            backgroundColor: "white",
            color: "#374151",
          }}
        >
          <option value="">All statuses</option>
          <option value="draft">Draft</option>
          <option value="open">Open</option>
          <option value="paused">Paused</option>
          <option value="closed">Closed</option>
        </select>
      </div>

      {/* Content */}
      {isLoading ? (
        <div style={{ display: "flex", justifyContent: "center", paddingTop: "60px" }}>
          <LoadingSpinner size="lg" />
        </div>
      ) : error ? (
        <div
          style={{
            backgroundColor: "#fee2e2",
            color: "#991b1b",
            padding: "16px",
            borderRadius: "8px",
            fontSize: "14px",
          }}
        >
          Failed to load jobs. Please refresh the page.
        </div>
      ) : jobs.length === 0 ? (
        <div
          style={{
            textAlign: "center",
            padding: "80px 0",
            color: "#6b7280",
          }}
        >
          <div style={{ fontSize: "48px", marginBottom: "16px" }}>💼</div>
          <h2 style={{ fontSize: "18px", fontWeight: "600", color: "#374151", marginBottom: "8px" }}>
            {search || statusFilter ? "No jobs match your filters" : "No jobs yet"}
          </h2>
          <p style={{ fontSize: "14px" }}>
            {search || statusFilter
              ? "Try adjusting your search or filter."
              : "Create your first job posting to start hiring."}
          </p>
        </div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
          {jobs.map((job) => (
            <JobCard key={job.id} job={job} />
          ))}
        </div>
      )}
    </div>
  );
}
