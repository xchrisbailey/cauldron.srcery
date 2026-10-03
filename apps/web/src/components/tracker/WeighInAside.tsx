import * as stylex from "@stylexjs/stylex";
import { copy, type WeighIn, type WeightUnit } from "@cauldron/shared";
import { Link } from "@tanstack/react-router";
import { useState } from "react";
import { useWeighInWrites } from "../../lib/weigh-in-writes";
import { weightLabel } from "../../lib/targets";
import { colors, fonts } from "../../styles/tokens.stylex";
import { Button } from "../ui";
import { focusRing } from "../ui/controls";
import { WeightDialog } from "./WeightDialog";

// The day's weigh-in beside the calories: the weight in the user's unit (tap to
// change it) or a button to log one, and a way into the weight page.

const t = copy.tracker.weight;

export function WeighInAside({
  date,
  today,
  weighIn,
  unit,
}: {
  date: string;
  today: string;
  weighIn: WeighIn | null;
  unit: WeightUnit;
}) {
  const writes = useWeighInWrites();
  const [open, setOpen] = useState(false);
  const shown = weighIn ? `${weightLabel(weighIn.weightKg, unit)} ${unit}` : null;

  return (
    <div {...stylex.props(styles.root)}>
      {shown ? (
        <button
          type="button"
          onClick={() => setOpen(true)}
          aria-label={t.change(shown).text}
          {...stylex.props(styles.weight, focusRing.ring)}
        >
          <span {...stylex.props(styles.figure)}>{weightLabel(weighIn!.weightKg, unit)}</span>
          <span {...stylex.props(styles.unit)}> {unit}</span>
        </button>
      ) : (
        <Button variant="secondary" onClick={() => setOpen(true)}>
          {t.logWeight.text}
        </Button>
      )}
      <Link to="/tracker/weight" {...stylex.props(styles.link, focusRing.ring)}>
        {t.seeTrend.text}
      </Link>
      <WeightDialog
        open={open}
        onClose={() => setOpen(false)}
        unit={unit}
        title={t.logTitle.text}
        today={today}
        date={date}
        weightKg={weighIn?.weightKg ?? null}
        onSave={(day, kg) => {
          setOpen(false);
          void writes.save(day, kg);
        }}
        {...(weighIn
          ? {
              onRemove: () => {
                setOpen(false);
                void writes.remove(date, weighIn.weightKg);
              },
            }
          : {})}
      />
    </div>
  );
}

const styles = stylex.create({
  root: { display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 4 },
  weight: {
    paddingBlock: 2,
    paddingInline: 6,
    borderWidth: 0,
    borderRadius: 8,
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.ink,
    cursor: "pointer",
    fontFamily: fonts.mono,
    fontVariantNumeric: "tabular-nums",
  },
  figure: { fontSize: 20, fontWeight: 600 },
  unit: { fontSize: 12, color: colors.overlay1 },
  link: { fontSize: 13, color: colors.subtext },
});
