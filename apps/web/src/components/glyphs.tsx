import type { ReactNode } from "react";

// The brand book's 16px UI glyphs. Decorative: the label beside each carries the meaning.

const Glyph = ({ children }: { children: ReactNode }) => (
  <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true" fill="none">
    {children}
  </svg>
);

export const BookGlyph = () => (
  <Glyph>
    <path
      d="M3 2.5h8.5a1 1 0 0 1 1 1v10H4a1 1 0 0 1-1-1z"
      stroke="currentColor"
      strokeWidth="1.4"
      strokeLinejoin="round"
    />
    <path d="M3 12.5a1 1 0 0 1 1-1h8.5" stroke="currentColor" strokeWidth="1.4" />
  </Glyph>
);

export const CalendarGlyph = () => (
  <Glyph>
    <rect x="2" y="3" width="12" height="11" rx="2" stroke="currentColor" strokeWidth="1.4" />
    <path
      d="M2 6.5h12M5.5 1.5v3M10.5 1.5v3"
      stroke="currentColor"
      strokeWidth="1.4"
      strokeLinecap="round"
    />
  </Glyph>
);

export const BagGlyph = () => (
  <Glyph>
    <path
      d="M3 5.5h10l-.8 8.5H3.8z"
      stroke="currentColor"
      strokeWidth="1.4"
      strokeLinejoin="round"
    />
    <path d="M5.5 5.5V4a2.5 2.5 0 0 1 5 0v1.5" stroke="currentColor" strokeWidth="1.4" />
  </Glyph>
);

export const ChartGlyph = () => (
  <Glyph>
    <path
      d="M2 13.5h12M4.5 11V8M8 11V4.5M11.5 11V7"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
    />
  </Glyph>
);

export const SearchGlyph = () => (
  <Glyph>
    <circle cx="7" cy="7" r="5" stroke="currentColor" strokeWidth="1.6" />
    <path d="M11 11l3.5 3.5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
  </Glyph>
);

export const PlusGlyph = () => (
  <Glyph>
    <path d="M8 3v10M3 8h10" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
  </Glyph>
);

export const MenuGlyph = () => (
  <Glyph>
    <path
      d="M2.5 4h11M2.5 8h11M2.5 12h11"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
    />
  </Glyph>
);

export const PersonGlyph = () => (
  <Glyph>
    <circle cx="8" cy="5.5" r="2.75" stroke="currentColor" strokeWidth="1.4" />
    <path
      d="M2.75 14a5.25 5.25 0 0 1 10.5 0"
      stroke="currentColor"
      strokeWidth="1.4"
      strokeLinecap="round"
    />
  </Glyph>
);

export const CloseGlyph = () => (
  <Glyph>
    <path d="M4 4l8 8M12 4l-8 8" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
  </Glyph>
);
