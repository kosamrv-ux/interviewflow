/**
 * useRateLimit — React hook for displaying rate-limit countdown to users.
 *
 * Usage:
 *   const { isLimited, countdown, recordLimit } = useRateLimit();
 *
 *   // In login handler when API returns 429:
 *   catch (err) {
 *     if (err.status === 429) {
 *       recordLimit(err.retry_after);
 *     }
 *   }
 *
 *   // In render:
 *   {isLimited && <p>Too many attempts. Try again in {countdown}s</p>}
 */

import { useState, useEffect, useCallback } from "react";

interface RateLimitState {
  isLimited:   boolean;
  countdown:   number;      // seconds remaining
  retryAfter:  number | null;  // epoch ms
}

export function useRateLimit() {
  const [state, setState] = useState<RateLimitState>({
    isLimited:  false,
    countdown:  0,
    retryAfter: null,
  });

  // Decrement countdown every second while limited
  useEffect(() => {
    if (!state.isLimited) return;

    const timer = setInterval(() => {
      const remaining = Math.max(
        0,
        Math.ceil(((state.retryAfter ?? Date.now()) - Date.now()) / 1000),
      );

      if (remaining === 0) {
        setState({ isLimited: false, countdown: 0, retryAfter: null });
        clearInterval(timer);
      } else {
        setState((prev) => ({ ...prev, countdown: remaining }));
      }
    }, 1000);

    return () => clearInterval(timer);
  }, [state.isLimited, state.retryAfter]);

  /**
   * Records a rate-limit response.
   * @param retryAfterSeconds - value from Retry-After header or API error body
   */
  const recordLimit = useCallback((retryAfterSeconds: number) => {
    const retryAfterMs = Date.now() + retryAfterSeconds * 1000;
    setState({
      isLimited:  true,
      countdown:  retryAfterSeconds,
      retryAfter: retryAfterMs,
    });
  }, []);

  const clearLimit = useCallback(() => {
    setState({ isLimited: false, countdown: 0, retryAfter: null });
  }, []);

  return {
    isLimited:  state.isLimited,
    countdown:  state.countdown,
    recordLimit,
    clearLimit,
  };
}
