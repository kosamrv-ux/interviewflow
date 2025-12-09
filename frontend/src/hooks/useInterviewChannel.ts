/**
 * useInterviewChannel — Manages the Phoenix Channel connection for a live
 * interview session.
 *
 * Handles:
 * - Socket connection with JWT auth
 * - Channel join with session_token
 * - Incoming WebRTC signaling message dispatch (offer/answer/ice_candidate)
 * - Chat message list
 * - Participant media state tracking (muted/video off)
 * - Graceful leave on unmount
 */

import { useEffect, useRef, useState, useCallback } from "react";
import { Socket, Channel } from "phoenix";
import type { RTCSessionDescriptionInit } from "dom";

export interface ChatMessage {
  user_id: string;
  full_name: string;
  body: string;
  sent_at: string;
}

export interface ParticipantState {
  user_id: string;
  audio_enabled: boolean;
  video_enabled: boolean;
  hand_raised: boolean;
}

interface UseInterviewChannelOptions {
  sessionToken: string;
  jwtToken: string;
  socketUrl: string;
  onOffer: (sdp: RTCSessionDescriptionInit, from: string) => void;
  onAnswer: (sdp: RTCSessionDescriptionInit, from: string) => void;
  onIceCandidate: (candidate: RTCIceCandidateInit, from: string) => void;
  onSessionEnded?: () => void;
}

interface UseInterviewChannelReturn {
  channel: Channel | null;
  connected: boolean;
  error: string | null;
  messages: ChatMessage[];
  participants: ParticipantState[];
  sendChat: (body: string) => void;
  sendMediaState: (audio: boolean, video: boolean) => void;
  raiseHand: () => void;
  leaveChannel: () => void;
}

export function useInterviewChannel({
  sessionToken,
  jwtToken,
  socketUrl,
  onOffer,
  onAnswer,
  onIceCandidate,
  onSessionEnded,
}: UseInterviewChannelOptions): UseInterviewChannelReturn {
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [participants, setParticipants] = useState<ParticipantState[]>([]);

  const socketRef = useRef<Socket | null>(null);
  const channelRef = useRef<Channel | null>(null);

  useEffect(() => {
    const socket = new Socket(socketUrl, {
      params: { token: jwtToken },
      logger: (kind, msg, data) => {
        if (import.meta.env.DEV) console.debug(`[Socket] ${kind} ${msg}`, data);
      },
    });

    socket.connect();
    socketRef.current = socket;

    const channel = socket.channel(`interview:${sessionToken}`, {
      session_token: sessionToken,
    });

    // ---------- WebRTC signaling ----------
    channel.on("webrtc:offer", ({ sdp, from }: { sdp: RTCSessionDescriptionInit; from: string }) => {
      onOffer(sdp, from);
    });

    channel.on("webrtc:answer", ({ sdp, from }: { sdp: RTCSessionDescriptionInit; from: string }) => {
      onAnswer(sdp, from);
    });

    channel.on("webrtc:ice_candidate", ({ candidate, from }: { candidate: RTCIceCandidateInit; from: string }) => {
      onIceCandidate(candidate, from);
    });

    // ---------- Chat ----------
    channel.on("chat:message", (msg: ChatMessage) => {
      setMessages((prev) => [...prev, msg]);
    });

    // ---------- Media state ----------
    channel.on("media:state_changed", (state: ParticipantState) => {
      setParticipants((prev) => {
        const idx = prev.findIndex((p) => p.user_id === state.user_id);
        if (idx === -1) return [...prev, state];
        const updated = [...prev];
        updated[idx] = state;
        return updated;
      });
    });

    // ---------- Session lifecycle ----------
    channel.on("session:ended", () => {
      onSessionEnded?.();
    });

    channel.on("participant:raised_hand", (data: { user_id: string }) => {
      setParticipants((prev) =>
        prev.map((p) => (p.user_id === data.user_id ? { ...p, hand_raised: true } : p)),
      );
    });

    channel
      .join()
      .receive("ok", (_response) => {
        setConnected(true);
        setError(null);
      })
      .receive("error", (reason) => {
        setError(`Failed to join session: ${reason?.reason ?? "unknown error"}`);
        setConnected(false);
      })
      .receive("timeout", () => {
        setError("Connection timed out. Please refresh and try again.");
      });

    channelRef.current = channel;

    return () => {
      channel.leave();
      socket.disconnect();
      channelRef.current = null;
      socketRef.current = null;
      setConnected(false);
    };
    // onOffer/onAnswer/onIceCandidate are callbacks — caller must memoize them.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sessionToken, jwtToken, socketUrl]);

  const sendChat = useCallback((body: string) => {
    channelRef.current?.push("chat:message", { body });
  }, []);

  const sendMediaState = useCallback((audio: boolean, video: boolean) => {
    channelRef.current?.push("media:state_changed", {
      audio_enabled: audio,
      video_enabled: video,
    });
  }, []);

  const raiseHand = useCallback(() => {
    channelRef.current?.push("participant:raised_hand", {});
  }, []);

  const leaveChannel = useCallback(() => {
    channelRef.current?.push("session:end", {});
    channelRef.current?.leave();
  }, []);

  return {
    channel: channelRef.current,
    connected,
    error,
    messages,
    participants,
    sendChat,
    sendMediaState,
    raiseHand,
    leaveChannel,
  };
}
