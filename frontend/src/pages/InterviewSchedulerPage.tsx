import { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { apiClient } from '../api/client';

interface Interviewer {
  id: string;
  full_name: string;
  email: string;
  role: string;
}

interface ScheduleFormState {
  title: string;
  interview_type: string;
  interviewer_id: string;
  scheduled_at: string;
  duration_minutes: number;
  notes: string;
}

const INITIAL_FORM: ScheduleFormState = {
  title: '',
  interview_type: 'video',
  interviewer_id: '',
  scheduled_at: '',
  duration_minutes: 60,
  notes: '',
};

const INTERVIEW_TYPES = [
  { value: 'video', label: 'Video Interview' },
  { value: 'phone', label: 'Phone Screen' },
  { value: 'technical', label: 'Technical Assessment' },
  { value: 'onsite', label: 'On-site Interview' },
  { value: 'panel', label: 'Panel Interview' },
];

const DURATION_OPTIONS = [15, 30, 45, 60, 90, 120];

export default function InterviewSchedulerPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const applicationId = searchParams.get('application_id');

  const [form, setForm] = useState<ScheduleFormState>(INITIAL_FORM);
  const [interviewers, setInterviewers] = useState<Interviewer[]>([]);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errors, setErrors] = useState<Partial<Record<keyof ScheduleFormState | 'general', string>>>({});
  const [conflictWarning, setConflictWarning] = useState<string | null>(null);

  useEffect(() => {
    apiClient.get<{ data: Interviewer[] }>('/users?role=interviewer,admin').then((r) => {
      setInterviewers(r.data.data || []);
    });
  }, []);

  const handleChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>,
  ) => {
    const { name, value } = e.target;
    setForm((prev) => ({
      ...prev,
      [name]: name === 'duration_minutes' ? Number(value) : value,
    }));
    setErrors((prev) => ({ ...prev, [name]: undefined }));
    setConflictWarning(null);
  };

  const validate = (): boolean => {
    const next: typeof errors = {};
    if (!form.title.trim()) next.title = 'Title is required';
    if (!form.interviewer_id) next.interviewer_id = 'Select an interviewer';
    if (!form.scheduled_at) next.scheduled_at = 'Schedule date and time are required';
    else if (new Date(form.scheduled_at) <= new Date())
      next.scheduled_at = 'Must be scheduled in the future';
    setErrors(next);
    return Object.keys(next).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validate()) return;
    setIsSubmitting(true);
    try {
      const payload = {
        ...form,
        application_id: applicationId,
        scheduled_at: new Date(form.scheduled_at).toISOString(),
      };
      await apiClient.post('/interviews', payload);
      navigate(applicationId ? `/applications/${applicationId}` : '/interviews');
    } catch (err: unknown) {
      const anyErr = err as { response?: { data?: { error?: string } } };
      const msg = anyErr?.response?.data?.error ?? 'Failed to schedule interview';
      if (msg.toLowerCase().includes('conflict')) {
        setConflictWarning(msg);
      } else {
        setErrors({ general: msg });
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="mx-auto max-w-2xl p-6">
      <h1 className="mb-6 text-2xl font-bold text-gray-900">Schedule Interview</h1>

      {errors.general && (
        <div className="mb-4 rounded-md bg-red-50 p-4 text-sm text-red-700">{errors.general}</div>
      )}

      {conflictWarning && (
        <div className="mb-4 rounded-md bg-amber-50 p-4 text-sm text-amber-800">
          <strong>Scheduling conflict:</strong> {conflictWarning}
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-5 rounded-xl border border-gray-200 bg-white p-6">
        <div>
          <label className="block text-sm font-medium text-gray-700">Title</label>
          <input
            name="title"
            type="text"
            value={form.title}
            onChange={handleChange}
            placeholder="e.g. Technical Round 1"
            className="mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
          />
          {errors.title && <p className="mt-1 text-xs text-red-600">{errors.title}</p>}
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700">Interview Type</label>
            <select
              name="interview_type"
              value={form.interview_type}
              onChange={handleChange}
              className="mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
            >
              {INTERVIEW_TYPES.map((t) => (
                <option key={t.value} value={t.value}>
                  {t.label}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700">Duration (minutes)</label>
            <select
              name="duration_minutes"
              value={form.duration_minutes}
              onChange={handleChange}
              className="mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
            >
              {DURATION_OPTIONS.map((d) => (
                <option key={d} value={d}>
                  {d} min
                </option>
              ))}
            </select>
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">Interviewer</label>
          <select
            name="interviewer_id"
            value={form.interviewer_id}
            onChange={handleChange}
            className="mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
          >
            <option value="">Select interviewer…</option>
            {interviewers.map((u) => (
              <option key={u.id} value={u.id}>
                {u.full_name} ({u.role})
              </option>
            ))}
          </select>
          {errors.interviewer_id && (
            <p className="mt-1 text-xs text-red-600">{errors.interviewer_id}</p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">Date and Time</label>
          <input
            name="scheduled_at"
            type="datetime-local"
            value={form.scheduled_at}
            onChange={handleChange}
            className="mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
          />
          {errors.scheduled_at && (
            <p className="mt-1 text-xs text-red-600">{errors.scheduled_at}</p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">Notes (optional)</label>
          <textarea
            name="notes"
            value={form.notes}
            onChange={handleChange}
            rows={3}
            placeholder="Preparation notes for the interviewer…"
            className="mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
          />
        </div>

        <div className="flex justify-end gap-3">
          <button
            type="button"
            onClick={() => navigate(-1)}
            className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={isSubmitting}
            className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-semibold text-white hover:bg-indigo-700 disabled:opacity-50"
          >
            {isSubmitting ? 'Scheduling…' : 'Schedule Interview'}
          </button>
        </div>
      </form>
    </div>
  );
}
