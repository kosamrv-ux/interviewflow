/**
 * useNotifications — subscribes to the Phoenix NotificationsChannel and
 * exposes a typed notification stream to React components.
 *
 * Features:
 * - Connects on mount, disconnects on unmount
 * - Queues notifications in local state (max 50)
 * - Marks individual notifications as read via REST
 * - Exposes unread count for badge display
 */

import { useEffect, useRef, useState, useCallback } from 'react';
import { Socket, Channel } from 'phoenix';
import { useAuth } from './useAuthContext';
import { getStoredAccessToken } from '../api/auth';
import { apiClient } from '../api/client';

export type NotificationType =
  | 'score_ready'
  | 'interview_reminder'
  | 'application_advanced'
  | 'invitation_accepted'
  | 'job_published';

export interface Notification {
  id: string;
  type: NotificationType;
  payload: Record<string, unknown>;
  receivedAt: Date;
  read: boolean;
}

const MAX_NOTIFICATIONS = 50;
const WS_URL = import.meta.env.VITE_WS_URL ?? 'ws://localhost:4000/socket';

export function useNotifications() {
  const { user, isAuthenticated } = useAuth();
  const socketRef = useRef<Socket | null>(null);
  const channelRef = useRef<Channel | null>(null);
  const [notifications, setNotifications] = useState<Notification[]>([]);

  const unreadCount = notifications.filter((n) => !n.read).length;

  const addNotification = useCallback((type: NotificationType, payload: Record<string, unknown>) => {
    const notification: Notification = {
      id: crypto.randomUUID(),
      type,
      payload,
      receivedAt: new Date(),
      read: false,
    };

    setNotifications((prev) => [notification, ...prev].slice(0, MAX_NOTIFICATIONS));
  }, []);

  const markRead = useCallback(async (notificationId: string) => {
    setNotifications((prev) =>
      prev.map((n) => (n.id === notificationId ? { ...n, read: true } : n)),
    );
    try {
      await apiClient.patch(`/notifications/${notificationId}/read`, {});
    } catch {
      // Optimistic update — failure is non-critical
    }
  }, []);

  const markAllRead = useCallback(() => {
    setNotifications((prev) => prev.map((n) => ({ ...n, read: true })));
  }, []);

  const clearAll = useCallback(() => {
    setNotifications([]);
  }, []);

  useEffect(() => {
    if (!isAuthenticated || !user) return;

    const token = getStoredAccessToken();
    const socket = new Socket(WS_URL, { params: { token } });
    socketRef.current = socket;
    socket.connect();

    const channel = socket.channel(`notifications:${user.id}`, {});
    channelRef.current = channel;

    const eventHandlers: NotificationType[] = [
      'score_ready',
      'interview_reminder',
      'application_advanced',
      'invitation_accepted',
      'job_published',
    ];

    eventHandlers.forEach((event) => {
      channel.on(event, (payload: Record<string, unknown>) => {
        addNotification(event, payload);
      });
    });

    channel
      .join()
      .receive('ok', () => {
        console.debug('[NotificationsChannel] joined');
      })
      .receive('error', (resp: unknown) => {
        console.error('[NotificationsChannel] join error', resp);
      });

    return () => {
      channel.leave();
      socket.disconnect();
    };
  }, [isAuthenticated, user, addNotification]);

  return {
    notifications,
    unreadCount,
    markRead,
    markAllRead,
    clearAll,
  };
}
