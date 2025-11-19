/**
 * InterviewRoomPage — Live video interview room.
 *
 * Manages:
 * - WebRTC PeerConnection lifecycle
 * - Phoenix Channel signaling (offer/answer/ICE)
 * - Local/remote media stream display
 * - Monaco Editor for coding assessments
 * - Chat panel
 */

import { useEffect, useRef, useState, useCallback } from "react";
import { useParams, useSearchParams } from "react-router-dom";
import { Editor } from "@monaco-editor/react";
import { Socket, Channel } from "phoenix";
import api from "@/api/client";
import type { IceServer } from "@/api/client";
import LoadingSpinner from "@/components/LoadingSpinner";

type ConnectionState = "connecting" | "waiting" | "active" | "ended" | "error";

interface ChatMessage {
  id: string;
  text: string;
  from: string;
  timestamp: number;
  isSelf: boolean;
}

const WS_URL =
  (import.meta.env.VITE_WS_URL as string | undefined) || "ws://localhost:4000";

export default function InterviewRoomPage() {
  const { sessionId } = useParams<{ sessionId: string }>();
  const [searchParams] = useSearchParams();
  const sessionToken = searchParams.get("token") ?? "";

  const [connectionState, setConnectionState] =
    useState<ConnectionState>("connecting");
  const [isMuted, setIsMuted] = useState(false);
  const [isVideoOff, setIsVideoOff] = useState(false);
  const [activeTab, setActiveTab] = useState<"chat" | "code">("chat");
  const [chatMessages, setChatMessages] = useState<ChatMessage[]>([]);
  const [chatInput, setChatInput] = useState("");
  const [code, setCode] = useState("// Write your solution here\n");
  const [codeLanguage, setCodeLanguage] = useState("javascript");
  const [participants, setParticipants] = useState<Record<string, unknown>>({});

  const localVideoRef = useRef<HTMLVideoElement>(null);
  const remoteVideoRef = useRef<HTMLVideoElement>(null);
  const peerConnectionRef = useRef<RTCPeerConnection | null>(null);
  const localStreamRef = useRef<MediaStream | null>(null);
  const channelRef = useRef<Channel | null>(null);
  const socketRef = useRef<Socket | null>(null);
  const chatEndRef = useRef<HTMLDivElement>(null);

  const userId = `user-${Math.random().toString(36).slice(2, 9)}`;

  // ─── ICE server config ──────────────────────────────────────────────────
  const getIceServers = useCallback(async (): Promise<RTCIceServer[]> => {
    if (!sessionId) return [{ urls: "stun:stun.l.google.com:19302" }];
    try {
      const { ice_servers } = await api.getIceServers(sessionId);
      return ice_servers as RTCIceServer[];
    } catch {
      return [{ urls: "stun:stun.l.google.com:19302" }];
    }
  }, [sessionId]);

  // ─── WebRTC setup ─────────────────────────────────────────────────────
  const createPeerConnection = useCallback(
    (iceServers: IceServer[]) => {
      const pc = new RTCPeerConnection({ iceServers: iceServers as RTCIceServer[] });

      pc.onicecandidate = (event) => {
        if (event.candidate && channelRef.current) {
          channelRef.current.push("webrtc:ice_candidate", {
            candidate: event.candidate.toJSON(),
          });
        }
      };

      pc.ontrack = (event) => {
        if (remoteVideoRef.current) {
          remoteVideoRef.current.srcObject = event.streams[0];
        }
        setConnectionState("active");
      };

      pc.onconnectionstatechange = () => {
        if (pc.connectionState === "disconnected" || pc.connectionState === "failed") {
          setConnectionState("error");
        }
      };

      return pc;
    },
    [],
  );

  // ─── Channel setup ─────────────────────────────────────────────────────
  useEffect(() => {
    if (!sessionId || !sessionToken) return;

    let cancelled = false;

    const init = async () => {
      // 1. Get local media
      let stream: MediaStream;
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: { width: 1280, height: 720 },
          audio: true,
        });
        localStreamRef.current = stream;
        if (localVideoRef.current) {
          localVideoRef.current.srcObject = stream;
        }
      } catch {
        setConnectionState("error");
        return;
      }

      if (cancelled) return;

      // 2. Set up WebSocket and join channel
      const socket = new Socket(`${WS_URL}/socket`, {
        params: { token: sessionToken },
      });
      socket.connect();
      socketRef.current = socket;

      const channel = socket.channel(`interview:${sessionId}`, {
        token: sessionToken,
      });
      channelRef.current = channel;

      // 3. Get ICE servers and create peer connection
      const iceServers = await getIceServers();
      const pc = createPeerConnection(iceServers);
      peerConnectionRef.current = pc;

      // Add local tracks to peer connection
      stream.getTracks().forEach((track) => pc.addTrack(track, stream));

      // 4. Channel event handlers
      channel.on("presence_state", (state: Record<string, unknown>) => {
        setParticipants(state);
        setConnectionState("waiting");
      });

      channel.on("session:started", () => {
        setConnectionState("active");
      });

      channel.on("webrtc:offer", async ({ sdp, from }: { sdp: RTCSessionDescriptionInit; from: string }) => {
        if (from === userId) return;
        await pc.setRemoteDescription(new RTCSessionDescription(sdp));
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        channel.push("webrtc:answer", { sdp: answer, to: from });
      });

      channel.on("webrtc:answer", async ({ sdp }: { sdp: RTCSessionDescriptionInit }) => {
        await pc.setRemoteDescription(new RTCSessionDescription(sdp));
      });

      channel.on("webrtc:ice_candidate", async ({ candidate }: { candidate: RTCIceCandidateInit }) => {
        await pc.addIceCandidate(new RTCIceCandidate(candidate));
      });

      channel.on("chat:message", (msg: { text: string; from: string; timestamp: number }) => {
        setChatMessages((prev) => [
          ...prev,
          {
            id: `${msg.timestamp}-${msg.from}`,
            text: msg.text,
            from: msg.from,
            timestamp: msg.timestamp,
            isSelf: msg.from === userId,
          },
        ]);
      });

      channel.on("media:state_changed", (state: { user_id: string; audio: boolean; video: boolean }) => {
        setParticipants((prev) => ({
          ...prev,
          [state.user_id]: { ...((prev[state.user_id] as object) ?? {}), ...state },
        }));
      });

      // 5. Join and create offer if first
      channel
        .join()
        .receive("ok", async () => {
          setConnectionState("waiting");
          // Small delay to let the other participant join
          setTimeout(async () => {
            const offer = await pc.createOffer();
            await pc.setLocalDescription(offer);
            channel.push("webrtc:offer", { sdp: offer, to: "all" });
          }, 500);
        })
        .receive("error", () => setConnectionState("error"));
    };

    init();

    return () => {
      cancelled = true;
      localStreamRef.current?.getTracks().forEach((t) => t.stop());
      peerConnectionRef.current?.close();
      channelRef.current?.leave();
      socketRef.current?.disconnect();
    };
  }, [sessionId, sessionToken, createPeerConnection, getIceServers, userId]);

  // Auto-scroll chat
  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [chatMessages]);

  const toggleMute = () => {
    const track = localStreamRef.current?.getAudioTracks()[0];
    if (track) {
      track.enabled = !track.enabled;
      setIsMuted(!track.enabled);
      channelRef.current?.push("media:state_changed", {
        audio: track.enabled,
        video: !isVideoOff,
      });
    }
  };

  const toggleVideo = () => {
    const track = localStreamRef.current?.getVideoTracks()[0];
    if (track) {
      track.enabled = !track.enabled;
      setIsVideoOff(!track.enabled);
      channelRef.current?.push("media:state_changed", {
        audio: !isMuted,
        video: track.enabled,
      });
    }
  };

  const sendChat = () => {
    if (!chatInput.trim() || !channelRef.current) return;
    channelRef.current.push("chat:message", { text: chatInput.trim() });
    setChatInput("");
  };

  const endSession = async () => {
    if (sessionId) {
      await api.endSession(sessionId).catch(() => {});
    }
    localStreamRef.current?.getTracks().forEach((t) => t.stop());
    peerConnectionRef.current?.close();
    channelRef.current?.leave();
    setConnectionState("ended");
  };

  if (connectionState === "ended") {
    return (
      <div
        style={{
          minHeight: "100vh",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          flexDirection: "column",
          gap: "16px",
          backgroundColor: "#1a1a2e",
          color: "white",
        }}
      >
        <div style={{ fontSize: "48px" }}>✅</div>
        <h1 style={{ fontSize: "24px", fontWeight: "700" }}>Interview Complete</h1>
        <p style={{ color: "#94a3b8" }}>
          The session has ended. Your AI scorecard will be ready shortly.
        </p>
      </div>
    );
  }

  return (
    <div
      style={{
        minHeight: "100vh",
        backgroundColor: "#0f0f1a",
        display: "flex",
        flexDirection: "column",
      }}
    >
      {/* Topbar */}
      <div
        style={{
          height: "52px",
          backgroundColor: "#1a1a2e",
          borderBottom: "1px solid rgba(255,255,255,0.1)",
          display: "flex",
          alignItems: "center",
          padding: "0 20px",
          justifyContent: "space-between",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
          <span style={{ color: "#818cf8", fontWeight: "700", fontSize: "16px" }}>
            InterviewFlow
          </span>
          <span
            style={{
              fontSize: "12px",
              padding: "3px 8px",
              borderRadius: "4px",
              backgroundColor:
                connectionState === "active"
                  ? "#166534"
                  : connectionState === "waiting"
                  ? "#713f12"
                  : connectionState === "error"
                  ? "#991b1b"
                  : "#1e3a5f",
              color: "white",
            }}
          >
            {connectionState === "active"
              ? "● Live"
              : connectionState === "waiting"
              ? "Waiting for participant..."
              : connectionState === "connecting"
              ? "Connecting..."
              : connectionState === "error"
              ? "Connection Error"
              : connectionState}
          </span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
          <span style={{ fontSize: "13px", color: "#64748b" }}>
            {Object.keys(participants).length} participant
            {Object.keys(participants).length !== 1 ? "s" : ""}
          </span>
        </div>
      </div>

      {/* Main area */}
      <div style={{ flex: 1, display: "grid", gridTemplateColumns: "1fr 320px", overflow: "hidden" }}>
        {/* Left: video + code */}
        <div style={{ display: "flex", flexDirection: "column", overflow: "hidden" }}>
          {/* Videos */}
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "1fr 1fr",
              gap: "4px",
              backgroundColor: "#0f0f1a",
              height: "220px",
              padding: "4px",
            }}
          >
            <div style={{ position: "relative", backgroundColor: "#1a1a2e", borderRadius: "6px", overflow: "hidden" }}>
              <video
                ref={localVideoRef}
                autoPlay
                muted
                playsInline
                style={{ width: "100%", height: "100%", objectFit: "cover" }}
              />
              <span
                style={{
                  position: "absolute",
                  bottom: "8px",
                  left: "8px",
                  fontSize: "11px",
                  color: "white",
                  backgroundColor: "rgba(0,0,0,0.5)",
                  padding: "2px 6px",
                  borderRadius: "4px",
                }}
              >
                You {isMuted && "🔇"} {isVideoOff && "📵"}
              </span>
            </div>
            <div style={{ position: "relative", backgroundColor: "#1a1a2e", borderRadius: "6px", overflow: "hidden" }}>
              <video
                ref={remoteVideoRef}
                autoPlay
                playsInline
                style={{ width: "100%", height: "100%", objectFit: "cover" }}
              />
              {connectionState !== "active" && (
                <div
                  style={{
                    position: "absolute",
                    inset: 0,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    flexDirection: "column",
                    gap: "8px",
                    color: "#64748b",
                  }}
                >
                  <LoadingSpinner size="md" />
                  <span style={{ fontSize: "12px" }}>Waiting...</span>
                </div>
              )}
            </div>
          </div>

          {/* Code editor tabs */}
          <div
            style={{
              flex: 1,
              display: "flex",
              flexDirection: "column",
              backgroundColor: "#1e1e1e",
              overflow: "hidden",
            }}
          >
            <div style={{ display: "flex", padding: "0 16px", gap: "4px", borderBottom: "1px solid #333" }}>
              <button
                onClick={() => setActiveTab("code")}
                style={{
                  padding: "8px 14px",
                  fontSize: "13px",
                  color: activeTab === "code" ? "#818cf8" : "#64748b",
                  borderBottom: activeTab === "code" ? "2px solid #818cf8" : "2px solid transparent",
                  background: "none",
                  border: "none",
                  borderBottom: activeTab === "code" ? "2px solid #818cf8" : "2px solid transparent",
                  cursor: "pointer",
                }}
              >
                Code Editor
              </button>
              <select
                value={codeLanguage}
                onChange={(e) => setCodeLanguage(e.target.value)}
                style={{
                  marginLeft: "auto",
                  padding: "4px 8px",
                  fontSize: "12px",
                  backgroundColor: "#1e1e1e",
                  color: "#94a3b8",
                  border: "1px solid #333",
                  borderRadius: "4px",
                  cursor: "pointer",
                  alignSelf: "center",
                }}
              >
                <option value="javascript">JavaScript</option>
                <option value="typescript">TypeScript</option>
                <option value="python">Python</option>
                <option value="go">Go</option>
                <option value="java">Java</option>
              </select>
            </div>
            <div style={{ flex: 1, overflow: "hidden" }}>
              <Editor
                height="100%"
                language={codeLanguage}
                value={code}
                onChange={(val) => setCode(val ?? "")}
                theme="vs-dark"
                options={{
                  fontSize: 14,
                  minimap: { enabled: false },
                  lineNumbers: "on",
                  wordWrap: "on",
                  automaticLayout: true,
                  tabSize: 2,
                  scrollBeyondLastLine: false,
                }}
              />
            </div>
          </div>
        </div>

        {/* Right: chat + controls */}
        <div
          style={{
            backgroundColor: "#1a1a2e",
            borderLeft: "1px solid rgba(255,255,255,0.08)",
            display: "flex",
            flexDirection: "column",
          }}
        >
          {/* Chat messages */}
          <div
            style={{
              flex: 1,
              overflowY: "auto",
              padding: "16px",
              display: "flex",
              flexDirection: "column",
              gap: "10px",
            }}
          >
            {chatMessages.length === 0 && (
              <div style={{ textAlign: "center", color: "#475569", fontSize: "13px", padding: "40px 0" }}>
                Chat messages will appear here
              </div>
            )}
            {chatMessages.map((msg) => (
              <div
                key={msg.id}
                style={{
                  display: "flex",
                  flexDirection: "column",
                  alignItems: msg.isSelf ? "flex-end" : "flex-start",
                }}
              >
                <div
                  style={{
                    maxWidth: "85%",
                    padding: "8px 12px",
                    borderRadius: msg.isSelf ? "12px 12px 2px 12px" : "12px 12px 12px 2px",
                    backgroundColor: msg.isSelf ? "#6366f1" : "#2d3748",
                    color: "white",
                    fontSize: "13px",
                    lineHeight: "1.4",
                  }}
                >
                  {msg.text}
                </div>
              </div>
            ))}
            <div ref={chatEndRef} />
          </div>

          {/* Chat input */}
          <div style={{ padding: "12px", borderTop: "1px solid rgba(255,255,255,0.08)" }}>
            <div style={{ display: "flex", gap: "8px" }}>
              <input
                type="text"
                value={chatInput}
                onChange={(e) => setChatInput(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && sendChat()}
                placeholder="Type a message..."
                style={{
                  flex: 1,
                  padding: "8px 12px",
                  fontSize: "13px",
                  backgroundColor: "#0f0f1a",
                  border: "1px solid rgba(255,255,255,0.1)",
                  borderRadius: "6px",
                  color: "white",
                  outline: "none",
                }}
              />
              <button
                onClick={sendChat}
                style={{
                  padding: "8px 14px",
                  fontSize: "13px",
                  color: "white",
                  backgroundColor: "#6366f1",
                  border: "none",
                  borderRadius: "6px",
                  cursor: "pointer",
                }}
              >
                Send
              </button>
            </div>
          </div>

          {/* Media controls */}
          <div
            style={{
              padding: "14px",
              borderTop: "1px solid rgba(255,255,255,0.08)",
              display: "flex",
              gap: "8px",
              justifyContent: "center",
            }}
          >
            <button
              onClick={toggleMute}
              title={isMuted ? "Unmute" : "Mute"}
              style={{
                width: "44px",
                height: "44px",
                borderRadius: "50%",
                border: "none",
                backgroundColor: isMuted ? "#7f1d1d" : "#374151",
                color: "white",
                fontSize: "18px",
                cursor: "pointer",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              {isMuted ? "🔇" : "🎙"}
            </button>
            <button
              onClick={toggleVideo}
              title={isVideoOff ? "Turn on camera" : "Turn off camera"}
              style={{
                width: "44px",
                height: "44px",
                borderRadius: "50%",
                border: "none",
                backgroundColor: isVideoOff ? "#7f1d1d" : "#374151",
                color: "white",
                fontSize: "18px",
                cursor: "pointer",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              {isVideoOff ? "📵" : "📹"}
            </button>
            <button
              onClick={endSession}
              title="End interview"
              style={{
                width: "44px",
                height: "44px",
                borderRadius: "50%",
                border: "none",
                backgroundColor: "#dc2626",
                color: "white",
                fontSize: "18px",
                cursor: "pointer",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              ☎
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
