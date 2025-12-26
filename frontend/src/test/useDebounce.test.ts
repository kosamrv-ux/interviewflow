import { describe, it, expect, vi, afterEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { useDebounce } from "@/hooks/useDebounce";

describe("useDebounce", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it("returns the initial value immediately", () => {
    const { result } = renderHook(() => useDebounce("hello", 300));
    expect(result.current).toBe("hello");
  });

  it("does not update the value before the delay elapses", () => {
    vi.useFakeTimers();
    const { result, rerender } = renderHook(
      ({ value, delay }) => useDebounce(value, delay),
      { initialProps: { value: "hello", delay: 300 } },
    );

    rerender({ value: "world", delay: 300 });

    // Advance only 200ms — value should still be "hello"
    act(() => {
      vi.advanceTimersByTime(200);
    });

    expect(result.current).toBe("hello");
  });

  it("updates the value after the full delay has elapsed", () => {
    vi.useFakeTimers();
    const { result, rerender } = renderHook(
      ({ value, delay }) => useDebounce(value, delay),
      { initialProps: { value: "hello", delay: 300 } },
    );

    rerender({ value: "world", delay: 300 });

    act(() => {
      vi.advanceTimersByTime(300);
    });

    expect(result.current).toBe("world");
  });

  it("resets the timer when the value changes before delay elapses", () => {
    vi.useFakeTimers();
    const { result, rerender } = renderHook(
      ({ value, delay }) => useDebounce(value, delay),
      { initialProps: { value: "a", delay: 300 } },
    );

    rerender({ value: "b", delay: 300 });
    act(() => {
      vi.advanceTimersByTime(200);
    });

    // Change value again before 300ms is up
    rerender({ value: "c", delay: 300 });
    act(() => {
      vi.advanceTimersByTime(200);
    });

    // Total 400ms elapsed but last change was only 200ms ago — still "a"
    expect(result.current).toBe("a");

    // Advance remaining 100ms
    act(() => {
      vi.advanceTimersByTime(100);
    });

    expect(result.current).toBe("c");
  });

  it("works with numeric values", () => {
    vi.useFakeTimers();
    const { result, rerender } = renderHook(
      ({ value, delay }) => useDebounce(value, delay),
      { initialProps: { value: 0, delay: 500 } },
    );

    rerender({ value: 42, delay: 500 });
    act(() => {
      vi.advanceTimersByTime(500);
    });

    expect(result.current).toBe(42);
  });

  it("cleans up the timer on unmount", () => {
    vi.useFakeTimers();
    const clearTimeoutSpy = vi.spyOn(globalThis, "clearTimeout");

    const { rerender, unmount } = renderHook(
      ({ value, delay }) => useDebounce(value, delay),
      { initialProps: { value: "start", delay: 300 } },
    );

    rerender({ value: "changed", delay: 300 });
    unmount();

    expect(clearTimeoutSpy).toHaveBeenCalled();
    clearTimeoutSpy.mockRestore();
  });
});
