/**
 * useWebRTC — Custom hook encapsulating WebRTC peer connection lifecycle.
 *
 * Separates signaling logic from the InterviewRoomPage component,
 * making it testable and reusable.
 */

import { useRef, useState, useCallback, useEffect } from "react";
import type { Channel } from "phoenix";
import type { IceServer } from "@/api/client";

export type WebRTCState = "idle" | "connecting" | "connected" | "disconnected" | "failed";

interface UseWebRTCOptions {
  iceServers: IceServer[];
  channel: Channel | null;
  userId: string;
  onRemoteStream?: (stream: MediaStream) => void;
  onConnectionStateChange?: (state: WebRTCState) => void;
}

interface UseWebRTCReturn {
  state: WebRTCState;
  localStream: MediaStream | null;
  startLocalMedia: () => Promise<MediaStream>;
  createOffer: () => Promise<void>;
  setRemoteDescription: (sdp: RTCSessionDescriptionInit) => Promise<void>;
  addIceCandidate: (candidate: RTCIceCandidateInit) => Promise<void>;
  toggleAudio: () => boolean;
  toggleVideo: () => boolean;
  close: () => void;
}

export function useWebRTC({
  iceServers,
  channel,
  userId,
  onRemoteStream,
  onConnectionStateChange,
}: UseWebRTCOptions): UseWebRTCReturn {
  const [state, setState] = useState<WebRTCState>("idle");
  const [localStream, setLocalStream] = useState<MediaStream | null>(null);

  const pcRef = useRef<RTCPeerConnection | null>(null);
  const localStreamRef = useRef<MediaStream | null>(null);

  const updateState = useCallback(
    (newState: WebRTCState) => {
      setState(newState);
      onConnectionStateChange?.(newState);
    },
    [onConnectionStateChange],
  );

  const getOrCreatePeerConnection = useCallback((): RTCPeerConnection => {
    if (pcRef.current) return pcRef.current;

    const pc = new RTCPeerConnection({
      iceServers: iceServers as RTCIceServer[],
      iceCandidatePoolSize: 10,
    });

    pc.onicecandidate = (event) => {
      if (event.candidate && channel) {
        channel.push("webrtc:ice_candidate", {
          candidate: event.candidate.toJSON(),
        });
      }
    };

    pc.ontrack = (event) => {
      onRemoteStream?.(event.streams[0]);
      updateState("connected");
    };

    pc.onconnectionstatechange = () => {
      switch (pc.connectionState) {
        case "connecting":
          updateState("connecting");
          break;
        case "connected":
          updateState("connected");
          break;
        case "disconnected":
          updateState("disconnected");
          break;
        case "failed":
          updateState("failed");
          break;
        default:
          break;
      }
    };

    pcRef.current = pc;
    return pc;
  }, [iceServers, channel, onRemoteStream, updateState]);

  const startLocalMedia = useCallback(async (): Promise<MediaStream> => {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { width: { ideal: 1280 }, height: { ideal: 720 }, facingMode: "user" },
      audio: { echoCancellation: true, noiseSuppression: true },
    });

    localStreamRef.current = stream;
    setLocalStream(stream);
    return stream;
  }, []);

  const createOffer = useCallback(async (): Promise<void> => {
    const stream = localStreamRef.current;
    if (!stream) throw new Error("Local media not started");

    const pc = getOrCreatePeerConnection();
    stream.getTracks().forEach((track) => pc.addTrack(track, stream));

    const offer = await pc.createOffer({
      offerToReceiveAudio: true,
      offerToReceiveVideo: true,
    });
    await pc.setLocalDescription(offer);

    channel?.push("webrtc:offer", { sdp: offer, to: "all" });
    updateState("connecting");
  }, [getOrCreatePeerConnection, channel, updateState]);

  const setRemoteDescription = useCallback(
    async (sdp: RTCSessionDescriptionInit): Promise<void> => {
      const stream = localStreamRef.current;
      if (!stream) return;

      const pc = getOrCreatePeerConnection();
      stream.getTracks().forEach((track) => pc.addTrack(track, stream));

      await pc.setRemoteDescription(new RTCSessionDescription(sdp));

      if (sdp.type === "offer") {
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        channel?.push("webrtc:answer", { sdp: answer, to: "all" });
      }
    },
    [getOrCreatePeerConnection, channel],
  );

  const addIceCandidate = useCallback(
    async (candidate: RTCIceCandidateInit): Promise<void> => {
      const pc = pcRef.current;
      if (pc?.remoteDescription) {
        await pc.addIceCandidate(new RTCIceCandidate(candidate));
      }
    },
    [],
  );

  const toggleAudio = useCallback((): boolean => {
    const stream = localStreamRef.current;
    if (!stream) return false;
    const track = stream.getAudioTracks()[0];
    if (!track) return false;
    track.enabled = !track.enabled;
    return track.enabled;
  }, []);

  const toggleVideo = useCallback((): boolean => {
    const stream = localStreamRef.current;
    if (!stream) return false;
    const track = stream.getVideoTracks()[0];
    if (!track) return false;
    track.enabled = !track.enabled;
    return track.enabled;
  }, []);

  const close = useCallback((): void => {
    localStreamRef.current?.getTracks().forEach((t) => t.stop());
    pcRef.current?.close();
    localStreamRef.current = null;
    pcRef.current = null;
    setLocalStream(null);
    updateState("disconnected");
  }, [updateState]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      localStreamRef.current?.getTracks().forEach((t) => t.stop());
      pcRef.current?.close();
    };
  }, []);

  return {
    state,
    localStream,
    startLocalMedia,
    createOffer,
    setRemoteDescription,
    addIceCandidate,
    toggleAudio,
    toggleVideo,
    close,
  };
}
