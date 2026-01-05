import { apiClient } from './client';

export interface LoginRequest {
  email: string;
  password: string;
}

export interface RegisterRequest {
  email: string;
  password: string;
  password_confirmation: string;
  full_name: string;
  company_name?: string;
}

export interface TokenResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  token_type: string;
  user: {
    id: string;
    email: string;
    full_name: string;
    role: string;
    company_id: string;
    avatar_url: string | null;
  };
}

export interface RefreshRequest {
  refresh_token: string;
}

/** POST /api/v1/auth/login */
export async function login(data: LoginRequest): Promise<TokenResponse> {
  const res = await apiClient.post<TokenResponse>('/auth/login', data);
  return res.data;
}

/** POST /api/v1/auth/register */
export async function register(data: RegisterRequest): Promise<TokenResponse> {
  const res = await apiClient.post<TokenResponse>('/auth/register', data);
  return res.data;
}

/** POST /api/v1/auth/refresh */
export async function refreshTokens(refresh_token: string): Promise<TokenResponse> {
  const res = await apiClient.post<TokenResponse>('/auth/refresh', { refresh_token });
  return res.data;
}

/** DELETE /api/v1/auth/logout */
export async function logout(): Promise<void> {
  await apiClient.delete('/auth/logout');
}

/** Returns stored access token from localStorage */
export function getStoredAccessToken(): string | null {
  return localStorage.getItem('if_access_token');
}

/** Returns stored refresh token from localStorage */
export function getStoredRefreshToken(): string | null {
  return localStorage.getItem('if_refresh_token');
}

export function storeTokens(access: string, refresh: string): void {
  localStorage.setItem('if_access_token', access);
  localStorage.setItem('if_refresh_token', refresh);
}

export function clearTokens(): void {
  localStorage.removeItem('if_access_token');
  localStorage.removeItem('if_refresh_token');
}
