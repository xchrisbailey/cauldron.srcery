import * as stylex from "@stylexjs/stylex";
import { colors } from "../../styles/tokens.stylex";

const pulse = stylex.keyframes({
  "0%": { opacity: 1 },
  "50%": { opacity: 0.5 },
  "100%": { opacity: 1 },
});

/** A placeholder block while something loads. Decorative: put `aria-busy` on the region it stands in for. */
export function Skeleton({
  width = "100%",
  height = 16,
  radius = 6,
}: {
  width?: number | string;
  height?: number | string;
  radius?: number;
}) {
  return (
    <span aria-hidden="true" {...stylex.props(styles.block, styles.size(width, height, radius))} />
  );
}

const styles = stylex.create({
  block: {
    display: "block",
    backgroundColor: colors.surface0,
    animationName: { default: pulse, "@media (prefers-reduced-motion: reduce)": "none" },
    animationDuration: "1.6s",
    animationIterationCount: "infinite",
    animationTimingFunction: "ease-in-out",
  },
  size: (width: number | string, height: number | string, radius: number) => ({
    width,
    height,
    borderRadius: radius,
  }),
});
