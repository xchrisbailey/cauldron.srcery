import { useId } from "react";

// The cauldron mark (brand/mark-*.svg), drawn with theme variables so it
// follows Mocha and Latte. brand/build.ts holds the same geometry.
export function Mark({ size = 32, title }: { size?: number; title?: string }) {
  const clip = `pot-${useId()}`;
  const ink = "var(--ctp-text)";
  const base = "var(--ctp-base)";
  return (
    <svg
      width={size}
      height={size}
      viewBox="-1 -1 66 66"
      role={title ? "img" : undefined}
      aria-label={title}
      aria-hidden={title ? undefined : true}
    >
      <defs>
        <clipPath id={clip}>
          <path d="M14.5 28.5H49.5V33A17.5 17.5 0 0 1 14.5 33Z" />
        </clipPath>
      </defs>
      <path
        fill="var(--ctp-peach)"
        d="M32 51Q39.5 57 37.8 60.6Q36.3 63.6 32 63.6Q27.7 63.6 26.2 60.6Q24.5 57 32 51Z"
      />
      <path
        d="M19.5 49L16.5 58M44.5 49L47.5 58"
        stroke={ink}
        strokeWidth="3"
        strokeLinecap="round"
        fill="none"
      />
      <path
        d="M13 27H51V33A19 19 0 0 1 13 33Z"
        fill={base}
        stroke={ink}
        strokeWidth="3"
        strokeLinejoin="round"
      />
      <path
        fill="var(--ctp-mauve)"
        clipPath={`url(#${clip})`}
        d="M8 36Q14 31.5 20 36T32 36T44 36T56 36V60H8Z"
      />
      <circle fill={base} fillOpacity=".55" cx="25" cy="43" r="2.6" />
      <circle fill={base} fillOpacity=".55" cx="36" cy="47" r="1.8" />
      <rect x="9" y="21" width="46" height="7" rx="3.5" fill={base} stroke={ink} strokeWidth="3" />
      <circle fill="var(--ctp-mauve)" cx="27" cy="15" r="2.6" />
      <circle cx="38" cy="11" r="3" stroke="var(--ctp-pink)" strokeWidth="2" fill="none" />
      <circle fill="var(--ctp-lavender)" cx="45" cy="3.5" r="2.2" />
      <path
        fill="var(--ctp-yellow)"
        d="M12 3Q12 8.5 17.5 8.5Q12 8.5 12 14Q12 8.5 6.5 8.5Q12 8.5 12 3Z"
      />
    </svg>
  );
}
