import React, { useState, useEffect } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "../api/client";

interface Organization {
  id: string;
  name: string;
  slug: string;
  plan: string;
  sso_enabled: boolean;
  sso_provider: string | null;
  max_seats: number;
  settings: Record<string, unknown>;
}

interface OrgMember {
  id: string;
  email: string;
  name: string;
  role: string;
  inserted_at: string;
}

export function OrganizationSettingsPage() {
  const queryClient = useQueryClient();
  const [activeTab, setActiveTab] = useState<"general" | "sso" | "members" | "danger">("general");

  const { data: org, isLoading } = useQuery<Organization>({
    queryKey: ["organization"],
    queryFn: () => api.get("/api/v1/organization").then((r) => r.data),
  });

  const { data: members } = useQuery<OrgMember[]>({
    queryKey: ["organization", "members"],
    queryFn: () => api.get("/api/v1/organization/members").then((r) => r.data),
    enabled: activeTab === "members",
  });

  const updateOrg = useMutation({
    mutationFn: (updates: Partial<Organization>) =>
      api.put("/api/v1/organization", { organization: updates }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["organization"] });
    },
  });

  const removeMember = useMutation({
    mutationFn: (userId: string) => api.delete(`/api/v1/organization/members/${userId}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["organization", "members"] });
    },
  });

  if (isLoading) {
    return <div className="p-8 text-gray-500">Loading organization settings...</div>;
  }

  if (!org) return null;

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Organization Settings</h1>

      <div className="flex gap-1 mb-6 border-b border-gray-200">
        {(["general", "sso", "members", "danger"] as const).map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-4 py-2 text-sm font-medium capitalize rounded-t-md transition-colors ${
              activeTab === tab
                ? "bg-white border border-b-white border-gray-200 text-indigo-600 -mb-px"
                : "text-gray-500 hover:text-gray-700"
            }`}
          >
            {tab === "sso" ? "SSO" : tab}
          </button>
        ))}
      </div>

      {activeTab === "general" && (
        <GeneralTab org={org} onSave={(updates) => updateOrg.mutate(updates)} saving={updateOrg.isPending} />
      )}

      {activeTab === "sso" && (
        <SSOTab org={org} onSave={(updates) => updateOrg.mutate(updates)} saving={updateOrg.isPending} />
      )}

      {activeTab === "members" && (
        <MembersTab
          members={members ?? []}
          onRemove={(id) => removeMember.mutate(id)}
          maxSeats={org.max_seats}
          plan={org.plan}
        />
      )}

      {activeTab === "danger" && <DangerTab orgName={org.name} />}
    </div>
  );
}

function GeneralTab({
  org,
  onSave,
  saving,
}: {
  org: Organization;
  onSave: (u: Partial<Organization>) => void;
  saving: boolean;
}) {
  const [name, setName] = useState(org.name);

  return (
    <div className="bg-white rounded-lg border border-gray-200 p-6 space-y-6">
      <div>
        <h2 className="text-lg font-medium text-gray-900 mb-4">General</h2>
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Organization Name</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Slug</label>
            <input
              type="text"
              value={org.slug}
              disabled
              className="w-full rounded-md border border-gray-200 bg-gray-50 px-3 py-2 text-sm text-gray-400"
            />
            <p className="text-xs text-gray-400 mt-1">Slug cannot be changed after creation.</p>
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Plan</label>
            <span className="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-indigo-100 text-indigo-700 capitalize">
              {org.plan}
            </span>
          </div>
        </div>
      </div>
      <div className="flex justify-end">
        <button
          onClick={() => onSave({ name })}
          disabled={saving || name === org.name}
          className="px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700 disabled:opacity-50"
        >
          {saving ? "Saving..." : "Save Changes"}
        </button>
      </div>
    </div>
  );
}

function SSOTab({
  org,
  onSave,
  saving,
}: {
  org: Organization;
  onSave: (u: Partial<Organization>) => void;
  saving: boolean;
}) {
  const [enabled, setEnabled] = useState(org.sso_enabled);
  const [provider, setProvider] = useState(org.sso_provider ?? "okta");

  return (
    <div className="bg-white rounded-lg border border-gray-200 p-6 space-y-6">
      <div>
        <h2 className="text-lg font-medium text-gray-900 mb-1">Single Sign-On (SSO)</h2>
        <p className="text-sm text-gray-500 mb-4">
          Configure SAML/OIDC SSO for your organization. Available on Enterprise plan.
        </p>

        {org.plan !== "enterprise" && (
          <div className="bg-amber-50 border border-amber-200 rounded-md p-4 mb-4">
            <p className="text-sm text-amber-700">
              SSO is available on the Enterprise plan.{" "}
              <a href="mailto:sales@interviewflow.io" className="font-medium underline">
                Contact sales
              </a>{" "}
              to upgrade.
            </p>
          </div>
        )}

        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <input
              type="checkbox"
              id="sso-enabled"
              checked={enabled}
              onChange={(e) => setEnabled(e.target.checked)}
              disabled={org.plan !== "enterprise"}
              className="rounded border-gray-300 text-indigo-600"
            />
            <label htmlFor="sso-enabled" className="text-sm text-gray-700">
              Enable SSO for this organization
            </label>
          </div>

          {enabled && (
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">SSO Provider</label>
              <select
                value={provider}
                onChange={(e) => setProvider(e.target.value)}
                className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm"
              >
                <option value="okta">Okta</option>
                <option value="google_workspace">Google Workspace</option>
                <option value="azure_ad">Azure AD</option>
                <option value="saml_generic">Generic SAML 2.0</option>
              </select>
              <p className="text-xs text-gray-400 mt-2">
                SSO login URL: <code className="bg-gray-100 px-1 rounded">/auth/sso/{org.slug}</code>
              </p>
            </div>
          )}
        </div>
      </div>

      <div className="flex justify-end">
        <button
          onClick={() => onSave({ sso_enabled: enabled, sso_provider: enabled ? provider : null })}
          disabled={saving || org.plan !== "enterprise"}
          className="px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700 disabled:opacity-50"
        >
          {saving ? "Saving..." : "Save SSO Settings"}
        </button>
      </div>
    </div>
  );
}

function MembersTab({
  members,
  onRemove,
  maxSeats,
  plan,
}: {
  members: OrgMember[];
  onRemove: (id: string) => void;
  maxSeats: number;
  plan: string;
}) {
  const roleColors: Record<string, string> = {
    owner: "bg-purple-100 text-purple-700",
    admin: "bg-blue-100 text-blue-700",
    member: "bg-gray-100 text-gray-700",
    viewer: "bg-green-100 text-green-700",
  };

  return (
    <div className="bg-white rounded-lg border border-gray-200">
      <div className="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
        <h2 className="text-lg font-medium text-gray-900">
          Members ({members.length}/{maxSeats} seats)
        </h2>
        <button className="px-3 py-1.5 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700">
          Invite Member
        </button>
      </div>
      <div className="divide-y divide-gray-100">
        {members.map((member) => (
          <div key={member.id} className="px-6 py-4 flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-gray-900">{member.name}</p>
              <p className="text-xs text-gray-500">{member.email}</p>
            </div>
            <div className="flex items-center gap-3">
              <span
                className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium capitalize ${roleColors[member.role] ?? "bg-gray-100 text-gray-700"}`}
              >
                {member.role}
              </span>
              {member.role !== "owner" && (
                <button
                  onClick={() => onRemove(member.id)}
                  className="text-xs text-red-600 hover:text-red-700 font-medium"
                >
                  Remove
                </button>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function DangerTab({ orgName }: { orgName: string }) {
  const [confirm, setConfirm] = useState("");

  return (
    <div className="bg-white rounded-lg border border-red-200 p-6">
      <h2 className="text-lg font-medium text-red-700 mb-4">Danger Zone</h2>
      <div className="border border-red-200 rounded-md p-4">
        <h3 className="text-sm font-medium text-gray-900 mb-1">Delete Organization</h3>
        <p className="text-sm text-gray-500 mb-4">
          Permanently delete <strong>{orgName}</strong> and all associated data. This action cannot be undone.
        </p>
        <input
          type="text"
          placeholder={`Type "${orgName}" to confirm`}
          value={confirm}
          onChange={(e) => setConfirm(e.target.value)}
          className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm mb-3"
        />
        <button
          disabled={confirm !== orgName}
          className="px-4 py-2 bg-red-600 text-white text-sm font-medium rounded-md hover:bg-red-700 disabled:opacity-50"
        >
          Delete Organization
        </button>
      </div>
    </div>
  );
}
