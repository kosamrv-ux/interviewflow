import { Outlet, NavLink, useNavigate } from "react-router-dom";
import { useAuthStore } from "@/hooks/useAuthStore";
import api from "@/api/client";

const NAV_ITEMS = [
  { to: "/dashboard", label: "Dashboard", icon: "⬜" },
  { to: "/jobs", label: "Jobs", icon: "💼" },
];

export default function AppLayout() {
  const user = useAuthStore((s) => s.user);
  const clearAuth = useAuthStore((s) => s.clearAuth);
  const navigate = useNavigate();

  const handleLogout = async () => {
    await api.logout();
    clearAuth();
    navigate("/login", { replace: true });
  };

  return (
    <div
      style={{
        display: "flex",
        minHeight: "100vh",
        backgroundColor: "#f9fafb",
      }}
    >
      {/* Sidebar */}
      <aside
        style={{
          width: "var(--sidebar-width)",
          backgroundColor: "#1e1b4b",
          color: "#c7d2fe",
          display: "flex",
          flexDirection: "column",
          padding: "0",
          flexShrink: 0,
        }}
      >
        {/* Logo */}
        <div
          style={{
            padding: "20px 24px",
            borderBottom: "1px solid rgba(255,255,255,0.1)",
            display: "flex",
            alignItems: "center",
            gap: "10px",
          }}
        >
          <span
            style={{
              fontSize: "20px",
              fontWeight: "700",
              color: "#818cf8",
              letterSpacing: "-0.5px",
            }}
          >
            InterviewFlow
          </span>
        </div>

        {/* Nav */}
        <nav style={{ padding: "16px 12px", flex: 1 }}>
          {NAV_ITEMS.map(({ to, label, icon }) => (
            <NavLink
              key={to}
              to={to}
              style={({ isActive }) => ({
                display: "flex",
                alignItems: "center",
                gap: "10px",
                padding: "10px 12px",
                borderRadius: "8px",
                color: isActive ? "#ffffff" : "#a5b4fc",
                backgroundColor: isActive
                  ? "rgba(99,102,241,0.3)"
                  : "transparent",
                textDecoration: "none",
                fontSize: "14px",
                fontWeight: isActive ? "600" : "400",
                marginBottom: "4px",
                transition: "background-color 150ms",
              })}
            >
              <span style={{ fontSize: "16px" }}>{icon}</span>
              {label}
            </NavLink>
          ))}
        </nav>

        {/* User footer */}
        <div
          style={{
            padding: "16px 24px",
            borderTop: "1px solid rgba(255,255,255,0.1)",
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: "10px",
              marginBottom: "12px",
            }}
          >
            <div
              style={{
                width: "32px",
                height: "32px",
                borderRadius: "50%",
                backgroundColor: "#6366f1",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                fontSize: "12px",
                fontWeight: "600",
                color: "white",
              }}
            >
              {user?.full_name.charAt(0).toUpperCase() ?? "?"}
            </div>
            <div>
              <div
                style={{ fontSize: "13px", fontWeight: "500", color: "#e0e7ff" }}
              >
                {user?.full_name}
              </div>
              <div style={{ fontSize: "11px", color: "#818cf8" }}>
                {user?.role}
              </div>
            </div>
          </div>
          <button
            onClick={handleLogout}
            style={{
              width: "100%",
              padding: "8px",
              fontSize: "13px",
              color: "#a5b4fc",
              background: "none",
              border: "1px solid rgba(165,180,252,0.2)",
              borderRadius: "6px",
              cursor: "pointer",
            }}
          >
            Sign out
          </button>
        </div>
      </aside>

      {/* Main content */}
      <main style={{ flex: 1, overflow: "auto" }}>
        <Outlet />
      </main>
    </div>
  );
}
