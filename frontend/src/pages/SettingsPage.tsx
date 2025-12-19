import { useState, useCallback } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { AppLayout } from "@/components/AppLayout";
import { useAuthStore } from "@/hooks/useAuthStore";

interface TeamMember {
  id: string;
  email: string;
  full_name: string;
  role: "admin" | "recruiter" | "interviewer";
  confirmed_at: string | null;
  last_sign_in_at: string | null;
  inserted_at: string;
}

const ROLE_LABELS: Record<string, string> = {
  admin: "Admin",
  recruiter: "Recruiter",
  interviewer: "Interviewer",
};

const ROLE_COLORS: Record<string, string> = {
  admin: "bg-purple-100 text-purple-700",
  recruiter: "bg-blue-100 text-blue-700",
  interviewer: "bg-green-100 text-green-700",
};

type SettingsTab = "team" | "profile" | "company";

export function SettingsPage() {
  const { user } = useAuthStore();
  const queryClient = useQueryClient();
  const [activeTab, setActiveTab] = useState<SettingsTab>("team");
  const [showInviteModal, setShowInviteModal] = useState(false);

  const [inviteForm, setInviteForm] = useState({
    email: "",
    full_name: "",
    role: "recruiter",
    password: "",
  });
  const [inviteError, setInviteError] = useState<string | null>(null);

  const [profileForm, setProfileForm] = useState({
    full_name: user?.full_name ?? "",
    avatar_url: "",
  });
  const [profileSaved, setProfileSaved] = useState(false);

  const { data: teamData, isLoading: teamLoading } = useQuery({
    queryKey: ["team"],
    queryFn: () => api.get<TeamMember[]>("/users"),
    staleTime: 60_000,
  });

  const inviteMutation = useMutation({
    mutationFn: (attrs: typeof inviteForm) => api.post<TeamMember>("/users/invite", attrs),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["team"] });
      setShowInviteModal(false);
      setInviteForm({ email: "", full_name: "", role: "recruiter", password: "" });
      setInviteError(null);
    },
    onError: (err: Error) => setInviteError(err.message),
  });

  const deactivateMutation = useMutation({
    mutationFn: (userId: string) => api.delete(`/users/${userId}`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["team"] }),
  });

  const updateProfileMutation = useMutation({
    mutationFn: (attrs: { full_name: string; avatar_url: string }) => api.patch("/users/me", attrs),
    onSuccess: () => {
      setProfileSaved(true);
      setTimeout(() => setProfileSaved(false), 3000);
    },
  });

  const handleInviteChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
      setInviteForm((prev) => ({ ...prev, [e.target.name]: e.target.value }));
    },
    [],
  );

  const handleInviteSubmit = useCallback(
    (e: React.FormEvent) => {
      e.preventDefault();
      if (!inviteForm.email || !inviteForm.password) {
        setInviteError("Email and password are required.");
        return;
      }
      inviteMutation.mutate(inviteForm);
    },
    [inviteForm, inviteMutation],
  );

  const isAdmin = user?.role === "admin";

  return (
    <AppLayout>
      <div className="p-6 max-w-5xl mx-auto">
        <h1 className="text-2xl font-semibold text-gray-900 mb-6">Settings</h1>

        {/* Tab navigation */}
        <div className="flex gap-1 border-b border-gray-200 mb-6">
          {(["team", "profile", "company"] as SettingsTab[]).map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`px-4 py-2 text-sm font-medium capitalize rounded-t-lg transition-colors ${
                activeTab === tab
                  ? "text-indigo-700 border-b-2 border-indigo-600 bg-indigo-50"
                  : "text-gray-500 hover:text-gray-700"
              }`}
            >
              {tab}
            </button>
          ))}
        </div>

        {/* Team tab */}
        {activeTab === "team" && (
          <div>
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-medium text-gray-800">Team Members</h2>
              {isAdmin && (
                <button
                  onClick={() => setShowInviteModal(true)}
                  className="px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-lg hover:bg-indigo-700 transition-colors"
                >
                  Invite Member
                </button>
              )}
            </div>

            {teamLoading && <p className="text-sm text-gray-400">Loading team...</p>}

            {teamData && (
              <div className="bg-white border border-gray-200 rounded-xl overflow-hidden">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-gray-100 bg-gray-50">
                      <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Name</th>
                      <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Email</th>
                      <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Role</th>
                      <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Joined</th>
                      {isAdmin && <th className="px-4 py-3"></th>}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-50">
                    {teamData.map((member) => (
                      <tr key={member.id} className="hover:bg-gray-50 transition-colors">
                        <td className="px-4 py-3 font-medium text-gray-900">
                          {member.full_name}
                          {member.id === user?.id && (
                            <span className="ml-2 text-xs text-gray-400">(you)</span>
                          )}
                        </td>
                        <td className="px-4 py-3 text-gray-500">{member.email}</td>
                        <td className="px-4 py-3">
                          <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-medium ${ROLE_COLORS[member.role] ?? "bg-gray-100 text-gray-600"}`}>
                            {ROLE_LABELS[member.role] ?? member.role}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-gray-400 text-xs">
                          {new Date(member.inserted_at).toLocaleDateString()}
                        </td>
                        {isAdmin && (
                          <td className="px-4 py-3 text-right">
                            {member.id !== user?.id && (
                              <button
                                onClick={() => {
                                  if (confirm(`Deactivate ${member.full_name}?`)) {
                                    deactivateMutation.mutate(member.id);
                                  }
                                }}
                                className="text-xs text-red-500 hover:text-red-700"
                              >
                                Deactivate
                              </button>
                            )}
                          </td>
                        )}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}

        {/* Profile tab */}
        {activeTab === "profile" && (
          <div className="max-w-md">
            <h2 className="text-lg font-medium text-gray-800 mb-4">Your Profile</h2>
            <form
              onSubmit={(e) => {
                e.preventDefault();
                updateProfileMutation.mutate(profileForm);
              }}
              className="space-y-4"
            >
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Full Name</label>
                <input
                  value={profileForm.full_name}
                  onChange={(e) => setProfileForm((p) => ({ ...p, full_name: e.target.value }))}
                  className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Avatar URL</label>
                <input
                  value={profileForm.avatar_url}
                  onChange={(e) => setProfileForm((p) => ({ ...p, avatar_url: e.target.value }))}
                  className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300"
                  placeholder="https://..."
                />
              </div>
              <div className="flex items-center gap-3">
                <button
                  type="submit"
                  disabled={updateProfileMutation.isPending}
                  className="px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-lg hover:bg-indigo-700 disabled:opacity-50 transition-colors"
                >
                  {updateProfileMutation.isPending ? "Saving..." : "Save Changes"}
                </button>
                {profileSaved && <span className="text-sm text-green-600">Saved!</span>}
              </div>
            </form>
          </div>
        )}

        {/* Company tab — read-only for non-admins */}
        {activeTab === "company" && (
          <div>
            <h2 className="text-lg font-medium text-gray-800 mb-4">Company Settings</h2>
            <p className="text-sm text-gray-500">
              Company name and slug settings are managed by administrators.
              Contact your account admin to make changes.
            </p>
          </div>
        )}
      </div>

      {/* Invite modal */}
      {showInviteModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="bg-white rounded-xl shadow-xl w-full max-w-md mx-4 p-6">
            <h2 className="text-lg font-semibold text-gray-900 mb-4">Invite Team Member</h2>

            {inviteError && (
              <div className="mb-4 bg-red-50 border border-red-200 rounded-lg px-4 py-2 text-sm text-red-700">
                {inviteError}
              </div>
            )}

            <form onSubmit={handleInviteSubmit} className="space-y-3">
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Full Name</label>
                <input
                  name="full_name"
                  value={inviteForm.full_name}
                  onChange={handleInviteChange}
                  className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300"
                  placeholder="Jane Doe"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Email *</label>
                <input
                  name="email"
                  type="email"
                  value={inviteForm.email}
                  onChange={handleInviteChange}
                  className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300"
                  placeholder="jane@company.com"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Temporary Password *</label>
                <input
                  name="password"
                  type="password"
                  value={inviteForm.password}
                  onChange={handleInviteChange}
                  className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300"
                  placeholder="Min. 12 characters"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Role</label>
                <select
                  name="role"
                  value={inviteForm.role}
                  onChange={handleInviteChange}
                  className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300"
                >
                  <option value="recruiter">Recruiter</option>
                  <option value="interviewer">Interviewer</option>
                  <option value="admin">Admin</option>
                </select>
              </div>

              <div className="flex justify-end gap-3 pt-2">
                <button
                  type="button"
                  onClick={() => setShowInviteModal(false)}
                  className="px-4 py-2 text-sm text-gray-600 hover:text-gray-800"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={inviteMutation.isPending}
                  className="px-4 py-2 bg-indigo-600 text-white rounded-lg text-sm font-medium hover:bg-indigo-700 disabled:opacity-50 transition-colors"
                >
                  {inviteMutation.isPending ? "Sending..." : "Send Invite"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </AppLayout>
  );
}
