import React, { useState, useMemo } from "react";

export interface RankedCandidate {
  id: string;
  name: string;
  email: string;
  composite_score: number | null;
  rank: number;
  dimensions: Record<string, number>;
  interview_completed_at: string | null;
}

type SortKey = "rank" | "name" | "composite_score";
type SortDir = "asc" | "desc";

interface Props {
  candidates: RankedCandidate[];
  onSelectCandidate?: (id: string) => void;
  selectedId?: string;
}

export function RankingTable({ candidates, onSelectCandidate, selectedId }: Props) {
  const [sortKey, setSortKey] = useState<SortKey>("rank");
  const [sortDir, setSortDir] = useState<SortDir>("asc");

  const sorted = useMemo(() => {
    return [...candidates].sort((a, b) => {
      let result = 0;

      if (sortKey === "rank") {
        // Primary: rank ascending. Tied ranks (same composite_score) sorted by
        // name alphabetically as a stable secondary key. Before this fix,
        // tied candidates were in arbitrary insertion order, causing the table
        // to flicker on re-renders.
        result = a.rank - b.rank;
        if (result === 0) {
          result = a.name.localeCompare(b.name);
        }
      } else if (sortKey === "composite_score") {
        // Null scores sort to the bottom regardless of direction
        if (a.composite_score === null && b.composite_score === null) {
          result = a.name.localeCompare(b.name);
        } else if (a.composite_score === null) {
          return 1;
        } else if (b.composite_score === null) {
          return -1;
        } else {
          result = a.composite_score - b.composite_score;
          // Secondary: name for ties
          if (result === 0) {
            result = a.name.localeCompare(b.name);
          }
        }
      } else if (sortKey === "name") {
        result = a.name.localeCompare(b.name);
      }

      return sortDir === "asc" ? result : -result;
    });
  }, [candidates, sortKey, sortDir]);

  const handleSort = (key: SortKey) => {
    if (sortKey === key) {
      setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setSortKey(key);
      setSortDir(key === "composite_score" ? "desc" : "asc");
    }
  };

  const SortIcon = ({ col }: { col: SortKey }) => {
    if (sortKey !== col) return <span className="text-gray-300 ml-1">↕</span>;
    return <span className="text-indigo-600 ml-1">{sortDir === "asc" ? "↑" : "↓"}</span>;
  };

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full text-sm">
        <thead>
          <tr className="border-b border-gray-200">
            <th
              className="text-left py-3 px-4 font-medium text-gray-500 cursor-pointer select-none hover:text-gray-700"
              onClick={() => handleSort("rank")}
            >
              Rank <SortIcon col="rank" />
            </th>
            <th
              className="text-left py-3 px-4 font-medium text-gray-500 cursor-pointer select-none hover:text-gray-700"
              onClick={() => handleSort("name")}
            >
              Candidate <SortIcon col="name" />
            </th>
            <th
              className="text-left py-3 px-4 font-medium text-gray-500 cursor-pointer select-none hover:text-gray-700"
              onClick={() => handleSort("composite_score")}
            >
              Score <SortIcon col="composite_score" />
            </th>
            <th className="text-left py-3 px-4 font-medium text-gray-500">Dimensions</th>
            <th className="text-left py-3 px-4 font-medium text-gray-500">Interview</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {sorted.map((candidate) => (
            <tr
              key={candidate.id}
              onClick={() => onSelectCandidate?.(candidate.id)}
              className={`hover:bg-gray-50 cursor-pointer transition-colors ${
                selectedId === candidate.id ? "bg-indigo-50" : ""
              }`}
            >
              <td className="py-3 px-4">
                <span
                  className={`inline-flex items-center justify-center w-7 h-7 rounded-full text-xs font-bold ${
                    candidate.rank === 1
                      ? "bg-yellow-100 text-yellow-700"
                      : candidate.rank <= 3
                      ? "bg-gray-100 text-gray-600"
                      : "text-gray-400"
                  }`}
                >
                  {candidate.rank}
                </span>
              </td>
              <td className="py-3 px-4">
                <p className="font-medium text-gray-900">{candidate.name}</p>
                <p className="text-xs text-gray-400">{candidate.email}</p>
              </td>
              <td className="py-3 px-4">
                {candidate.composite_score !== null ? (
                  <div className="flex items-center gap-2">
                    <div className="flex-1 h-2 bg-gray-100 rounded-full w-16 overflow-hidden">
                      <div
                        className={`h-full rounded-full ${scoreColor(candidate.composite_score)}`}
                        style={{ width: `${candidate.composite_score}%` }}
                      />
                    </div>
                    <span className="text-sm font-semibold text-gray-800">
                      {Math.round(candidate.composite_score)}
                    </span>
                  </div>
                ) : (
                  <span className="text-xs text-gray-400">Pending</span>
                )}
              </td>
              <td className="py-3 px-4">
                <div className="flex flex-wrap gap-1">
                  {Object.entries(candidate.dimensions).map(([key, val]) => (
                    <span
                      key={key}
                      title={key}
                      className="inline-flex items-center px-1.5 py-0.5 rounded text-xs bg-gray-100 text-gray-600"
                    >
                      {key.slice(0, 4)} {Math.round(val)}
                    </span>
                  ))}
                </div>
              </td>
              <td className="py-3 px-4 text-xs text-gray-400">
                {candidate.interview_completed_at
                  ? new Date(candidate.interview_completed_at).toLocaleDateString()
                  : "—"}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {sorted.length === 0 && (
        <div className="py-12 text-center text-gray-400 text-sm">No candidates ranked yet.</div>
      )}
    </div>
  );
}

function scoreColor(score: number): string {
  if (score >= 80) return "bg-green-500";
  if (score >= 60) return "bg-blue-500";
  if (score >= 40) return "bg-yellow-400";
  return "bg-red-400";
}
