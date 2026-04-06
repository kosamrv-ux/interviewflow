import { useState, type FormEvent } from "react";
import { useNavigate, Link } from "react-router-dom";
import { useAuthStore } from "@/hooks/useAuthStore";
import { useRateLimit } from "@/hooks/useRateLimit";
import api from "@/api/client";
import type { ApiError } from "@/api/client";
import LoadingSpinner from "@/components/LoadingSpinner";

interface FormState {
  email: string;
  password: string;
}

interface FieldErrors {
  email?: string;
  password?: string;
  general?: string;
}

export default function LoginPage() {
  const navigate = useNavigate();
  const setUser  = useAuthStore((s) => s.setUser);
  const { isLimited, countdown, recordLimit } = useRateLimit();

  const [form, setForm] = useState<FormState>({ email: "", password: "" });
  const [errors, setErrors] = useState<FieldErrors>({});
  const [isLoading, setIsLoading] = useState(false);

  const validateForm = (): boolean => {
    const newErrors: FieldErrors = {};

    if (!form.email.trim()) {
      newErrors.email = "Email is required";
    } else if (!/^[^\s]+@[^\s]+$/.test(form.email)) {
      newErrors.email = "Enter a valid email address";
    }

    if (!form.password) {
      newErrors.password = "Password is required";
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (isLimited) return;
    if (!validateForm()) return;

    setIsLoading(true);
    setErrors({});

    try {
      const data = await api.login(form.email, form.password);
      setUser(data.user);
      navigate("/dashboard", { replace: true });
    } catch (err: unknown) {
      const apiErr = err as { status?: number; errors?: ApiError[]; retry_after?: number };
      const firstError = apiErr.errors?.[0];

      if (apiErr.status === 429) {
        recordLimit(apiErr.retry_after ?? 60);
        setErrors({ general: `Too many login attempts. Please wait ${apiErr.retry_after ?? 60} seconds.` });
      } else if (firstError?.code === "account_locked") {
        setErrors({ general: "Account locked after too many failed attempts. Try again in 15 minutes." });
      } else if (firstError?.code === "unauthorized") {
        setErrors({ general: "Invalid email or password" });
      } else {
        setErrors({
          general: firstError?.message ?? "Something went wrong. Please try again.",
        });
      }
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div
      style={{
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: "#f0f9ff",
        padding: "24px",
      }}
    >
      <div
        style={{
          width: "100%",
          maxWidth: "420px",
        }}
      >
        {/* Logo / Brand */}
        <div style={{ textAlign: "center", marginBottom: "40px" }}>
          <div
            style={{
              display: "inline-flex",
              alignItems: "center",
              justifyContent: "center",
              width: "56px",
              height: "56px",
              backgroundColor: "#6366f1",
              borderRadius: "14px",
              marginBottom: "16px",
            }}
          >
            <span style={{ fontSize: "28px" }}>🎙</span>
          </div>
          <h1
            style={{
              fontSize: "28px",
              fontWeight: "700",
              color: "#111827",
              margin: "0 0 6px",
            }}
          >
            InterviewFlow
          </h1>
          <p style={{ fontSize: "14px", color: "#6b7280", margin: 0 }}>
            Sign in to your recruiter dashboard
          </p>
        </div>

        {/* Card */}
        <div
          style={{
            backgroundColor: "white",
            borderRadius: "12px",
            padding: "32px",
            boxShadow: "0 1px 3px rgba(0,0,0,0.1), 0 1px 2px rgba(0,0,0,0.06)",
          }}
        >
          {errors.general && (
            <div
              role="alert"
              style={{
                backgroundColor: "#fee2e2",
                color: "#991b1b",
                padding: "12px 16px",
                borderRadius: "8px",
                fontSize: "14px",
                marginBottom: "20px",
              }}
            >
              {errors.general}
            </div>
          )}

          <form onSubmit={handleSubmit} noValidate>
            {/* Email */}
            <div style={{ marginBottom: "20px" }}>
              <label
                htmlFor="email"
                style={{
                  display: "block",
                  fontSize: "14px",
                  fontWeight: "500",
                  color: "#374151",
                  marginBottom: "6px",
                }}
              >
                Work email
              </label>
              <input
                id="email"
                type="email"
                autoComplete="email"
                value={form.email}
                onChange={(e) =>
                  setForm((prev) => ({ ...prev, email: e.target.value }))
                }
                style={{
                  width: "100%",
                  padding: "10px 12px",
                  fontSize: "14px",
                  border: `1px solid ${errors.email ? "#ef4444" : "#d1d5db"}`,
                  borderRadius: "8px",
                  outline: "none",
                  boxSizing: "border-box",
                  backgroundColor: "white",
                }}
                placeholder="you@company.com"
                aria-describedby={errors.email ? "email-error" : undefined}
                aria-invalid={!!errors.email}
              />
              {errors.email && (
                <p
                  id="email-error"
                  style={{ fontSize: "12px", color: "#ef4444", marginTop: "4px" }}
                >
                  {errors.email}
                </p>
              )}
            </div>

            {/* Password */}
            <div style={{ marginBottom: "28px" }}>
              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  marginBottom: "6px",
                }}
              >
                <label
                  htmlFor="password"
                  style={{ fontSize: "14px", fontWeight: "500", color: "#374151" }}
                >
                  Password
                </label>
                <Link
                  to="/forgot-password"
                  style={{ fontSize: "13px", color: "#6366f1" }}
                >
                  Forgot password?
                </Link>
              </div>
              <input
                id="password"
                type="password"
                autoComplete="current-password"
                value={form.password}
                onChange={(e) =>
                  setForm((prev) => ({ ...prev, password: e.target.value }))
                }
                style={{
                  width: "100%",
                  padding: "10px 12px",
                  fontSize: "14px",
                  border: `1px solid ${errors.password ? "#ef4444" : "#d1d5db"}`,
                  borderRadius: "8px",
                  outline: "none",
                  boxSizing: "border-box",
                  backgroundColor: "white",
                }}
                aria-invalid={!!errors.password}
              />
              {errors.password && (
                <p style={{ fontSize: "12px", color: "#ef4444", marginTop: "4px" }}>
                  {errors.password}
                </p>
              )}
            </div>

            <button
              type="submit"
              disabled={isLoading}
              style={{
                width: "100%",
                padding: "12px",
                fontSize: "15px",
                fontWeight: "600",
                color: "white",
                backgroundColor: isLoading ? "#818cf8" : "#6366f1",
                border: "none",
                borderRadius: "8px",
                cursor: isLoading ? "not-allowed" : "pointer",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                gap: "8px",
              }}
            >
              {isLoading && <LoadingSpinner size="sm" />}
              {isLoading ? "Signing in..." : "Sign in"}
            </button>
          </form>
        </div>

        <p
          style={{
            textAlign: "center",
            fontSize: "13px",
            color: "#6b7280",
            marginTop: "20px",
          }}
        >
          Don&apos;t have an account?{" "}
          <Link to="/register" style={{ color: "#6366f1", fontWeight: "500" }}>
            Request access
          </Link>
        </p>
      </div>
    </div>
  );
}
