import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../hooks/useAuthContext';

interface FormState {
  full_name: string;
  email: string;
  company_name: string;
  password: string;
  password_confirmation: string;
}

const INITIAL: FormState = {
  full_name: '',
  email: '',
  company_name: '',
  password: '',
  password_confirmation: '',
};

export default function RegisterPage() {
  const { register } = useAuth();
  const navigate = useNavigate();
  const [form, setForm] = useState<FormState>(INITIAL);
  const [errors, setErrors] = useState<Partial<Record<keyof FormState | 'general', string>>>({});
  const [isSubmitting, setIsSubmitting] = useState(false);

  const validate = (): boolean => {
    const next: typeof errors = {};
    if (!form.full_name.trim()) next.full_name = 'Full name is required';
    if (!form.email.includes('@')) next.email = 'Enter a valid email address';
    if (!form.company_name.trim()) next.company_name = 'Company name is required';
    if (form.password.length < 12) next.password = 'Password must be at least 12 characters';
    if (form.password !== form.password_confirmation)
      next.password_confirmation = 'Passwords do not match';
    setErrors(next);
    return Object.keys(next).length === 0;
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setForm((prev) => ({ ...prev, [name]: value }));
    setErrors((prev) => ({ ...prev, [name]: undefined }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validate()) return;
    setIsSubmitting(true);
    try {
      await register(form);
      navigate('/dashboard');
    } catch (err: unknown) {
      const message =
        err instanceof Error ? err.message : 'Registration failed. Please try again.';
      setErrors({ general: message });
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-md space-y-8 rounded-2xl bg-white p-8 shadow-lg">
        <div className="text-center">
          <h1 className="text-3xl font-bold text-gray-900">Create your workspace</h1>
          <p className="mt-2 text-sm text-gray-500">
            Already have an account?{' '}
            <Link to="/login" className="font-medium text-indigo-600 hover:text-indigo-500">
              Sign in
            </Link>
          </p>
        </div>

        {errors.general && (
          <div className="rounded-md bg-red-50 p-4 text-sm text-red-700">{errors.general}</div>
        )}

        <form onSubmit={handleSubmit} className="space-y-5" noValidate>
          {(
            [
              { name: 'full_name', label: 'Full name', type: 'text', autoComplete: 'name' },
              { name: 'email', label: 'Work email', type: 'email', autoComplete: 'email' },
              {
                name: 'company_name',
                label: 'Company name',
                type: 'text',
                autoComplete: 'organization',
              },
              {
                name: 'password',
                label: 'Password',
                type: 'password',
                autoComplete: 'new-password',
              },
              {
                name: 'password_confirmation',
                label: 'Confirm password',
                type: 'password',
                autoComplete: 'new-password',
              },
            ] as const
          ).map(({ name, label, type, autoComplete }) => (
            <div key={name}>
              <label className="block text-sm font-medium text-gray-700" htmlFor={name}>
                {label}
              </label>
              <input
                id={name}
                name={name}
                type={type}
                autoComplete={autoComplete}
                value={form[name]}
                onChange={handleChange}
                className={`mt-1 block w-full rounded-lg border px-3 py-2 text-sm shadow-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 ${
                  errors[name] ? 'border-red-400' : 'border-gray-300'
                }`}
              />
              {errors[name] && (
                <p className="mt-1 text-xs text-red-600">{errors[name]}</p>
              )}
            </div>
          ))}

          <button
            type="submit"
            disabled={isSubmitting}
            className="w-full rounded-lg bg-indigo-600 px-4 py-2 text-sm font-semibold text-white shadow hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:opacity-50"
          >
            {isSubmitting ? 'Creating account…' : 'Create account'}
          </button>
        </form>

        <p className="text-center text-xs text-gray-400">
          By creating an account you agree to our Terms of Service and Privacy Policy.
        </p>
      </div>
    </div>
  );
}
