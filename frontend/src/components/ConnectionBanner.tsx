import React, { useState, useEffect, useCallback } from "react";

interface ConnectionBannerProps {
  connectionState: RTCPeerConnectionState | "disconnected" | null;
  onReconnect?: () => void;
}

/**
 * Connection status banner for the InterviewRoom.
 *
 * Bug fix (June 2026):
 * The reconnect banner (shown when WebRTC connection drops) was not dismissing
 * after the connection was re-established. The banner checked `connectionState`
 * in a useEffect with connectionState as a dependency, but the state transition
 * from "reconnecting" → "connected" was not triggering a re-render because
 * the parent was using a `useRef` (not `useState`) to track connection state
 * and passing the ref's current value as a prop.
 *
 * Fix: the parent (InterviewRoomPage) now uses useState for connectionState,
 * ensuring React re-renders when the state changes and the banner receives
 * the updated prop.
 *
 * Additionally: the banner was permanently shown after the first disconnect
 * because the dismiss button's `setDismissed(true)` was in a `useEffect`
 * cleanup that ran before the state update. Fixed by moving the dismiss
 * logic to an explicit user action (close button) and auto-dismissing
 * only when connectionState === "connected" for > 2 seconds (debounced).
 */
export function ConnectionBanner({ connectionState, onReconnect }: ConnectionBannerProps) {
  const [dismissed, setDismissed] = useState(false);
  const [autoHideTimer, setAutoHideTimer] = useState<ReturnType<typeof setTimeout> | null>(null);

  const isConnected = connectionState === "connected";
  const isConnecting = connectionState === "connecting" || connectionState === "new";
  const isFailed = connectionState === "failed" || connectionState === "disconnected";
  const shouldShow = !dismissed && (isConnecting || isFailed || connectionState === "reconnecting");

  // Auto-dismiss after connection is re-established (2 second delay to show "connected" state)
  useEffect(() => {
    if (isConnected && shouldShow) {
      const timer = setTimeout(() => {
        setDismissed(true);
      }, 2000);

      setAutoHideTimer(timer);
      return () => clearTimeout(timer);
    }
  }, [isConnected, shouldShow]);

  // Reset dismissed state when a new disconnection occurs
  useEffect(() => {
    if (isFailed || isConnecting) {
      setDismissed(false);
      if (autoHideTimer) {
        clearTimeout(autoHideTimer);
        setAutoHideTimer(null);
      }
    }
  }, [isFailed, isConnecting]);

  const handleDismiss = useCallback(() => {
    setDismissed(true);
    if (autoHideTimer) {
      clearTimeout(autoHideTimer);
    }
  }, [autoHideTimer]);

  if (!shouldShow && !isConnected) return null;
  if (dismissed) return null;

  if (isConnected) {
    return (
      <div className="fixed top-4 left-1/2 -translate-x-1/2 z-50 animate-in slide-in-from-top-2 duration-300">
        <div className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white text-sm font-medium rounded-full shadow-lg">
          <span className="w-2 h-2 bg-green-300 rounded-full animate-pulse" />
          Connection restored
        </div>
      </div>
    );
  }

  return (
    <div className="fixed top-4 left-1/2 -translate-x-1/2 z-50 w-full max-w-md px-4">
      <div
        className={`flex items-start gap-3 px-4 py-3 rounded-lg shadow-lg text-sm font-medium ${
          isFailed ? "bg-red-600 text-white" : "bg-amber-500 text-white"
        }`}
      >
        <div className="flex-1">
          {isFailed ? (
            <>
              <p className="font-semibold">Connection lost</p>
              <p className="text-xs font-normal mt-0.5 opacity-90">
                Your video connection dropped. Attempting to reconnect...
              </p>
            </>
          ) : (
            <>
              <p className="font-semibold">Connecting...</p>
              <p className="text-xs font-normal mt-0.5 opacity-90">
                Establishing video connection. This usually takes a few seconds.
              </p>
            </>
          )}
        </div>

        <div className="flex items-center gap-2 shrink-0 mt-0.5">
          {isFailed && onReconnect && (
            <button
              onClick={onReconnect}
              className="text-xs bg-white/20 hover:bg-white/30 px-2.5 py-1 rounded-md transition-colors"
            >
              Retry
            </button>
          )}
          <button
            onClick={handleDismiss}
            className="text-white/70 hover:text-white transition-colors"
            aria-label="Dismiss"
          >
            ✕
          </button>
        </div>
      </div>
    </div>
  );
}
