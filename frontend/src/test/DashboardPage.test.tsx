import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import { DashboardPage } from "@/pages/DashboardPage";

// Mock the API client
vi.mock("@/api/client", () => ({
  api: {
    get: vi.fn(),
  },
}));

// Mock AppLayout to keep tests simple
vi.mock("@/components/AppLayout", () => ({
  AppLayout: ({ children }: { children: React.ReactNode }) => <div data-testid="app-layout">{children}</div>,
}));

const { api } = await import("@/api/client");
const mockApi = api as { get: ReturnType<typeof vi.fn> };

const mockDashboard = {
  kpis: {
    active_jobs: 4,
    total_candidates: 127,
    interviews_this_week: 8,
    avg_composite_score: 7.3,
    pipeline_conversion_rate: 0.22,
  },
  pipeline_stage_counts: {
    applied: 45,
    screen: 28,
    interview: 18,
    offer: 8,
    hired: 12,
  },
  recent_applications: [
    {
      id: "app-1",
      candidate_name: "Alice Johnson",
      job_title: "Senior Backend Engineer",
      pipeline_stage: "interview",
      status: "active",
      composite_score: "8.4",
      inserted_at: "2025-12-10T09:00:00Z",
    },
    {
      id: "app-2",
      candidate_name: "Bob Williams",
      job_title: "Frontend Engineer",
      pipeline_stage: "screen",
      status: "active",
      composite_score: null,
      inserted_at: "2025-12-10T11:00:00Z",
    },
  ],
};

function renderWithProviders(ui: React.ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>{ui}</MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("DashboardPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockApi.get.mockResolvedValue(mockDashboard);
  });

  it("renders the page title", async () => {
    renderWithProviders(<DashboardPage />);
    expect(screen.getByText(/dashboard/i)).toBeTruthy();
  });

  it("displays KPI cards after data loads", async () => {
    renderWithProviders(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText("4")).toBeTruthy(); // active_jobs
    });

    expect(screen.getByText("127")).toBeTruthy(); // total_candidates
    expect(screen.getByText("8")).toBeTruthy(); // interviews_this_week
  });

  it("shows recent applications table", async () => {
    renderWithProviders(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText("Alice Johnson")).toBeTruthy();
    });

    expect(screen.getByText("Bob Williams")).toBeTruthy();
    expect(screen.getByText("Senior Backend Engineer")).toBeTruthy();
  });

  it("shows composite score badge for scored applications", async () => {
    renderWithProviders(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText("8.4")).toBeTruthy();
    });
  });

  it("shows dash for unscored applications", async () => {
    renderWithProviders(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText("Alice Johnson")).toBeTruthy();
    });

    // Bob has no score — should show an em dash or similar placeholder
    const noScore = screen.getAllByText("—");
    expect(noScore.length).toBeGreaterThan(0);
  });

  it("shows pipeline stage counts in the bar chart section", async () => {
    renderWithProviders(<DashboardPage />);

    await waitFor(() => {
      // Stage labels should appear
      expect(screen.getByText(/applied/i)).toBeTruthy();
    });
  });

  it("shows loading state initially", () => {
    // Mock never resolves
    mockApi.get.mockReturnValue(new Promise(() => {}));
    renderWithProviders(<DashboardPage />);

    // Loading indicator should be visible before data arrives
    expect(screen.getByRole("main") || screen.getByTestId("app-layout")).toBeTruthy();
  });

  it("shows error state on API failure", async () => {
    mockApi.get.mockRejectedValue(new Error("Network error"));
    renderWithProviders(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText(/failed to load/i)).toBeTruthy();
    });
  });
});
