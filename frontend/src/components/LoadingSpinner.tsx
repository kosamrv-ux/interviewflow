import { clsx } from "clsx";

interface LoadingSpinnerProps {
  size?: "sm" | "md" | "lg";
  className?: string;
  label?: string;
}

const sizeMap = {
  sm: "h-4 w-4 border-2",
  md: "h-6 w-6 border-2",
  lg: "h-10 w-10 border-[3px]",
};

export default function LoadingSpinner({
  size = "md",
  className,
  label = "Loading...",
}: LoadingSpinnerProps) {
  return (
    <div
      role="status"
      aria-label={label}
      className={clsx("flex items-center justify-center", className)}
    >
      <span
        className={clsx(
          "inline-block rounded-full border-solid",
          "border-t-transparent border-r-transparent",
          "animate-spin",
          sizeMap[size],
        )}
        style={{
          borderColor: "var(--color-primary)",
          borderTopColor: "transparent",
          borderRightColor: "transparent",
        }}
      />
      <span className="sr-only">{label}</span>
    </div>
  );
}
