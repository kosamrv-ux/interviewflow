import { useState, useEffect } from 'react';
import { apiClient } from '../api/client';

interface CompanySummary {
  total_applications: number;
  active_applications: number;
  hired_this_month: number;
}

interface FunnelData {
  stages: Record<string, number>;
  rejection_count: number;
  conversion_rate: number;
  offer_acceptance_rate: number;
}

interface Job {
  id: string;
  title: string;
  department: string;
}

interface RankedCandidate {
  application_id: string;
  candidate_name: string;
  stage: string;
  composite_score: number | null;
  rank: number | null;
}

function KpiCard({ label, value, sub }: { label: string; value: string | number; sub?: string }) {
  return (
    <div className="rounded-xl border border-gray-200 bg-white p-5">
      <p className="text-sm font-medium text-gray-500">{label}</p>
      <p className="mt-1 text-3xl font-bold text-gray-900">{value}</p>
      {sub && <p className="mt-1 text-xs text-gray-400">{sub}</p>}
    </div>
  );
}

const STAGE_ORDER = [
  'applied',
  'screening',
  'phone_screen',
  'technical',
  'onsite',
  'offer',
  'hired',
];

export default function AnalyticsPage() {
  const [summary, setSummary] = useState<CompanySummary | null>(null);
  const [jobs, setJobs] = useState<Job[]>([]);
  const [selectedJobId, setSelectedJobId] = useState<string>('');
  const [funnel, setFunnel] = useState<FunnelData | null>(null);
  const [rankings, setRankings] = useState<RankedCandidate[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    Promise.all([
      apiClient.get<CompanySummary>('/analytics/summary'),
      apiClient.get<{ data: Job[] }>('/jobs'),
    ]).then(([summaryRes, jobsRes]) => {
      setSummary(summaryRes.data);
      const jobList = jobsRes.data.data || [];
      setJobs(jobList);
      if (jobList.length > 0) setSelectedJobId(jobList[0].id);
      setIsLoading(false);
    });
  }, []);

  useEffect(() => {
    if (!selectedJobId) return;
    Promise.all([
      apiClient.get<FunnelData>(`/analytics/jobs/${selectedJobId}/funnel`),
      apiClient.get<RankedCandidate[]>(`/analytics/jobs/${selectedJobId}/rankings`),
    ]).then(([funnelRes, rankingsRes]) => {
      setFunnel(funnelRes.data);
      setRankings(rankingsRes.data);
    });
  }, [selectedJobId]);

  if (isLoading) {
    return (
      <div className="flex h-64 items-center justify-center">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-indigo-500 border-t-transparent" />
      </div>
    );
  }

  const topOfFunnel = funnel?.stages?.applied ?? 0;

  return (
    <div className="space-y-6 p-6">
      <h1 className="text-2xl font-bold text-gray-900">Hiring Analytics</h1>

      {/* Company KPIs */}
      {summary && (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <KpiCard label="Total Applications" value={summary.total_applications} />
          <KpiCard
            label="Active in Pipeline"
            value={summary.active_applications}
            sub="Excluding hired and rejected"
          />
          <KpiCard label="Hired This Month" value={summary.hired_this_month} />
        </div>
      )}

      {/* Job selector */}
      <div className="flex items-center gap-3">
        <label className="text-sm font-medium text-gray-700">Job</label>
        <select
          value={selectedJobId}
          onChange={(e) => setSelectedJobId(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
        >
          {jobs.map((j) => (
            <option key={j.id} value={j.id}>
              {j.title} – {j.department}
            </option>
          ))}
        </select>
      </div>

      {funnel && (
        <div className="rounded-xl border border-gray-200 bg-white p-6">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="text-lg font-semibold text-gray-800">Hiring Funnel</h2>
            <div className="flex gap-6 text-sm">
              <span className="text-gray-500">
                Conversion:{' '}
                <strong className="text-indigo-600">
                  {(funnel.conversion_rate * 100).toFixed(1)}%
                </strong>
              </span>
              <span className="text-gray-500">
                Offer accept:{' '}
                <strong className="text-emerald-600">
                  {(funnel.offer_acceptance_rate * 100).toFixed(1)}%
                </strong>
              </span>
            </div>
          </div>
          <div className="space-y-3">
            {STAGE_ORDER.map((stage) => {
              const count = funnel.stages[stage] ?? 0;
              const pct = topOfFunnel > 0 ? (count / topOfFunnel) * 100 : 0;
              return (
                <div key={stage} className="flex items-center gap-4">
                  <div className="w-28 text-right text-sm capitalize text-gray-500">
                    {stage.replace('_', ' ')}
                  </div>
                  <div className="flex-1">
                    <div className="h-6 rounded-md bg-gray-100">
                      <div
                        className="h-6 rounded-md bg-indigo-500 transition-all"
                        style={{ width: `${Math.max(pct, 1)}%` }}
                      />
                    </div>
                  </div>
                  <div className="w-12 text-sm font-semibold text-gray-700">{count}</div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Rankings */}
      {rankings.length > 0 && (
        <div className="rounded-xl border border-gray-200 bg-white p-6">
          <h2 className="mb-4 text-lg font-semibold text-gray-800">Candidate Rankings</h2>
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-200 text-left text-xs font-semibold uppercase tracking-wide text-gray-400">
                <th className="pb-3">Rank</th>
                <th className="pb-3">Candidate</th>
                <th className="pb-3">Stage</th>
                <th className="pb-3 text-right">AI Score</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {rankings.map((r) => (
                <tr key={r.application_id}>
                  <td className="py-3 font-bold text-indigo-600">#{r.rank ?? '—'}</td>
                  <td className="py-3 font-medium text-gray-800">{r.candidate_name}</td>
                  <td className="py-3 capitalize text-gray-500">{r.stage.replace('_', ' ')}</td>
                  <td className="py-3 text-right font-semibold text-gray-700">
                    {r.composite_score != null
                      ? `${Math.round(r.composite_score * 100)}`
                      : <span className="text-gray-400">—</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
