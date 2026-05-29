import React, { useState, useCallback } from "react";

interface Props {
  onDateSelected: (date: Date) => void;
  minDate?: Date;
  maxDate?: Date;
  disabledDates?: Date[];
  timezone?: string;
}

/**
 * Date picker component for interview scheduling.
 *
 * DST bug fix (May 2026):
 * In timezones that observe Daylight Saving Time (US/Eastern, US/Central, etc.),
 * the date picker was showing an off-by-one error on the first day after a DST
 * transition. For example, when DST ended on Nov 2 2025 (clocks fell back 1 hour),
 * selecting Nov 3 in the calendar would submit Nov 2 to the backend.
 *
 * Root cause: we were constructing dates using `new Date(year, month, day)` which
 * creates a date in the LOCAL timezone at midnight. When that local midnight was
 * serialized to ISO8601 for the API, the UTC offset caused it to fall on the
 * previous calendar day.
 *
 * Example:
 *   new Date(2025, 10, 3) // Nov 3 at 00:00 EST (UTC-5) = Nov 3 05:00 UTC ✓
 *   new Date(2025, 10, 3) // Nov 3 at 00:00 EDT (UTC-4) = Nov 3 04:00 UTC ✓
 * But during the transition hour:
 *   The JS date was being constructed with a hardcoded offset that didn't
 *   account for the 1-hour shift, resulting in Nov 2 23:00 UTC.
 *
 * Fix: construct dates at noon local time (12:00) instead of midnight to avoid
 * the ambiguous boundary period during DST transitions. Noon is safely within
 * the day regardless of UTC offset.
 */
export function InterviewScheduler({
  onDateSelected,
  minDate,
  maxDate,
  disabledDates = [],
  timezone = Intl.DateTimeFormat().resolvedOptions().timeZone,
}: Props) {
  const today = new Date();
  const [viewYear, setViewYear] = useState(today.getFullYear());
  const [viewMonth, setViewMonth] = useState(today.getMonth());
  const [selectedDate, setSelectedDate] = useState<Date | null>(null);
  const [selectedTime, setSelectedTime] = useState("09:00");

  const daysInMonth = new Date(viewYear, viewMonth + 1, 0).getDate();
  const firstDayOfMonth = new Date(viewYear, viewMonth, 1).getDay();

  const isDisabled = useCallback(
    (day: number) => {
      // Construct at noon to avoid DST boundary issues
      const date = new Date(viewYear, viewMonth, day, 12, 0, 0);

      if (minDate && date < new Date(minDate.getFullYear(), minDate.getMonth(), minDate.getDate(), 12)) {
        return true;
      }
      if (maxDate && date > new Date(maxDate.getFullYear(), maxDate.getMonth(), maxDate.getDate(), 12)) {
        return true;
      }

      return disabledDates.some(
        (d) =>
          d.getFullYear() === viewYear &&
          d.getMonth() === viewMonth &&
          d.getDate() === day
      );
    },
    [viewYear, viewMonth, minDate, maxDate, disabledDates]
  );

  const isSelected = useCallback(
    (day: number) =>
      selectedDate?.getFullYear() === viewYear &&
      selectedDate?.getMonth() === viewMonth &&
      selectedDate?.getDate() === day,
    [selectedDate, viewYear, viewMonth]
  );

  const isToday = useCallback(
    (day: number) =>
      today.getFullYear() === viewYear &&
      today.getMonth() === viewMonth &&
      today.getDate() === day,
    [today, viewYear, viewMonth]
  );

  const handleDayClick = useCallback(
    (day: number) => {
      if (isDisabled(day)) return;
      // Construct at noon to avoid DST off-by-one
      const date = new Date(viewYear, viewMonth, day, 12, 0, 0);
      setSelectedDate(date);
    },
    [isDisabled, viewYear, viewMonth]
  );

  const handleConfirm = useCallback(() => {
    if (!selectedDate) return;

    const [hours, minutes] = selectedTime.split(":").map(Number);

    // Build the final datetime at the specified time (not noon placeholder)
    const finalDate = new Date(
      selectedDate.getFullYear(),
      selectedDate.getMonth(),
      selectedDate.getDate(),
      hours,
      minutes,
      0,
      0
    );

    onDateSelected(finalDate);
  }, [selectedDate, selectedTime, onDateSelected]);

  const prevMonth = () => {
    if (viewMonth === 0) {
      setViewMonth(11);
      setViewYear((y) => y - 1);
    } else {
      setViewMonth((m) => m - 1);
    }
  };

  const nextMonth = () => {
    if (viewMonth === 11) {
      setViewMonth(0);
      setViewYear((y) => y + 1);
    } else {
      setViewMonth((m) => m + 1);
    }
  };

  const monthName = new Date(viewYear, viewMonth, 1).toLocaleString("default", {
    month: "long",
    year: "numeric",
  });

  const days = Array.from({ length: daysInMonth }, (_, i) => i + 1);
  const blanks = Array.from({ length: firstDayOfMonth }, (_, i) => i);

  return (
    <div className="bg-white rounded-lg border border-gray-200 p-4 max-w-sm">
      <div className="flex items-center justify-between mb-4">
        <button onClick={prevMonth} className="p-1 hover:bg-gray-100 rounded-md">
          ‹
        </button>
        <span className="text-sm font-semibold text-gray-800">{monthName}</span>
        <button onClick={nextMonth} className="p-1 hover:bg-gray-100 rounded-md">
          ›
        </button>
      </div>

      <div className="grid grid-cols-7 gap-0 mb-2">
        {["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"].map((d) => (
          <div key={d} className="text-center text-xs font-medium text-gray-400 py-1">
            {d}
          </div>
        ))}
        {blanks.map((_, i) => (
          <div key={`blank-${i}`} />
        ))}
        {days.map((day) => (
          <button
            key={day}
            onClick={() => handleDayClick(day)}
            disabled={isDisabled(day)}
            className={`
              w-8 h-8 mx-auto rounded-full text-sm transition-colors
              ${isSelected(day) ? "bg-indigo-600 text-white" : ""}
              ${isToday(day) && !isSelected(day) ? "border border-indigo-400 text-indigo-600" : ""}
              ${!isSelected(day) && !isDisabled(day) ? "hover:bg-gray-100 text-gray-700" : ""}
              ${isDisabled(day) ? "text-gray-200 cursor-not-allowed" : "cursor-pointer"}
            `}
          >
            {day}
          </button>
        ))}
      </div>

      {selectedDate && (
        <div className="mt-4 border-t border-gray-100 pt-4">
          <label className="block text-xs font-medium text-gray-600 mb-1">
            Time ({timezone})
          </label>
          <input
            type="time"
            value={selectedTime}
            onChange={(e) => setSelectedTime(e.target.value)}
            className="w-full rounded-md border border-gray-300 px-3 py-1.5 text-sm"
          />
          <button
            onClick={handleConfirm}
            className="mt-3 w-full bg-indigo-600 text-white text-sm font-medium py-2 rounded-md hover:bg-indigo-700"
          >
            Confirm:{" "}
            {selectedDate.toLocaleDateString("default", {
              weekday: "short",
              month: "short",
              day: "numeric",
            })}{" "}
            at {selectedTime}
          </button>
        </div>
      )}
    </div>
  );
}
