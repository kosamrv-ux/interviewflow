import { useCallback } from "react";
import { useNavigate } from "react-router-dom";
import { useAuthStore } from "./useAuthStore";
import { api } from "../api/client";

const ORG_STORAGE_KEY = "if_active_org_id";

/**
 * Hook for switching between organizations (for users who belong to multiple orgs,
 * e.g. consultants or internal admins).
 *
 * Bug fix (May 2026):
 * The org switcher was storing the selected org_id in React component state only.
 * On page refresh, the state was lost and the first org returned by the API was
 * selected, which was not necessarily the one the user had chosen.
 *
 * Fix: persist the selected org_id to localStorage under "if_active_org_id".
 * On app boot, read this value and use it as the initial org. Clear on logout.
 *
 * Edge cases handled:
 * - The stored org_id is no longer in the user's org list (removed from org):
 *   fall back to first available org and clear storage.
 * - The user has only one org: skip the switcher UI entirely.
 * - Storage is unavailable (private browsing in some browsers): fall back to
 *   in-memory state only, log a warning.
 */
export function useOrgSwitcher() {
  const { user, setActiveOrg } = useAuthStore();
  const navigate = useNavigate();

  const getStoredOrgId = useCallback((): string | null => {
    try {
      return localStorage.getItem(ORG_STORAGE_KEY);
    } catch {
      console.warn("[OrgSwitcher] localStorage unavailable, using in-memory only");
      return null;
    }
  }, []);

  const storeOrgId = useCallback((orgId: string) => {
    try {
      localStorage.setItem(ORG_STORAGE_KEY, orgId);
    } catch {
      // Silently ignore — falls back to in-memory state
    }
  }, []);

  const clearStoredOrgId = useCallback(() => {
    try {
      localStorage.removeItem(ORG_STORAGE_KEY);
    } catch {}
  }, []);

  const switchOrg = useCallback(
    async (orgId: string) => {
      try {
        const res = await api.post("/api/v1/auth/switch-org", { org_id: orgId });
        const { token, organization } = res.data;

        // Update the auth token and active org in the store
        setActiveOrg(organization, token);
        storeOrgId(orgId);

        // Navigate to dashboard of the new org
        navigate("/dashboard");
      } catch (err) {
        console.error("[OrgSwitcher] failed to switch org:", err);
        throw err;
      }
    },
    [setActiveOrg, storeOrgId, navigate]
  );

  const initOrgFromStorage = useCallback(
    (availableOrgs: Array<{ id: string; name: string; slug: string }>) => {
      if (!availableOrgs.length) return null;

      const storedId = getStoredOrgId();

      if (storedId) {
        const match = availableOrgs.find((o) => o.id === storedId);
        if (match) return match;

        // Stored org not found — user was removed; clear and fall back
        console.warn("[OrgSwitcher] stored org_id not in available orgs, clearing");
        clearStoredOrgId();
      }

      return availableOrgs[0];
    },
    [getStoredOrgId, clearStoredOrgId]
  );

  return {
    switchOrg,
    initOrgFromStorage,
    clearStoredOrgId,
  };
}
