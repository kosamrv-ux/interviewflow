import { useState, useCallback } from "react";
import { Link } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { AppLayout } from "@/components/AppLayout";
import { useDebounce } from "@/hooks/useDebounce";

interface Candidate {
  id: string;
  email: string;
  full_name: string;
  phone: string | null;
  linkedin_url: string | null;
  github_url: string | null;
  source: string;
  tags: string[];
  notes: string | null;
  inserted_at: string;
}

const SOURCE_LABELS: Record<string, string> = {
  linkedin: "LinkedIn",
  referral: "Referral",
  careers_page: "Careers Page",
  github: "GitHub",
  outbound: "Outbound",
  other: "Other",
};

export function CandidatesPage() {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const [tagFilter, setTagFilter] = useState("");
  const debouncedSearch = useDebounce(search, 300);
  const debouncedTag = useDebounce(tagFilter, 300);

  const [showAddModal, setShowAddModal] = useState(false);
  const [form, setForm] = useState({
    email: "",
    full_name: "",
    phone: "",
    linkedin_url: "",
    github_url: "",
    source: "other",
    notes: "",
  });
  const [formError, setFormError] = useState<string | null>(null);

  const { data, isLoading, isError } = useQuery({
    queryKey: ["candidates", debouncedSearch, debouncedTag],
    queryFn: async () => {
      const params: Record<string, string> = {};
      if (debouncedSearch) params.search = debouncedSearch;
      if (debouncedTag) params.tags = debouncedTag;
      return api.get<{ data: Candidate[]; meta: { total: number } }>("/candidates", { params });
    },
    staleTime: 30_000,
  });

  const createMutation = useMutation({
    mutationFn: (attrs: typeof form) => api.post<Candidate>("/candidates", attrs),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["candidates"] });
      setShowAddModal(false);
      setForm({ email: "", full_name: "", phone: "", linkedin_url: "", github_url: "", source: "other", notes: "" });
      setFormError(null);
    },
    onError: (err: Error) => {
      setFormError(err.message);
    },
  });

  const handleFormChange = useCallback((e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => {
    setForm((prev) => ({ ...prev, [e.target.name]: e.target.value }));
  }, []);

  const handleSubmit = useCallback(
    (e: React.FormEvent) => {
      e.preventDefault();
      if (!form.email || !form.full_name) {
        setFormError("Email and full name are required.");
        return;
      }
      createMutation.mutate(form);
    },
    [form, createMutation],
  );

  const candidates: Candidate[] = data?.data ?? [];

  return (
    <AppLayout>
      <div className="p-6 max-w-6xl mx-auto">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-2xl font-semibold text-gray-900">Candidates</h1>
            {data && (
              <p className="text-sm text-gray-500 mt-1">{data.meta.total} total</p>
            )}
          </div>
          <button
            onClick={() => setShowAddModal(true)}
            className="px-4 py-2 bg-indigo-600 text-white rounded-lg text-sm font-medium hover:bg-indigo-700 transition-colors"
          >
            Add Candidate
          </button>
        </div>

        {/* Filters */}
        <div className="flex gap-3 mb-6">
          <div className="flex-1 relative">
            <input
              type="text"
              placeholder="Search by name or email..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-10 pr-4 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300"
            />
            <svg className="absolute left-3 top-2.5 h-4 w-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-4.35-4.35M17 11A6 6 0 1 1 5 11a6 6 0 0 1 12 0z" />
            </svg>
          </div>
          <input
            type="text"
            placeholder="Filter by tag..."
            value={tagFilter}
            onChange={(e) => setTagFilter(e.target.value)}
            className="w-48 px-4 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300"
          />
        </div>

        {/* Table */}
        {isLoading && (
          <div className="flex items-center justify-center h-48 text-gray-400 text-sm">Loading...</div>
        )}

        {isError && (
          <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-sm text-red-700">
            Failed to load candidates. Please try again.
          </div>
        )}

        {!isLoading && !isError && candidates.length === 0 && (
          <div className="flex flex-col items-center justify-center h-48 text-gray-400">
            <p className="text-sm">No candidates found.</p>
            {search && (
              <button onClick={() => setSearch("")} className="mt-2 text-xs text-indigo-600 hover:underline">
                Clear search
              </button>
            )}
          </div>
        )}

        {candidates.length > 0 && (
          <div className="bg-white border border-gray-200 rounded-xl overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-100 bg-gray-50">
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Name</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Email</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Source</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Tags</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Added</th>
                  <th className="px-4 py-3"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {candidates.map((c) => (
                  <tr key={c.id} className="hover:bg-gray-50 transition-colors">
                    <td className="px-4 py-3 font-medium text-gray-900">{c.full_name}</td>
                    <td className="px-4 py-3 text-gray-500">{c.email}</td>
                    <td className="px-4 py-3">
                      <span className="inline-flex items-center px-2 py-0.5 rounded-full text-xs bg-gray-100 text-gray-600">
                        {SOURCE_LABELS[c.source] ?? c.source}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex flex-wrap gap-1">
                        {c.tags.map((tag) => (
                          <span key={tag} className="px-2 py-0.5 rounded-full text-xs bg-indigo-50 text-indigo-700">
                            {tag}
                          </span>
                        ))}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-gray-400 text-xs">
                      {new Date(c.inserted_at).toLocaleDateString()}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Link
                        to={`/candidates/${c.id}`}
                        className="text-indigo-600 hover:text-indigo-800 text-xs font-medium"
                      >
                        View
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Add Candidate Modal */}
      {showAddModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="bg-white rounded-xl shadow-xl w-full max-w-lg mx-4 p-6">
            <h2 className="text-lg font-semibold text-gray-900 mb-4">Add Candidate</h2>

            {formError && (
              <div className="mb-4 bg-red-50 border border-red-200 rounded-lg px-4 py-2 text-sm text-red-700">
                {formError}
              </div>
            )}

            <form onSubmit={handleSubmit} className="space-y-3">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">Full Name *</label>
                  <input
                    name="full_name"
                    value={form.full_name}
                    onChange={handleFormChange}
                    className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300"
                    placeholder="Jane Doe"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">Email *</label>
                  <input
                    name="email"
                    type="email"
                    value={form.email}
                    onChange={handleFormChange}
                    className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300"
                    placeholder="jane@example.com"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">Phone</label>
                  <input
                    name="phone"
                    value={form.phone}
                    onChange={handleFormChange}
                    className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300"
                    placeholder="+1 555 000 0000"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">Source</label>
                  <select
                    name="source"
                    value={form.source}
                    onChange={handleFormChange}
                    className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300"
                  >
                    {Object.entries(SOURCE_LABELS).map(([v, l]) => (
                      <option key={v} value={v}>{l}</option>
                    ))}
                  </select>
                </div>
              </div>

              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">LinkedIn URL</label>
                <input
                  name="linkedin_url"
                  value={form.linkedin_url}
                  onChange={handleFormChange}
                  className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300"
                  placeholder="https://linkedin.com/in/..."
                />
              </div>

              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Notes</label>
                <textarea
                  name="notes"
                  value={form.notes}
                  onChange={handleFormChange}
                  rows={3}
                  className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300 resize-none"
                  placeholder="Internal notes about this candidate..."
                />
              </div>

              <div className="flex justify-end gap-3 pt-2">
                <button
                  type="button"
                  onClick={() => setShowAddModal(false)}
                  className="px-4 py-2 text-sm text-gray-600 hover:text-gray-800"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={createMutation.isPending}
                  className="px-4 py-2 bg-indigo-600 text-white rounded-lg text-sm font-medium hover:bg-indigo-700 disabled:opacity-50 transition-colors"
                >
                  {createMutation.isPending ? "Adding..." : "Add Candidate"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </AppLayout>
  );
}
