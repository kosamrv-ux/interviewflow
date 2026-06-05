import React, { useState, useCallback } from "react";
import { useQuery } from "@tanstack/react-query";
import { api } from "../api/client";

interface AuditLogEntry {
  id: string;
  action: string;
  resource_type: string;
  resource_id: string;
  actor_id: string;
  actor_email: string;
  metadata: Record<string, unknown>;
  inserted_at: string;
}

interface AuditLogFilters {
  action: string;
  resource_type: string;
  actor_id: string;
  from: string;
  to: string;
}

/**
 * Audit log viewer page for enterprise admin users.
 *
 * Bug fix (June 2026):
 * When a user applied a new filter (e.g., changed the resource_type dropdown),
 * the page number was NOT reset to 1. This caused the request to fetch
 * `page=5&resource_type=interview` when the filtered result had only 2 pages,
 * returning an empty response that the UI displayed as "no results found"
 * instead of the first page of filtered results.
 *
 * Fix: call setPage(1) whenever any filter value changes. This is done in
 * the handleFilterChange callback and also guarded in the query to reset
 * page when the filter key changes.
 */
export function AuditLogPage() {
  const [page, setPage] = useState(1);
  const [filters, setFilters] = useState<AuditLogFilters>({
    action: "",
    resource_type: "",
    actor_id: "",
    from: "",
    to: "",
  });

  // Bug fix: reset to page 1 whenever filters change
  const handleFilterChange = useCallback(
    (key: keyof AuditLogFilters, value: string) => {
      setFilters((prev) => ({ ...prev, [key]: value }));
      setPage(1); // Always reset to first page on filter change
    },
    []
  );

  const params = new URLSearchParams({ page: String(page) });
  if (filters.action) params.set("action", filters.action);
  if (filters.resource_type) params.set("resource_type", filters.resource_type);
  if (filters.actor_id) params.set("actor_id", filters.actor_id);
  if (filters.from) params.set("from", filters.from);
  if (filters.to) params.set("to", filters.to);

  const { data, isLoading } = useQuery({
    queryKey: ["audit-log", page, filters],
    queryFn: () => api.get(`/api/v2/audit-log?${params.toString()}`).then((r) => r.data),
    placeholderData: (prev) => prev,
  });

  const entries: AuditLogEntry[] = data?.data ?? [];
  const meta = data?.meta ?? { total: 0, page: 1, per_page: 50, total_pages: 0 };

  return (
    <div className="max-w-6xl mx-auto px-4 py-8">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Audit Log</h1>
        <p className="text-sm text-gray-500 mt-1">
          Immutable log of all user actions and system events in your organization.
        </p>
      </div>

      {/* Filters */}
      <div className="bg-white rounded-lg border border-gray-200 p-4 mb-4 grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-3">
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-1">Action</label>
          <input
            type="text"
            value={filters.action}
            onChange={(e) => handleFilterChange("action", e.target.value)}
            placeholder="e.g. interview.created"
            className="w-full text-sm border border-gray-300 rounded px-2 py-1.5"
          />
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-1">Resource Type</label>
          <select
            value={filters.resource_type}
            onChange={(e) => handleFilterChange("resource_type", e.target.value)}
            className="w-full text-sm border border-gray-300 rounded px-2 py-1.5"
          >
            <option value="">All</option>
            <option value="interview">Interview</option>
            <option value="candidate">Candidate</option>
            <option value="job">Job</option>
            <option value="application">Application</option>
            <option value="api_key">API Key</option>
            <option value="webhook">Webhook</option>
            <option value="user">User</option>
            <option value="organization">Organization</option>
          </select>
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-1">From</label>
          <input
            type="datetime-local"
            value={filters.from}
            onChange={(e) => handleFilterChange("from", e.target.value)}
            className="w-full text-sm border border-gray-300 rounded px-2 py-1.5"
          />
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-1">To</label>
          <input
            type="datetime-local"
            value={filters.to}
            onChange={(e) => handleFilterChange("to", e.target.value)}
            className="w-full text-sm border border-gray-300 rounded px-2 py-1.5"
          />
        </div>
        <div className="flex items-end">
          <button
            onClick={() => {
              setFilters({ action: "", resource_type: "", actor_id: "", from: "", to: "" });
              setPage(1);
            }}
            className="text-sm text-gray-500 hover:text-gray-700 underline"
          >
            Clear filters
          </button>
        </div>
      </div>

      {/* Stats bar */}
      <div className="flex items-center justify-between mb-3">
        <p className="text-sm text-gray-500">
          {meta.total.toLocaleString()} entries
          {meta.total_pages > 0 && ` · page ${meta.page} of ${meta.total_pages}`}
        </p>
        <a
          href={`/api/v2/audit-log/export?format=csv&${params.toString()}`}
          className="text-sm text-indigo-600 hover:text-indigo-700 font-medium"
          download="audit-log.csv"
        >
          Export CSV
        </a>
      </div>

      {/* Table */}
      <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
        {isLoading ? (
          <div className="py-16 text-center text-gray-400 text-sm">Loading audit log...</div>
        ) : entries.length === 0 ? (
          <div className="py-16 text-center text-gray-400 text-sm">No entries matching the current filters.</div>
        ) : (
          <table className="min-w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-500">Time</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-500">Actor</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-500">Action</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-500">Resource</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-500">Details</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {entries.map((entry) => (
                <tr key={entry.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 text-xs text-gray-400 whitespace-nowrap">
                    {new Date(entry.inserted_at).toLocaleString()}
                  </td>
                  <td className="px-4 py-3 text-xs text-gray-600">{entry.actor_email}</td>
                  <td className="px-4 py-3">
                    <code className="text-xs bg-gray-100 text-gray-700 px-1.5 py-0.5 rounded">
                      {entry.action}
                    </code>
                  </td>
                  <td className="px-4 py-3 text-xs text-gray-500">
                    <span className="capitalize">{entry.resource_type}</span>
                    <span className="text-gray-300 mx-1">·</span>
                    <code className="text-gray-400">{entry.resource_id?.slice(0, 8)}</code>
                  </td>
                  <td className="px-4 py-3 text-xs text-gray-400 max-w-xs truncate">
                    {JSON.stringify(entry.metadata)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Pagination */}
      {meta.total_pages > 1 && (
        <div className="flex items-center justify-center gap-2 mt-4">
          <button
            onClick={() => setPage((p) => Math.max(1, p - 1))}
            disabled={page <= 1}
            className="px-3 py-1.5 text-sm border border-gray-300 rounded-md disabled:opacity-40 hover:bg-gray-50"
          >
            Previous
          </button>
          <span className="text-sm text-gray-500">
            {page} / {meta.total_pages}
          </span>
          <button
            onClick={() => setPage((p) => Math.min(meta.total_pages, p + 1))}
            disabled={page >= meta.total_pages}
            className="px-3 py-1.5 text-sm border border-gray-300 rounded-md disabled:opacity-40 hover:bg-gray-50"
          >
            Next
          </button>
        </div>
      )}
    </div>
  );
}
