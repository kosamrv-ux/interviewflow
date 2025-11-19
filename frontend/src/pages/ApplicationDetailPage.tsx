/**
 * ApplicationDetailPage — Full application view with candidate profile,
 * interview history, and AI scorecard.
 */

import { useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import api from "@/api/client";
import type { Application, AiScore } from "@/api/client";
import ScoreCard from "@/components/ScoreCard";
import LoadingSpinner from "@/components/LoadingSpinner";
import { format } from "date-fns";

interface ApplicationWithDetails extends Application {
  candidate?: {
    id: string;
    full_name: string;
    email: string;
    linkedin_url?: string;
    github_url?: string;
    source?: string;
    tags?: string[];
  };
  job?: {
    id: string;
    title: string;
    pipeline_stages: string[];
  };
  interviews?: Array<{
    id: string;
    title: string;
    interview_type: string;
    scheduled_at: string;
    status: string;
    duration_minutes: number;
  }>;
  latest_score?: AiScore | null;
}

const REJECTION_REASONS = [
  { value: "underqualified", label: "Underqualified" },
  { value: "overqualified", label: "Overqualified" },
  { value: "failed_assessment", label: "Failed Assessment" },
  { value: "culture_fit", label: "Culture Fit" },
  { value: "position_filled", label: "Position Filled" },
  { value: "withdrew", label: "Candidate Withdrew" },
  { value: "no_response", label: "No Response" },
  { value: "other", label: "Other" },
];

export default function ApplicationDetailPage() {
  const { applicationId } = useParams<{ applicationId: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const [showRejectModal, setShowRejectModal] = useState(false);
  const [rejectReason, setRejectReason] = useState("");

  const { data: application, isLoading } = useQuery<ApplicationWithDetails>({
    queryKey: ["application", applicationId],
    queryFn: () => api.get(`/applications/${applicationId!}`),
    enabled: !!applicationId,
  });

  const advanceMutation = useMutation({
    mutationFn: (stage: string) =>
      api.advanceApplication(applicationId!, stage),
    onSuccess: (updated) => {
      queryClient.setQueryData(["application", applicationId], (old: ApplicationWithDetails | undefined) =>
        old ? { ...old, pipeline_stage: updated.pipeline_stage } : old,
      );
      queryClient.invalidateQueries({ queryKey: ["applications"] });
    },
  });

  const rejectMutation = useMutation({
    mutationFn: (reason: string) =>
      api.rejectApplication(applicationId!, reason),
    onSuccess: () => {
      setShowRejectModal(false);
      queryClient.invalidateQueries({ queryKey: ["application", applicationId] });
      queryClient.invalidateQueries({ queryKey: ["applications"] });
    },
  });

  const hireMutation = useMutation({
    mutationFn: () => api.post(`/applications/${applicationId!}/hire`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["application", applicationId] });
      navigate("/dashboard");
    },
  });

  if (isLoading) {
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

  if (!application) {
    return (
      <div style={{ padding: "32px 40px" }}>
        <p style={{ color: "#6b7280" }}>Application not found.</p>
      </div>
    );
  }

  const { candidate, job, interviews = [], latest_score } = application;

  // Figure out next stage
  const stages = job?.pipeline_stages ?? [];
  const currentIdx = stages.indexOf(application.pipeline_stage);
  const nextStage = stages[currentIdx + 1];
  const isActive = application.status === "active";

  return (
    <div style={{ padding: "32px 40px" }}>
      {/* Breadcrumb */}
      <div style={{ fontSize: "13px", color: "#6b7280", marginBottom: "20px" }}>
        <span
          style={{ cursor: "pointer", color: "#6366f1" }}
          onClick={() => navigate(-1)}
        >
          ← Back
        </span>
        {job && (
          <>
            <span style={{ margin: "0 6px" }}>·</span>
            <span>{job.title}</span>
          </>
        )}
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 340px", gap: "24px" }}>
        {/* Main column */}
        <div style={{ display: "flex", flexDirection: "column", gap: "20px" }}>
          {/* Candidate header */}
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
                alignItems: "flex-start",
                justifyContent: "space-between",
              }}
            >
              <div style={{ display: "flex", gap: "16px", alignItems: "center" }}>
                <div
                  style={{
                    width: "56px",
                    height: "56px",
                    borderRadius: "50%",
                    backgroundColor: "#ede9fe",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    fontSize: "22px",
                    fontWeight: "600",
                    color: "#5b21b6",
                    flexShrink: 0,
                  }}
                >
                  {candidate?.full_name.charAt(0).toUpperCase()}
                </div>
                <div>
                  <h1
                    style={{
                      fontSize: "22px",
                      fontWeight: "700",
                      color: "#111827",
                      margin: "0 0 4px",
                    }}
                  >
                    {candidate?.full_name}
                  </h1>
                  <div style={{ fontSize: "14px", color: "#6b7280" }}>
                    {candidate?.email}
                  </div>
                  <div
                    style={{
                      display: "flex",
                      gap: "10px",
                      marginTop: "6px",
                    }}
                  >
                    {candidate?.linkedin_url && (
                      <a
                        href={candidate.linkedin_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        style={{ fontSize: "13px", color: "#6366f1" }}
                      >
                        LinkedIn ↗
                      </a>
                    )}
                    {candidate?.github_url && (
                      <a
                        href={candidate.github_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        style={{ fontSize: "13px", color: "#6366f1" }}
                      >
                        GitHub ↗
                      </a>
                    )}
                  </div>
                </div>
              </div>

              {/* Action buttons */}
              {isActive && (
                <div style={{ display: "flex", gap: "8px" }}>
                  {nextStage && (
                    <button
                      onClick={() => advanceMutation.mutate(nextStage)}
                      disabled={advanceMutation.isPending}
                      style={{
                        padding: "10px 18px",
                        fontSize: "14px",
                        fontWeight: "600",
                        color: "white",
                        backgroundColor: "#6366f1",
                        border: "none",
                        borderRadius: "8px",
                        cursor: advanceMutation.isPending ? "not-allowed" : "pointer",
                        textTransform: "capitalize",
                      }}
                    >
                      Advance to {nextStage} →
                    </button>
                  )}
                  {application.pipeline_stage === "offer" && (
                    <button
                      onClick={() => hireMutation.mutate()}
                      disabled={hireMutation.isPending}
                      style={{
                        padding: "10px 18px",
                        fontSize: "14px",
                        fontWeight: "600",
                        color: "white",
                        backgroundColor: "#16a34a",
                        border: "none",
                        borderRadius: "8px",
                        cursor: "pointer",
                      }}
                    >
                      Mark as Hired ✓
                    </button>
                  )}
                  <button
                    onClick={() => setShowRejectModal(true)}
                    style={{
                      padding: "10px 18px",
                      fontSize: "14px",
                      fontWeight: "500",
                      color: "#dc2626",
                      backgroundColor: "#fee2e2",
                      border: "none",
                      borderRadius: "8px",
                      cursor: "pointer",
                    }}
                  >
                    Reject
                  </button>
                </div>
              )}

              {!isActive && (
                <span
                  style={{
                    fontSize: "14px",
                    fontWeight: "600",
                    color:
                      application.status === "hired" ? "#166534" : "#6b7280",
                    backgroundColor:
                      application.status === "hired" ? "#dcfce7" : "#f3f4f6",
                    padding: "6px 12px",
                    borderRadius: "6px",
                    textTransform: "capitalize",
                  }}
                >
                  {application.status}
                </span>
              )}
            </div>

            {/* Pipeline stages */}
            <div style={{ marginTop: "24px" }}>
              <div style={{ display: "flex", gap: "4px" }}>
                {stages.map((stage, idx) => {
                  const isCompleted = idx < currentIdx;
                  const isCurrent = idx === currentIdx;
                  return (
                    <div key={stage} style={{ flex: 1, textAlign: "center" }}>
                      <div
                        style={{
                          height: "4px",
                          borderRadius: "2px",
                          backgroundColor: isCompleted
                            ? "#6366f1"
                            : isCurrent
                            ? "#818cf8"
                            : "#e5e7eb",
                          marginBottom: "6px",
                        }}
                      />
                      <span
                        style={{
                          fontSize: "11px",
                          color: isCurrent ? "#4f46e5" : "#9ca3af",
                          fontWeight: isCurrent ? "600" : "400",
                          textTransform: "capitalize",
                        }}
                      >
                        {stage}
                      </span>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>

          {/* AI Scorecard */}
          {latest_score && (
            <div>
              <h2
                style={{
                  fontSize: "16px",
                  fontWeight: "600",
                  color: "#111827",
                  marginBottom: "12px",
                }}
              >
                AI Scorecard
              </h2>
              <ScoreCard score={latest_score} showRawBreakdown />
            </div>
          )}

          {!latest_score && (
            <div
              style={{
                backgroundColor: "#f8fafc",
                border: "1px dashed #cbd5e1",
                borderRadius: "12px",
                padding: "40px",
                textAlign: "center",
                color: "#94a3b8",
              }}
            >
              <div style={{ fontSize: "32px", marginBottom: "12px" }}>🤖</div>
              <p style={{ fontSize: "14px" }}>
                AI scorecard will appear here after a video interview session completes.
              </p>
            </div>
          )}

          {/* Interview history */}
          {interviews.length > 0 && (
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
                  marginBottom: "16px",
                }}
              >
                Interview History
              </h2>
              <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
                {interviews.map((interview) => (
                  <div
                    key={interview.id}
                    style={{
                      display: "flex",
                      justifyContent: "space-between",
                      alignItems: "center",
                      padding: "12px",
                      backgroundColor: "#f9fafb",
                      borderRadius: "8px",
                    }}
                  >
                    <div>
                      <div
                        style={{
                          fontSize: "14px",
                          fontWeight: "500",
                          color: "#111827",
                        }}
                      >
                        {interview.title}
                      </div>
                      <div style={{ fontSize: "12px", color: "#6b7280" }}>
                        {format(new Date(interview.scheduled_at), "MMM d, yyyy 'at' h:mm a")} ·{" "}
                        {interview.duration_minutes} min
                      </div>
                    </div>
                    <span
                      style={{
                        fontSize: "12px",
                        fontWeight: "500",
                        color:
                          interview.status === "completed"
                            ? "#166534"
                            : "#374151",
                        backgroundColor:
                          interview.status === "completed"
                            ? "#dcfce7"
                            : "#f3f4f6",
                        padding: "3px 8px",
                        borderRadius: "4px",
                        textTransform: "capitalize",
                      }}
                    >
                      {interview.status}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Sidebar */}
        <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
          <div
            style={{
              backgroundColor: "white",
              borderRadius: "12px",
              border: "1px solid #e5e7eb",
              padding: "20px",
            }}
          >
            <h3
              style={{
                fontSize: "14px",
                fontWeight: "600",
                color: "#374151",
                marginBottom: "16px",
              }}
            >
              Application Details
            </h3>
            <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
              <div>
                <div style={{ fontSize: "11px", fontWeight: "600", color: "#9ca3af", textTransform: "uppercase", letterSpacing: "0.05em", marginBottom: "4px" }}>
                  Applied
                </div>
                <div style={{ fontSize: "13px", color: "#374151" }}>
                  {format(new Date(application.applied_at), "MMM d, yyyy")}
                </div>
              </div>
              {candidate?.source && (
                <div>
                  <div style={{ fontSize: "11px", fontWeight: "600", color: "#9ca3af", textTransform: "uppercase", letterSpacing: "0.05em", marginBottom: "4px" }}>
                    Source
                  </div>
                  <div style={{ fontSize: "13px", color: "#374151", textTransform: "capitalize" }}>
                    {candidate.source.replace("_", " ")}
                  </div>
                </div>
              )}
              {application.composite_score !== null && (
                <div>
                  <div style={{ fontSize: "11px", fontWeight: "600", color: "#9ca3af", textTransform: "uppercase", letterSpacing: "0.05em", marginBottom: "4px" }}>
                    Composite Score
                  </div>
                  <div style={{ fontSize: "22px", fontWeight: "700", color: "#6366f1" }}>
                    {Number(application.composite_score).toFixed(1)}/10
                  </div>
                </div>
              )}
              {application.rank_within_job !== null && (
                <div>
                  <div style={{ fontSize: "11px", fontWeight: "600", color: "#9ca3af", textTransform: "uppercase", letterSpacing: "0.05em", marginBottom: "4px" }}>
                    Rank
                  </div>
                  <div style={{ fontSize: "13px", color: "#374151" }}>
                    #{application.rank_within_job} for this job
                  </div>
                </div>
              )}
            </div>
          </div>

          {candidate?.tags && candidate.tags.length > 0 && (
            <div
              style={{
                backgroundColor: "white",
                borderRadius: "12px",
                border: "1px solid #e5e7eb",
                padding: "20px",
              }}
            >
              <h3 style={{ fontSize: "14px", fontWeight: "600", color: "#374151", marginBottom: "12px" }}>
                Tags
              </h3>
              <div style={{ display: "flex", flexWrap: "wrap", gap: "6px" }}>
                {candidate.tags.map((tag) => (
                  <span
                    key={tag}
                    style={{
                      fontSize: "12px",
                      color: "#4f46e5",
                      backgroundColor: "#ede9fe",
                      padding: "3px 8px",
                      borderRadius: "4px",
                    }}
                  >
                    {tag}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Reject modal */}
      {showRejectModal && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            backgroundColor: "rgba(0,0,0,0.4)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 1000,
          }}
          onClick={(e) => {
            if (e.target === e.currentTarget) setShowRejectModal(false);
          }}
        >
          <div
            style={{
              backgroundColor: "white",
              borderRadius: "12px",
              padding: "28px",
              width: "440px",
              maxWidth: "90vw",
            }}
          >
            <h2 style={{ fontSize: "18px", fontWeight: "700", color: "#111827", marginBottom: "8px" }}>
              Reject Application
            </h2>
            <p style={{ fontSize: "14px", color: "#6b7280", marginBottom: "20px" }}>
              Select a reason for rejection. This will be logged in the audit trail.
            </p>
            <select
              value={rejectReason}
              onChange={(e) => setRejectReason(e.target.value)}
              style={{
                width: "100%",
                padding: "10px 12px",
                fontSize: "14px",
                border: "1px solid #d1d5db",
                borderRadius: "8px",
                marginBottom: "20px",
                outline: "none",
              }}
            >
              <option value="">Select a reason...</option>
              {REJECTION_REASONS.map((r) => (
                <option key={r.value} value={r.value}>
                  {r.label}
                </option>
              ))}
            </select>
            <div style={{ display: "flex", gap: "10px", justifyContent: "flex-end" }}>
              <button
                onClick={() => setShowRejectModal(false)}
                style={{
                  padding: "10px 18px",
                  fontSize: "14px",
                  color: "#374151",
                  backgroundColor: "#f9fafb",
                  border: "1px solid #e5e7eb",
                  borderRadius: "8px",
                  cursor: "pointer",
                }}
              >
                Cancel
              </button>
              <button
                onClick={() => rejectReason && rejectMutation.mutate(rejectReason)}
                disabled={!rejectReason || rejectMutation.isPending}
                style={{
                  padding: "10px 18px",
                  fontSize: "14px",
                  fontWeight: "600",
                  color: "white",
                  backgroundColor: "#dc2626",
                  border: "none",
                  borderRadius: "8px",
                  cursor: !rejectReason ? "not-allowed" : "pointer",
                  opacity: !rejectReason ? 0.6 : 1,
                }}
              >
                {rejectMutation.isPending ? "Rejecting…" : "Reject Application"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
