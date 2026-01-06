import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from '../hooks/useAuthContext';

interface ProtectedRouteProps {
  /** Optional role(s) required to access this route */
  requiredRole?: string | string[];
}

/**
 * Wraps routes that require authentication (and optionally a specific role).
 * Unauthenticated users are redirected to /login with a `from` state so they
 * can be sent back after successful login. Users lacking the required role see
 * a 403 redirect instead.
 */
export function ProtectedRoute({ requiredRole }: ProtectedRouteProps) {
  const { isAuthenticated, isLoading, hasRole } = useAuth();
  const location = useLocation();

  if (isLoading) {
    return (
      <div className="flex h-screen items-center justify-center">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-indigo-600 border-t-transparent" />
      </div>
    );
  }

  if (!isAuthenticated) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  if (requiredRole && !hasRole(requiredRole)) {
    return <Navigate to="/403" replace />;
  }

  return <Outlet />;
}
