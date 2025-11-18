import { Suspense, lazy } from "react";
import {
  BrowserRouter,
  Routes,
  Route,
  Navigate,
  Outlet,
} from "react-router-dom";
import { useAuthStore } from "@/hooks/useAuthStore";
import LoadingSpinner from "@/components/LoadingSpinner";
import AppLayout from "@/components/AppLayout";

// Route-level code splitting — each page is a separate chunk
const LoginPage = lazy(() => import("@/pages/LoginPage"));
const DashboardPage = lazy(() => import("@/pages/DashboardPage"));
const JobsPage = lazy(() => import("@/pages/JobsPage"));
const JobDetailPage = lazy(() => import("@/pages/JobDetailPage"));
const ApplicationDetailPage = lazy(() => import("@/pages/ApplicationDetailPage"));
const InterviewRoomPage = lazy(() => import("@/pages/InterviewRoomPage"));
const NotFoundPage = lazy(() => import("@/pages/NotFoundPage"));

/** Guards any child routes behind authentication. */
function ProtectedRoute() {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  return <Outlet />;
}

/** Full-page spinner shown while lazy chunks are loading. */
function PageSuspense({ children }: { children: React.ReactNode }) {
  return (
    <Suspense
      fallback={
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
      }
    >
      {children}
    </Suspense>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <PageSuspense>
        <Routes>
          {/* Public routes */}
          <Route path="/login" element={<LoginPage />} />

          {/* Interview room is semi-public — needs a session token but not a full JWT */}
          <Route path="/room/:sessionId" element={<InterviewRoomPage />} />

          {/* Protected application routes */}
          <Route element={<ProtectedRoute />}>
            <Route element={<AppLayout />}>
              <Route index element={<Navigate to="/dashboard" replace />} />
              <Route path="/dashboard" element={<DashboardPage />} />
              <Route path="/jobs" element={<JobsPage />} />
              <Route path="/jobs/:jobId" element={<JobDetailPage />} />
              <Route
                path="/applications/:applicationId"
                element={<ApplicationDetailPage />}
              />
            </Route>
          </Route>

          <Route path="*" element={<NotFoundPage />} />
        </Routes>
      </PageSuspense>
    </BrowserRouter>
  );
}
