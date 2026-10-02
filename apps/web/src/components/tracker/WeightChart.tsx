import * as stylex from "@stylexjs/stylex";
import { copy, type TrendPoint, type WeightUnit } from "@cauldron/shared";
import { shortDate } from "../../lib/dates";
import { showNumber } from "../../lib/targets";
import { buildChart } from "../../lib/weight";
import { useEffect, useRef, useState } from "react";
import { colors, fonts } from "../../styles/tokens.stylex";

// Weigh-ins as dots and the smoothed trend as a line, drawn as inline SVG. The
// viewBox follows the box's own width, so the axis labels stay readable on a
// phone instead of shrinking with a wide drawing.

const t = copy.tracker.weight;

export function WeightChart({
  points,
  unit,
  start,
  end,
}: {
  points: ReadonlyArray<TrendPoint>;
  unit: WeightUnit;
  start: string;
  end: string;
}) {
  const ref = useRef<HTMLElement>(null);
  const [width, setWidth] = useState(640);
  useEffect(() => {
    const box = ref.current;
    if (!box) return;
    const observer = new ResizeObserver(([entry]) => {
      if (entry) setWidth(Math.max(280, Math.round(entry.contentRect.width)));
    });
    observer.observe(box);
    return () => observer.disconnect();
  }, []);
  const height = Math.round(Math.min(280, Math.max(200, width * 0.5)));
  const chart = buildChart(points, unit, start, end, { width, height });
  const { plot } = chart;
  const first = points[0];
  const last = points[points.length - 1];
  return (
    <figure ref={ref} {...stylex.props(styles.figure)}>
      <svg
        viewBox={`0 0 ${chart.width} ${chart.height}`}
        role="img"
        aria-label={
          first && last
            ? t.chartSummary(points.length, shortDate(first.date, true), shortDate(last.date, true))
                .text
            : t.chartLabel.text
        }
        {...stylex.props(styles.svg)}
      >
        {chart.yTicks.map((tick) => (
          <g key={tick.value}>
            <line
              x1={plot.left}
              x2={plot.right}
              y1={tick.y}
              y2={tick.y}
              {...stylex.props(styles.grid)}
            />
            <text x={plot.left - 8} y={tick.y} {...stylex.props(styles.text, styles.yText)}>
              {showNumber(tick.value)}
            </text>
          </g>
        ))}
        {chart.xTicks.map((tick, i) => (
          <text
            key={tick.date}
            x={tick.x}
            y={plot.bottom + 18}
            {...stylex.props(
              styles.text,
              i === 0 ? styles.startText : i === chart.xTicks.length - 1 ? styles.endText : null,
            )}
          >
            {shortDate(tick.date)}
          </text>
        ))}
        {chart.line ? <path d={chart.line} {...stylex.props(styles.trend)} /> : null}
        {chart.dots.map((dot) => (
          <circle key={dot.date} cx={dot.x} cy={dot.y} r={3} {...stylex.props(styles.dot)} />
        ))}
      </svg>
      <figcaption {...stylex.props(styles.legend)}>
        <span {...stylex.props(styles.key)}>
          <span aria-hidden="true" {...stylex.props(styles.swatchDot)} />
          {t.legendScale.text}
        </span>
        <span {...stylex.props(styles.key)}>
          <span aria-hidden="true" {...stylex.props(styles.swatchLine)} />
          {t.legendTrend.text}
        </span>
        <span {...stylex.props(styles.key)}>{unit}</span>
      </figcaption>
    </figure>
  );
}

const styles = stylex.create({
  figure: { margin: 0, display: "flex", flexDirection: "column", gap: 8 },
  svg: { display: "block", width: "100%", height: "auto" },
  grid: { stroke: colors.surface0, strokeWidth: 1 },
  text: {
    fontFamily: fonts.mono,
    fontSize: 11,
    fill: colors.overlay1,
    textAnchor: "middle",
  },
  yText: { textAnchor: "end", dominantBaseline: "middle" },
  startText: { textAnchor: "start" },
  endText: { textAnchor: "end" },
  trend: {
    fill: "none",
    stroke: colors.magic,
    strokeWidth: 2.5,
    strokeLinejoin: "round",
    strokeLinecap: "round",
  },
  dot: { fill: colors.overlay1, opacity: 0.8 },
  legend: {
    display: "flex",
    flexWrap: "wrap",
    gap: 16,
    fontFamily: fonts.mono,
    fontSize: 11,
    color: colors.subtext,
  },
  key: { display: "inline-flex", alignItems: "center", gap: 6 },
  swatchDot: { width: 7, height: 7, borderRadius: 999, backgroundColor: colors.overlay1 },
  swatchLine: { width: 16, height: 3, borderRadius: 3, backgroundColor: colors.magic },
});
