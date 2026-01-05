import React, { createContext, useContext, useEffect, useCallback, useState, useRef } from 'react';
import {
  login as apiLogin,
  register as apiRegister,
  logout as apiLogout,
  refreshTokens,
  storeTokens,
  clearTokens,
  getStoredAccessToken,
  getStoredRefreshToken,
  type LoginRequest,
  type RegisterRequest,
  type TokenResponse,
} from '../api/auth';

interface AuthUser {
  id: string;
  email: string;
  full_name: string;
  role: string;
  company_id: string;
  avatar_url: string | null;
}

interface AuthContextValue {
  user: AuthUser | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  login: (data: LoginRequest) => Promise<void>;
  register: (data: RegisterRequest) => Promise<void>;
  logout: () => Promise<void>;
  hasRole: (role: string | string[]) => boolean;
}

const AuthContext = createContext<AuthContextValue | null>(null);

const REFRESH_MARGIN_MS = 60_000; // refresh 1 min before expiry

function decodeJwtPayload(token: string): Record<string, unknown> | null {
  try {
    const payload = token.split('.')[1];
    return JSON.parse(atob(payload.replace(/-/g, '+').replace(/_/g, '/')));
  } catch {
    return null;
  }
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const refreshTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const scheduleRefresh = useCallback((accessToken: string) => {
    const payload = decodeJwtPayload(accessToken);
    if (!payload || typeof payload.exp !== 'number') return;

    const expiresAt = payload.exp * 1000;
    const now = Date.now();
    const delay = expiresAt - now - REFRESH_MARGIN_MS;

    if (refreshTimerRef.current) clearTimeout(refreshTimerRef.current);

    if (delay > 0) {
      refreshTimerRef.current = setTimeout(async () => {
        const refreshToken = getStoredRefreshToken();
        if (!refreshToken) return;
        try {
          const resp = await refreshTokens(refreshToken);
          storeTokens(resp.access_token, resp.refresh_token);
          setUser(resp.user);
          scheduleRefresh(resp.access_token);
        } catch {
          clearTokens();
          setUser(null);
        }
      }, delay);
    }
  }, []);

  // Restore session from localStorage on mount
  useEffect(() => {
    const accessToken = getStoredAccessToken();
    if (accessToken) {
      const payload = decodeJwtPayload(accessToken);
      if (payload && typeof payload.exp === 'number' && payload.exp * 1000 > Date.now()) {
        setUser(payload as unknown as AuthUser);
        scheduleRefresh(accessToken);
      } else {
        clearTokens();
      }
    }
    setIsLoading(false);

    return () => {
      if (refreshTimerRef.current) clearTimeout(refreshTimerRef.current);
    };
  }, [scheduleRefresh]);

  const handleAuthResponse = useCallback(
    (resp: TokenResponse) => {
      storeTokens(resp.access_token, resp.refresh_token);
      setUser(resp.user);
      scheduleRefresh(resp.access_token);
    },
    [scheduleRefresh],
  );

  const login = useCallback(
    async (data: LoginRequest) => {
      const resp = await apiLogin(data);
      handleAuthResponse(resp);
    },
    [handleAuthResponse],
  );

  const register = useCallback(
    async (data: RegisterRequest) => {
      const resp = await apiRegister(data);
      handleAuthResponse(resp);
    },
    [handleAuthResponse],
  );

  const logout = useCallback(async () => {
    try {
      await apiLogout();
    } finally {
      clearTokens();
      setUser(null);
      if (refreshTimerRef.current) clearTimeout(refreshTimerRef.current);
    }
  }, []);

  const hasRole = useCallback(
    (role: string | string[]) => {
      if (!user) return false;
      const roles = Array.isArray(role) ? role : [role];
      return roles.includes(user.role);
    },
    [user],
  );

  return (
    <AuthContext.Provider
      value={{ user, isAuthenticated: !!user, isLoading, login, register, logout, hasRole }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within an AuthProvider');
  return ctx;
}
