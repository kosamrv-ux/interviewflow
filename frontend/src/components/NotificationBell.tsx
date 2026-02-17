import { useState, useRef, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useNotifications, type Notification } from '../hooks/useNotifications';

const TYPE_LABELS: Record<string, string> = {
  score_ready: 'AI Score Ready',
  interview_reminder: 'Interview Reminder',
  application_advanced: 'Stage Advanced',
  invitation_accepted: 'Invitation Accepted',
  job_published: 'Job Published',
};

const TYPE_COLORS: Record<string, string> = {
  score_ready: 'bg-indigo-100 text-indigo-700',
  interview_reminder: 'bg-amber-100 text-amber-700',
  application_advanced: 'bg-green-100 text-green-700',
  invitation_accepted: 'bg-blue-100 text-blue-700',
  job_published: 'bg-purple-100 text-purple-700',
};

function formatRelativeTime(date: Date): string {
  const diff = Date.now() - date.getTime();
  if (diff < 60_000) return 'just now';
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)}m ago`;
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)}h ago`;
  return date.toLocaleDateString();
}

function NotificationItem({
  notification,
  onRead,
}: {
  notification: Notification;
  onRead: (id: string) => void;
}) {
  const navigate = useNavigate();

  const handleClick = () => {
    onRead(notification.id);
    const payload = notification.payload;
    if (notification.type === 'score_ready' && payload.application_id) {
      navigate(`/applications/${payload.application_id}`);
    } else if (notification.type === 'interview_reminder' && payload.interview_id) {
      navigate(`/interviews/${payload.interview_id}`);
    }
  };

  return (
    <button
      onClick={handleClick}
      className={`flex w-full items-start gap-3 px-4 py-3 text-left hover:bg-gray-50 ${
        !notification.read ? 'bg-indigo-50/30' : ''
      }`}
    >
      <span
        className={`mt-0.5 shrink-0 rounded-full px-2 py-0.5 text-xs font-medium ${
          TYPE_COLORS[notification.type] ?? 'bg-gray-100 text-gray-600'
        }`}
      >
        {TYPE_LABELS[notification.type] ?? notification.type}
      </span>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm text-gray-700">
          {getDescription(notification)}
        </p>
        <p className="mt-0.5 text-xs text-gray-400">
          {formatRelativeTime(notification.receivedAt)}
        </p>
      </div>
      {!notification.read && (
        <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-indigo-500" />
      )}
    </button>
  );
}

function getDescription(n: Notification): string {
  switch (n.type) {
    case 'score_ready':
      return `AI score ready — ${Math.round((n.payload.composite_score as number) * 100)} pts`;
    case 'interview_reminder':
      return `Interview in ${n.payload.minutes_until} minutes`;
    case 'application_advanced':
      return `Application moved from ${n.payload.from} to ${n.payload.to}`;
    default:
      return TYPE_LABELS[n.type] ?? 'New notification';
  }
}

export function NotificationBell() {
  const { notifications, unreadCount, markRead, markAllRead, clearAll } = useNotifications();
  const [open, setOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close on outside click
  useEffect(() => {
    const handle = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', handle);
    return () => document.removeEventListener('mousedown', handle);
  }, []);

  return (
    <div ref={dropdownRef} className="relative">
      <button
        onClick={() => setOpen((o) => !o)}
        className="relative rounded-full p-2 text-gray-500 hover:bg-gray-100 hover:text-gray-700"
        aria-label={`Notifications${unreadCount > 0 ? ` (${unreadCount} unread)` : ''}`}
      >
        <svg className="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"
          />
        </svg>
        {unreadCount > 0 && (
          <span className="absolute -right-0.5 -top-0.5 flex h-4 w-4 items-center justify-center rounded-full bg-indigo-600 text-[10px] font-bold text-white">
            {unreadCount > 9 ? '9+' : unreadCount}
          </span>
        )}
      </button>

      {open && (
        <div className="absolute right-0 z-50 mt-2 w-80 overflow-hidden rounded-xl border border-gray-200 bg-white shadow-lg">
          <div className="flex items-center justify-between border-b border-gray-100 px-4 py-3">
            <h3 className="text-sm font-semibold text-gray-800">Notifications</h3>
            <div className="flex gap-2">
              {unreadCount > 0 && (
                <button
                  onClick={markAllRead}
                  className="text-xs text-indigo-600 hover:underline"
                >
                  Mark all read
                </button>
              )}
              {notifications.length > 0 && (
                <button onClick={clearAll} className="text-xs text-gray-400 hover:underline">
                  Clear
                </button>
              )}
            </div>
          </div>

          <div className="max-h-80 divide-y divide-gray-100 overflow-y-auto">
            {notifications.length === 0 ? (
              <div className="px-4 py-8 text-center text-sm text-gray-400">
                No notifications yet
              </div>
            ) : (
              notifications.map((n) => (
                <NotificationItem key={n.id} notification={n} onRead={markRead} />
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
}
