import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { BrowserRouter } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import LoginPage from "@/pages/LoginPage";

// Mock the API client
vi.mock("@/api/client", () => ({
  default: {
    login: vi.fn(),
    logout: vi.fn(),
  },
  TOKEN_STORAGE_KEY: "if_access_token",
  REFRESH_STORAGE_KEY: "if_refresh_token",
}));

// Mock useAuthStore
vi.mock("@/hooks/useAuthStore", () => ({
  useAuthStore: (selector: (s: { setUser: () => void; isAuthenticated: boolean }) => unknown) =>
    selector({
      setUser: vi.fn(),
      isAuthenticated: false,
    }),
}));

// Mock useNavigate
const mockNavigate = vi.fn();
vi.mock("react-router-dom", async () => {
  const actual = await vi.importActual("react-router-dom");
  return {
    ...actual,
    useNavigate: () => mockNavigate,
  };
});

function renderLoginPage() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });

  return render(
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <LoginPage />
      </BrowserRouter>
    </QueryClientProvider>,
  );
}

describe("LoginPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders the login form with all required fields", () => {
    renderLoginPage();

    expect(
      screen.getByRole("heading", { name: /InterviewFlow/i }),
    ).toBeInTheDocument();
    expect(screen.getByLabelText(/work email/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/password/i)).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /sign in/i }),
    ).toBeInTheDocument();
  });

  it("shows validation error when email is empty", async () => {
    renderLoginPage();
    const user = userEvent.setup();

    await user.click(screen.getByRole("button", { name: /sign in/i }));

    expect(await screen.findByText("Email is required")).toBeInTheDocument();
  });

  it("shows validation error for invalid email format", async () => {
    renderLoginPage();
    const user = userEvent.setup();

    await user.type(screen.getByLabelText(/work email/i), "not-an-email");
    await user.click(screen.getByRole("button", { name: /sign in/i }));

    expect(
      await screen.findByText("Enter a valid email address"),
    ).toBeInTheDocument();
  });

  it("calls api.login with correct credentials on submit", async () => {
    const { default: api } = await import("@/api/client");
    const loginMock = vi.mocked(api.login);
    loginMock.mockResolvedValue({
      user: {
        id: "u1",
        email: "test@example.com",
        full_name: "Test User",
        role: "recruiter",
        company_id: "c1",
        avatar_url: null,
        confirmed_at: null,
        inserted_at: "2025-11-01T00:00:00Z",
      },
      access_token: "token123",
      refresh_token: "refresh123",
      expires_in: 3600,
      token_type: "Bearer",
    });

    renderLoginPage();
    const user = userEvent.setup();

    await user.type(screen.getByLabelText(/work email/i), "test@example.com");
    await user.type(screen.getByLabelText(/password/i), "Password123!");
    await user.click(screen.getByRole("button", { name: /sign in/i }));

    await waitFor(() => {
      expect(loginMock).toHaveBeenCalledWith("test@example.com", "Password123!");
    });
  });

  it("shows error message on invalid credentials", async () => {
    const { default: api } = await import("@/api/client");
    const loginMock = vi.mocked(api.login);
    loginMock.mockRejectedValue({
      errors: [{ message: "Invalid email or password", code: "unauthorized" }],
    });

    renderLoginPage();
    const user = userEvent.setup();

    await user.type(screen.getByLabelText(/work email/i), "test@example.com");
    await user.type(screen.getByLabelText(/password/i), "WrongPass!");
    await user.click(screen.getByRole("button", { name: /sign in/i }));

    expect(
      await screen.findByText("Invalid email or password"),
    ).toBeInTheDocument();
  });

  it("disables submit button while loading", async () => {
    const { default: api } = await import("@/api/client");
    const loginMock = vi.mocked(api.login);
    // Never resolves — simulates slow network
    loginMock.mockReturnValue(new Promise(() => {}));

    renderLoginPage();
    const user = userEvent.setup();

    await user.type(screen.getByLabelText(/work email/i), "test@example.com");
    await user.type(screen.getByLabelText(/password/i), "Password123!");
    await user.click(screen.getByRole("button", { name: /sign in/i }));

    await waitFor(() => {
      expect(
        screen.getByRole("button", { name: /signing in/i }),
      ).toBeDisabled();
    });
  });
});
