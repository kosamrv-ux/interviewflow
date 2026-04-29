import React, { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "../api/client";

interface ApiKey {
  id: string;
  name: string;
  key_prefix: string;
  scopes: string[];
  last_used_at: string | null;
  expires_at: string | null;
  inserted_at: string;
}

interface NewKeyReveal {
  id: string;
  rawKey: string;
}

export function ApiKeysPage() {
  const queryClient = useQueryClient();
  const [showCreate, setShowCreate] = useState(false);
  const [revealedKey, setRevealedKey] = useState<NewKeyReveal | null>(null);

  const { data: keys = [], isLoading } = useQuery<ApiKey[]>({
    queryKey: ["api-keys"],
    queryFn: () => api.get("/api/v1/api-keys").then((r) => r.data),
  });

  const createKey = useMutation({
    mutationFn: (payload: { name: string; scopes: string[]; expires_at?: string }) =>
      api.post("/api/v1/api-keys", { api_key: payload }),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ["api-keys"] });
      setRevealedKey({ id: res.data.data.id, rawKey: res.data.key });
      setShowCreate(false);
    },
  });

  const rotateKey = useMutation({
    mutationFn: (id: string) => api.post(`/api/v1/api-keys/${id}/rotate`, {}),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ["api-keys"] });
      setRevealedKey({ id: res.data.data.id, rawKey: res.data.key });
    },
  });

  const revokeKey = useMutation({
    mutationFn: (id: string) => api.delete(`/api/v1/api-keys/${id}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["api-keys"] });
    },
  });

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">API Keys</h1>
          <p className="text-sm text-gray-500 mt-1">
            Manage API keys for programmatic access to InterviewFlow.
          </p>
        </div>
        <button
          onClick={() => setShowCreate(true)}
          className="px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700"
        >
          Create Key
        </button>
      </div>

      {revealedKey && (
        <div className="mb-6 bg-green-50 border border-green-200 rounded-lg p-4">
          <p className="text-sm font-medium text-green-800 mb-2">
            API key created. Copy it now — it won't be shown again.
          </p>
          <div className="flex items-center gap-2">
            <code className="flex-1 bg-white border border-green-200 rounded px-3 py-2 text-sm font-mono text-gray-800 break-all">
              {revealedKey.rawKey}
            </code>
            <button
              onClick={() => navigator.clipboard.writeText(revealedKey.rawKey)}
              className="px-3 py-2 bg-green-600 text-white text-xs font-medium rounded-md hover:bg-green-700 whitespace-nowrap"
            >
              Copy
            </button>
          </div>
          <button
            onClick={() => setRevealedKey(null)}
            className="text-xs text-green-700 underline mt-2"
          >
            I've saved this key
          </button>
        </div>
      )}

      {showCreate && (
        <CreateKeyModal
          onSubmit={(data) => createKey.mutate(data)}
          onCancel={() => setShowCreate(false)}
          submitting={createKey.isPending}
        />
      )}

      {isLoading ? (
        <div className="text-sm text-gray-400 py-8 text-center">Loading API keys...</div>
      ) : keys.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">🔑</p>
          <p className="text-sm">No API keys yet. Create one to get started.</p>
        </div>
      ) : (
        <div className="bg-white rounded-lg border border-gray-200 divide-y divide-gray-100">
          {keys.map((key) => (
            <ApiKeyRow
              key={key.id}
              apiKey={key}
              onRotate={() => rotateKey.mutate(key.id)}
              onRevoke={() => revokeKey.mutate(key.id)}
            />
          ))}
        </div>
      )}

      <div className="mt-8 bg-gray-50 rounded-lg border border-gray-200 p-6">
        <h2 className="text-sm font-semibold text-gray-900 mb-3">Using the API</h2>
        <p className="text-sm text-gray-600 mb-3">
          Include your API key in the <code className="bg-gray-100 px-1 rounded">Authorization</code> header:
        </p>
        <pre className="bg-gray-900 text-green-400 text-xs rounded-md p-4 overflow-x-auto">
          {`curl https://api.interviewflow.io/api/v2/interviews \\
  -H "Authorization: Bearer if_live_your_key_here"`}
        </pre>
      </div>
    </div>
  );
}

function ApiKeyRow({
  apiKey,
  onRotate,
  onRevoke,
}: {
  apiKey: ApiKey;
  onRotate: () => void;
  onRevoke: () => void;
}) {
  const [confirmRevoke, setConfirmRevoke] = useState(false);

  const isExpired = apiKey.expires_at
    ? new Date(apiKey.expires_at) < new Date()
    : false;

  return (
    <div className="px-6 py-4">
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="text-sm font-medium text-gray-900">{apiKey.name}</span>
            {isExpired && (
              <span className="px-1.5 py-0.5 text-xs bg-red-100 text-red-600 rounded-full">Expired</span>
            )}
          </div>
          <code className="text-xs text-gray-400 font-mono">{apiKey.key_prefix}••••••••••••••••</code>
          <div className="flex flex-wrap gap-1 mt-2">
            {apiKey.scopes.map((s) => (
              <span key={s} className="px-1.5 py-0.5 bg-gray-100 text-gray-600 text-xs rounded">
                {s}
              </span>
            ))}
          </div>
          <p className="text-xs text-gray-400 mt-2">
            Created {new Date(apiKey.inserted_at).toLocaleDateString()}
            {apiKey.last_used_at && ` · Last used ${new Date(apiKey.last_used_at).toLocaleDateString()}`}
            {apiKey.expires_at && ` · Expires ${new Date(apiKey.expires_at).toLocaleDateString()}`}
          </p>
        </div>
        <div className="flex items-center gap-2 ml-4 shrink-0">
          <button
            onClick={onRotate}
            className="text-xs text-indigo-600 hover:text-indigo-700 font-medium"
          >
            Rotate
          </button>
          {confirmRevoke ? (
            <>
              <button
                onClick={onRevoke}
                className="text-xs text-red-600 hover:text-red-700 font-medium"
              >
                Confirm
              </button>
              <button
                onClick={() => setConfirmRevoke(false)}
                className="text-xs text-gray-400 hover:text-gray-600"
              >
                Cancel
              </button>
            </>
          ) : (
            <button
              onClick={() => setConfirmRevoke(true)}
              className="text-xs text-red-600 hover:text-red-700 font-medium"
            >
              Revoke
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

function CreateKeyModal({
  onSubmit,
  onCancel,
  submitting,
}: {
  onSubmit: (data: { name: string; scopes: string[]; expires_at?: string }) => void;
  onCancel: () => void;
  submitting: boolean;
}) {
  const [name, setName] = useState("");
  const [scopes, setScopes] = useState<string[]>(["read"]);
  const [expiresAt, setExpiresAt] = useState("");

  const toggleScope = (scope: string) => {
    setScopes((prev) =>
      prev.includes(scope) ? prev.filter((s) => s !== scope) : [...prev, scope]
    );
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg shadow-xl p-6 w-full max-w-md">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">Create API Key</h2>
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Name</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Production integration"
              className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Scopes</label>
            <div className="space-y-2">
              {["read", "write", "admin"].map((s) => (
                <label key={s} className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={scopes.includes(s)}
                    onChange={() => toggleScope(s)}
                    className="rounded border-gray-300 text-indigo-600"
                  />
                  <span className="text-sm text-gray-700 capitalize">{s}</span>
                  <span className="text-xs text-gray-400">
                    {s === "read" && "— Read-only access"}
                    {s === "write" && "— Create and update resources"}
                    {s === "admin" && "— Full access including org management"}
                  </span>
                </label>
              ))}
            </div>
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Expires (optional)
            </label>
            <input
              type="date"
              value={expiresAt}
              onChange={(e) => setExpiresAt(e.target.value)}
              min={new Date().toISOString().split("T")[0]}
              className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm"
            />
          </div>
        </div>
        <div className="flex justify-end gap-3 mt-6">
          <button onClick={onCancel} className="px-4 py-2 text-sm text-gray-600 hover:text-gray-800">
            Cancel
          </button>
          <button
            onClick={() =>
              onSubmit({ name, scopes, ...(expiresAt ? { expires_at: `${expiresAt}T23:59:59Z` } : {}) })
            }
            disabled={!name.trim() || scopes.length === 0 || submitting}
            className="px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700 disabled:opacity-50"
          >
            {submitting ? "Creating..." : "Create Key"}
          </button>
        </div>
      </div>
    </div>
  );
}
