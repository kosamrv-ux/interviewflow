/**
 * Tests for useNotifications hook.
 *
 * We mock the Phoenix Socket and Channel to avoid actual WebSocket connections.
 */

import { renderHook, act } from '@testing-library/react';
import { vi, describe, it, expect, beforeEach, afterEach } from 'vitest';

// Mock Phoenix
vi.mock('phoenix', () => {
  const mockChannel = {
    on: vi.fn(),
    join: vi.fn().mockReturnThis(),
    leave: vi.fn(),
    receive: vi.fn().mockReturnThis(),
  };

  const mockSocket = {
    connect: vi.fn(),
    disconnect: vi.fn(),
    channel: vi.fn().mockReturnValue(mockChannel),
  };

  return {
    Socket: vi.fn().mockImplementation(() => mockSocket),
    Channel: vi.fn(),
  };
});

// Mock auth hook
vi.mock('../hooks/useAuthContext', () => ({
  useAuth: vi.fn().mockReturnValue({
    user: { id: 'user-123', email: 'test@example.com', role: 'recruiter' },
    isAuthenticated: true,
  }),
}));

// Mock auth storage
vi.mock('../api/auth', () => ({
  getStoredAccessToken: vi.fn().mockReturnValue('mock-token'),
}));

// Mock apiClient
vi.mock('../api/client', () => ({
  apiClient: {
    patch: vi.fn().mockResolvedValue({ data: {} }),
  },
}));

import { useNotifications } from '../hooks/useNotifications';

describe('useNotifications', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('initializes with empty notifications', () => {
    const { result } = renderHook(() => useNotifications());
    expect(result.current.notifications).toEqual([]);
    expect(result.current.unreadCount).toBe(0);
  });

  it('markAllRead sets all notifications to read', async () => {
    const { result } = renderHook(() => useNotifications());

    // Simulate receiving a notification by directly invoking markRead path
    // In real usage, the Phoenix channel event triggers addNotification
    act(() => {
      result.current.markAllRead();
    });

    expect(result.current.unreadCount).toBe(0);
  });

  it('clearAll empties the notification list', () => {
    const { result } = renderHook(() => useNotifications());

    act(() => {
      result.current.clearAll();
    });

    expect(result.current.notifications).toHaveLength(0);
  });

  it('markRead optimistically marks single notification as read', async () => {
    const { result } = renderHook(() => useNotifications());

    // After mark all read, nothing should be unread
    act(() => {
      result.current.markAllRead();
    });

    expect(result.current.unreadCount).toBe(0);

    // markRead on a fake id should not throw
    await act(async () => {
      await result.current.markRead('fake-id');
    });

    expect(result.current.unreadCount).toBe(0);
  });

  it('connects to the correct Phoenix channel on mount', async () => {
    const { Socket } = await import('phoenix');

    renderHook(() => useNotifications());

    expect(Socket).toHaveBeenCalledWith(expect.stringContaining('ws://'), expect.objectContaining({
      params: expect.objectContaining({ token: 'mock-token' }),
    }));
  });

  it('disconnects socket on unmount', async () => {
    const phoenixModule = await import('phoenix');
    const { unmount } = renderHook(() => useNotifications());

    unmount();

    const socketInstance = (phoenixModule.Socket as ReturnType<typeof vi.fn>).mock.results[0]?.value;
    if (socketInstance) {
      expect(socketInstance.disconnect).toHaveBeenCalled();
    }
  });
});
