import * as stylex from "@stylexjs/stylex";
import { copy, fromKg, roundWeight, type WeightUnit } from "@cauldron/shared";
import { type FormEvent, useState } from "react";
import { showNumber } from "../../lib/targets";
import { parseWeight, weightLimits } from "../../lib/weight";
import { fonts } from "../../styles/tokens.stylex";
import { Button, Dialog, Input } from "../ui";

// One step to log or change a weigh-in: a number in the user's unit, Enter
// saves. With `pickDay` it also asks which day (for adding a past one).

const t = copy.tracker.weight;

export function WeightDialog({
  open,
  onClose,
  unit,
  title,
  today,
  date,
  weightKg,
  pickDay = false,
  onSave,
  onRemove,
}: {
  open: boolean;
  onClose: () => void;
  unit: WeightUnit;
  title: string;
  today: string;
  /** The day being logged; the starting day when `pickDay` is on. */
  date: string;
  /** What's logged for the day now, if anything. */
  weightKg: number | null;
  pickDay?: boolean;
  onSave: (date: string, weightKg: number) => void;
  /** Offered when there's a weigh-in to take away. */
  onRemove?: () => void;
}) {
  return (
    <Dialog open={open} onClose={onClose} title={title}>
      {/* Mounted only while open, so each opening starts from what's logged. */}
      {open ? (
        <Form
          unit={unit}
          today={today}
          date={date}
          weightKg={weightKg}
          pickDay={pickDay}
          onSave={onSave}
          onRemove={onRemove}
          onCancel={onClose}
        />
      ) : null}
    </Dialog>
  );
}

function Form({
  unit,
  today,
  date,
  weightKg,
  pickDay,
  onSave,
  onRemove,
  onCancel,
}: {
  unit: WeightUnit;
  today: string;
  date: string;
  weightKg: number | null;
  pickDay: boolean;
  onSave: (date: string, weightKg: number) => void;
  onRemove: (() => void) | undefined;
  onCancel: () => void;
}) {
  const [text, setText] = useState(
    weightKg === null ? "" : showNumber(roundWeight(fromKg(weightKg, unit))),
  );
  const [day, setDay] = useState(date);
  const [error, setError] = useState<string | undefined>();

  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (day === "" || day > today) return setError(t.needDay.text);
    const kg = parseWeight(text, unit);
    if (kg === null) {
      const { min, max } = weightLimits(unit);
      return setError(t.outOfRange(showNumber(min), showNumber(max), unit).text);
    }
    onSave(day, kg);
  };

  return (
    <form onSubmit={submit} noValidate {...stylex.props(styles.form)}>
      {pickDay ? (
        <Input
          label={t.day.text}
          type="date"
          value={day}
          max={today}
          onChange={(e) => setDay(e.target.value)}
          xstyle={styles.mono}
        />
      ) : null}
      <Input
        label={t.label(unit).text}
        inputMode="decimal"
        autoComplete="off"
        data-autofocus
        value={text}
        error={error}
        onChange={(e) => {
          setText(e.target.value);
          setError(undefined);
        }}
        xstyle={styles.mono}
      />
      <div {...stylex.props(styles.actions)}>
        {onRemove ? (
          <Button variant="danger" onClick={onRemove}>
            {t.remove.text}
          </Button>
        ) : null}
        <span {...stylex.props(styles.spacer)} />
        <Button variant="secondary" onClick={onCancel}>
          {t.cancel.text}
        </Button>
        <Button type="submit">{t.save.text}</Button>
      </div>
    </form>
  );
}

const styles = stylex.create({
  form: { display: "flex", flexDirection: "column", gap: 16 },
  mono: { fontFamily: fonts.mono },
  actions: { display: "flex", alignItems: "center", gap: 8 },
  spacer: { flexGrow: 1 },
});
