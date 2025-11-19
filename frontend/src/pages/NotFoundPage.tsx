import { Link } from "react-router-dom";

export default function NotFoundPage() {
  return (
    <div
      style={{
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        flexDirection: "column",
        gap: "16px",
        backgroundColor: "#f9fafb",
        color: "#374151",
        textAlign: "center",
        padding: "24px",
      }}
    >
      <div style={{ fontSize: "72px" }}>404</div>
      <h1 style={{ fontSize: "24px", fontWeight: "700", color: "#111827" }}>
        Page not found
      </h1>
      <p style={{ color: "#6b7280", fontSize: "15px" }}>
        The page you&apos;re looking for doesn&apos;t exist.
      </p>
      <Link
        to="/dashboard"
        style={{
          marginTop: "8px",
          padding: "10px 24px",
          fontSize: "14px",
          fontWeight: "600",
          color: "white",
          backgroundColor: "#6366f1",
          borderRadius: "8px",
          textDecoration: "none",
        }}
      >
        Go to Dashboard
      </Link>
    </div>
  );
}
