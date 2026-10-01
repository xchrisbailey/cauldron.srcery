import * as stylex from "@stylexjs/stylex";
import { copy } from "@cauldron/shared";
import { colors, fonts } from "../styles/tokens.stylex";
import { Mark } from "./Mark";

/**
 * The mark beside the `cauldron` wordmark (Geist 800, tracked tight). `hero` is
 * the landing page's large version with the pink ring and lavender dot rising
 * out of the o and the peach cursor; the sidebar uses the small one.
 */
export function Lockup({ size = "small" }: { size?: "small" | "hero" }) {
  const hero = size === "hero";
  const word = copy.ui.wordmark.text;
  const o = word.lastIndexOf("o");
  return (
    <span {...stylex.props(styles.lockup, hero && styles.lockupHero)}>
      <Mark size={hero ? 88 : 30} />
      <span {...stylex.props(styles.word, hero ? styles.wordHero : styles.wordSmall)}>
        {hero ? (
          <>
            {word.slice(0, o)}
            <span {...stylex.props(styles.bubblingO)}>
              {word[o]}
              <span aria-hidden="true" {...stylex.props(styles.ring)} />
              <span aria-hidden="true" {...stylex.props(styles.dot)} />
            </span>
            {word.slice(o + 1)}
            <span aria-hidden="true" {...stylex.props(styles.cursor)}>
              _
            </span>
          </>
        ) : (
          word
        )}
      </span>
    </span>
  );
}

const blink = stylex.keyframes({ "50%": { opacity: 0 } });

const styles = stylex.create({
  lockup: { display: "inline-flex", alignItems: "center", gap: 9 },
  lockupHero: { gap: { default: 14, "@media (min-width: 768px)": 20 }, flexWrap: "wrap" },
  word: { fontWeight: 800, color: colors.ink, lineHeight: 1 },
  wordSmall: { fontSize: 21, letterSpacing: "-0.04em" },
  wordHero: {
    fontSize: "clamp(3rem, 12vw, 5.5rem)",
    letterSpacing: "-0.045em",
    lineHeight: 0.9,
  },
  bubblingO: { position: "relative", display: "inline-block" },
  ring: {
    position: "absolute",
    left: "46%",
    top: "0.02em",
    width: "0.17em",
    height: "0.17em",
    borderRadius: "50%",
    borderWidth: "0.042em",
    borderStyle: "solid",
    borderColor: colors.sparklePink,
  },
  dot: {
    position: "absolute",
    left: "16%",
    top: "-0.2em",
    width: "0.11em",
    height: "0.11em",
    borderRadius: "50%",
    backgroundColor: colors.sparkleLavender,
  },
  cursor: {
    marginLeft: "0.04em",
    color: colors.heat,
    fontFamily: fonts.mono,
    fontWeight: 700,
    animationName: { default: blink, "@media (prefers-reduced-motion: reduce)": "none" },
    animationDuration: "1.2s",
    animationTimingFunction: "steps(1)",
    animationIterationCount: "infinite",
  },
});
