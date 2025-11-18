/**
 * Global auth state managed by Zustand.
 * Intentionally kept minimal — only stores the current user and auth status.
 * All server state (jobs, applications) lives in TanStack Query.
 */

import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { User } from "@/api/client";
import { TOKEN_STORAGE_KEY } from "@/api/client";

interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
  setUser: (user: User) => void;
  clearAuth: () => void;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      user: null,
      isAuthenticated: !!localStorage.getItem(TOKEN_STORAGE_KEY),

      setUser: (user: User) =>
        set({
          user,
          isAuthenticated: true,
        }),

      clearAuth: () => {
        localStorage.removeItem(TOKEN_STORAGE_KEY);
        localStorage.removeItem("if_refresh_token");
        set({ user: null, isAuthenticated: false });
      },
    }),
    {
      name: "interviewflow-auth",
      partialize: (state) => ({
        user: state.user,
        isAuthenticated: state.isAuthenticated,
      }),
    },
  ),
);
