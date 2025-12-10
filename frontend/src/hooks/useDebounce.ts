import { useState, useEffect } from "react";

/**
 * Delays updating the returned value until the input hasn't changed for
 * `delay` milliseconds.  Used to avoid firing a search query on every
 * keystroke.
 */
export function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState<T>(value);

  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedValue(value);
    }, delay);

    return () => {
      clearTimeout(timer);
    };
  }, [value, delay]);

  return debouncedValue;
}
