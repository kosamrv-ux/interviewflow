/**
 * Typed API client for InterviewFlow.
 * Uses Axios with request/response interceptors for:
 * - Automatic Bearer token attachment
 * - 401 → token refresh → retry flow
 * - Structured error normalization
 */

import axios, {
  type AxiosInstance,
  type AxiosRequestConfig,
  type AxiosResponse,
  type InternalAxiosRequestConfig,
} from "axios";

// ─── Types ────────────────────────────────────────────────────────────────────

export interface ApiError {
  message: string;
  code: string;
  field?: string;
}

export interface ApiErrorResponse {
  errors: ApiError[];
  retry_after?: number;
}

export interface PaginationMeta {
  total?: number;
  limit: number;
  has_more: boolean;
  next_cursor?: string | null;
}

export interface PaginatedResponse<T> {
  data: T[];
  meta: PaginationMeta;
}

export interface TokenPair {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  token_type: string;
}

export interface User {
  id: string;
  email: string;
  full_name: string;
  role: "admin" | "recruiter" | "interviewer" | "stakeholder";
  company_id: string;
  avatar_url: string | null;
  confirmed_at: string | null;
  inserted_at: string;
}

export interface AuthResponse extends TokenPair {
  user: User;
}

export interface Job {
  id: string;
  title: string;
  department: string | null;
  location: string | null;
  remote_policy: "onsite" | "hybrid" | "remote";
  employment_type: "full_time" | "part_time" | "contract" | "internship";
  description: string | null;
  requirements: string | null;
  salary_min: number | null;
  salary_max: number | null;
  salary_currency: string;
  pipeline_stages: string[];
  status: "draft" | "open" | "paused" | "closed" | "archived";
  company_id: string;
  created_by_id: string;
  published_at: string | null;
  closed_at: string | null;
  inserted_at: string;
  updated_at: string;
  stage_counts?: Record<string, number>;
}

export interface Candidate {
  id: string;
  email: string;
  full_name: string;
  phone: string | null;
  linkedin_url: string | null;
  github_url: string | null;
  portfolio_url: string | null;
  resume_url: string | null;
  source: string | null;
  tags: string[];
  notes: string | null;
  inserted_at: string;
}

export interface Application {
  id: string;
  job_id: string;
  candidate_id: string;
  assigned_to_id: string | null;
  pipeline_stage: string;
  status: "active" | "rejected" | "withdrawn" | "hired";
  rejection_reason: string | null;
  composite_score: number | null;
  rank_within_job: number | null;
  applied_at: string;
  stage_changed_at: string;
  inserted_at: string;
  candidate?: Candidate;
  job?: Pick<Job, "id" | "title" | "pipeline_stages">;
}

export interface AiScore {
  id: string;
  composite_score: number;
  breakdown: Record<
    string,
    { score: number; weight: number; rationale: string }
  >;
  strengths: string[];
  areas_for_growth: string[];
  recommended_action: "advance" | "reject" | "hold";
  confidence: number;
  status: "completed" | "overridden" | "failed";
  inserted_at: string;
}

export interface VideoSession {
  id: string;
  interview_id: string;
  session_token: string;
  status: "waiting" | "active" | "ended" | "failed";
  started_at: string | null;
  ended_at: string | null;
  duration_seconds: number | null;
  recording_url: string | null;
}

export interface IceServer {
  urls: string | string[];
  username?: string;
  credential?: string;
}

// ─── Client factory ──────────────────────────────────────────────────────────

const TOKEN_STORAGE_KEY = "if_access_token";
const REFRESH_STORAGE_KEY = "if_refresh_token";

class ApiClient {
  private readonly client: AxiosInstance;
  private isRefreshing = false;
  private refreshSubscribers: Array<(token: string) => void> = [];

  constructor(baseURL: string) {
    this.client = axios.create({
      baseURL,
      timeout: 15_000,
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
    });

    this.client.interceptors.request.use(this.attachToken);
    this.client.interceptors.response.use(
      (response) => response,
      this.handleResponseError.bind(this),
    );
  }

  private attachToken = (
    config: InternalAxiosRequestConfig,
  ): InternalAxiosRequestConfig => {
    const token = localStorage.getItem(TOKEN_STORAGE_KEY);
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  };

  private handleResponseError = async (error: unknown): Promise<unknown> => {
    if (!axios.isAxiosError(error) || !error.response) {
      return Promise.reject(error);
    }

    const { status, config: originalConfig } = error.response;

    // 401: Try to refresh the token once, then retry the original request
    if (status === 401 && originalConfig && !originalConfig._retry) {
      if (this.isRefreshing) {
        // Queue this request until the refresh resolves
        return new Promise<unknown>((resolve) => {
          this.refreshSubscribers.push((newToken) => {
            if (originalConfig.headers) {
              originalConfig.headers.Authorization = `Bearer ${newToken}`;
            }
            resolve(this.client(originalConfig));
          });
        });
      }

      originalConfig._retry = true;
      this.isRefreshing = true;

      try {
        const refreshToken = localStorage.getItem(REFRESH_STORAGE_KEY);
        if (!refreshToken) throw new Error("No refresh token");

        const response = await axios.post<TokenPair>(
          `${this.client.defaults.baseURL}/auth/refresh`,
          { refresh_token: refreshToken },
        );

        const { access_token, refresh_token } = response.data;
        localStorage.setItem(TOKEN_STORAGE_KEY, access_token);
        localStorage.setItem(REFRESH_STORAGE_KEY, refresh_token);

        // Drain the subscriber queue
        this.refreshSubscribers.forEach((cb) => cb(access_token));
        this.refreshSubscribers = [];

        if (originalConfig.headers) {
          originalConfig.headers.Authorization = `Bearer ${access_token}`;
        }

        return this.client(originalConfig);
      } catch {
        // Refresh failed — clear tokens and redirect to login
        localStorage.removeItem(TOKEN_STORAGE_KEY);
        localStorage.removeItem(REFRESH_STORAGE_KEY);
        window.location.href = "/login";
        return Promise.reject(error);
      } finally {
        this.isRefreshing = false;
      }
    }

    // Normalize error shape
    const apiError = new Error("API request failed") as Error & {
      status: number;
      errors: ApiError[];
      retry_after?: number;
    };
    apiError.status = status;
    apiError.errors = error.response.data?.errors ?? [
      { message: "An unexpected error occurred", code: "server_error" },
    ];
    apiError.retry_after = error.response.data?.retry_after;

    return Promise.reject(apiError);
  };

  // ─── Auth ────────────────────────────────────────────────────────────────

  async login(email: string, password: string): Promise<AuthResponse> {
    const res = await this.client.post<AuthResponse>("/auth/login", {
      email,
      password,
    });
    this.storeTokens(res.data);
    return res.data;
  }

  async register(params: {
    name: string;
    email: string;
    password: string;
    password_confirmation: string;
    full_name: string;
  }): Promise<AuthResponse> {
    const slug = params.name
      .toLowerCase()
      .replace(/[^a-z0-9\s-]/g, "")
      .replace(/\s+/g, "-");
    const res = await this.client.post<AuthResponse>("/auth/register", {
      ...params,
      slug,
    });
    this.storeTokens(res.data);
    return res.data;
  }

  async logout(): Promise<void> {
    await this.client.delete("/auth/logout").catch(() => {});
    this.clearTokens();
  }

  private storeTokens(data: TokenPair): void {
    localStorage.setItem(TOKEN_STORAGE_KEY, data.access_token);
    localStorage.setItem(REFRESH_STORAGE_KEY, data.refresh_token);
  }

  private clearTokens(): void {
    localStorage.removeItem(TOKEN_STORAGE_KEY);
    localStorage.removeItem(REFRESH_STORAGE_KEY);
  }

  // ─── Jobs ────────────────────────────────────────────────────────────────

  async listJobs(params?: {
    status?: string;
    search?: string;
    after?: string;
    limit?: number;
  }): Promise<PaginatedResponse<Job>> {
    const res = await this.client.get<PaginatedResponse<Job>>("/jobs", {
      params,
    });
    return res.data;
  }

  async getJob(jobId: string): Promise<Job> {
    const res = await this.client.get<Job>(`/jobs/${jobId}`);
    return res.data;
  }

  async createJob(data: Partial<Job>): Promise<Job> {
    const res = await this.client.post<Job>("/jobs", data);
    return res.data;
  }

  async updateJob(jobId: string, data: Partial<Job>): Promise<Job> {
    const res = await this.client.patch<Job>(`/jobs/${jobId}`, data);
    return res.data;
  }

  async publishJob(jobId: string): Promise<Job> {
    const res = await this.client.post<Job>(`/jobs/${jobId}/publish`);
    return res.data;
  }

  // ─── Applications ────────────────────────────────────────────────────────

  async listApplications(params?: {
    job_id?: string;
    stage?: string;
    status?: string;
    limit?: number;
  }): Promise<PaginatedResponse<Application>> {
    const res = await this.client.get<PaginatedResponse<Application>>(
      "/applications",
      { params },
    );
    return res.data;
  }

  async getApplication(applicationId: string): Promise<Application> {
    const res = await this.client.get<Application>(
      `/applications/${applicationId}`,
    );
    return res.data;
  }

  async advanceApplication(
    applicationId: string,
    stage: string,
  ): Promise<Application> {
    const res = await this.client.post<Application>(
      `/applications/${applicationId}/advance`,
      { stage },
    );
    return res.data;
  }

  async rejectApplication(
    applicationId: string,
    reason: string,
  ): Promise<Application> {
    const res = await this.client.post<Application>(
      `/applications/${applicationId}/reject`,
      { reason },
    );
    return res.data;
  }

  // ─── Video Sessions ──────────────────────────────────────────────────────

  async createSession(interviewId: string): Promise<VideoSession> {
    const res = await this.client.post<VideoSession>(
      `/interviews/${interviewId}/sessions`,
    );
    return res.data;
  }

  async getIceServers(
    sessionId: string,
  ): Promise<{ ice_servers: IceServer[] }> {
    const res = await this.client.get<{ ice_servers: IceServer[] }>(
      `/sessions/${sessionId}/ice-servers`,
    );
    return res.data;
  }

  async endSession(sessionId: string): Promise<VideoSession> {
    const res = await this.client.post<VideoSession>(
      `/sessions/${sessionId}/end`,
    );
    return res.data;
  }

  // ─── Raw request escape hatch ────────────────────────────────────────────

  async get<T>(path: string, config?: AxiosRequestConfig): Promise<T> {
    const res: AxiosResponse<T> = await this.client.get(path, config);
    return res.data;
  }

  async post<T>(
    path: string,
    data?: unknown,
    config?: AxiosRequestConfig,
  ): Promise<T> {
    const res: AxiosResponse<T> = await this.client.post(path, data, config);
    return res.data;
  }
}

const apiBaseUrl =
  (import.meta.env.VITE_API_URL as string | undefined) ||
  "http://localhost:4000";

export const api = new ApiClient(`${apiBaseUrl}/api/v1`);
export default api;

// Re-export storage keys for use in auth store
export { TOKEN_STORAGE_KEY, REFRESH_STORAGE_KEY };
