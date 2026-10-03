import * as stylex from "@stylexjs/stylex";
import { addDays, copy, type DiaryDay, MEAL_SLOTS, type MealSlot } from "@cauldron/shared";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { type FormEvent, useState } from "react";
import { messageOr } from "../../lib/api-failure";
import { dayLabel } from "../../lib/dates";
import { trackerApi, trackerKeys } from "../../lib/tracker";
import { fonts } from "../../styles/tokens.stylex";
import { Button, Dialog, FormMessage, Input, Select, useToast } from "../ui";

// Copying a meal or a whole day (#116) from yesterday, or any day, into the
// day the diary shows.

/** Copies `from` (or one meal of it) into `to`, then shows `to` as the API has it. */
export function useCopyDay() {
  const queryClient = useQueryClient();
  const notify = useToast();
  return useMutation({
    mutationFn: (input: { from: string; to: string; slot: MealSlot | null }) =>
      trackerApi.copy(input),
    onSuccess: (day: DiaryDay, input) => {
      const before = queryClient.getQueryData<DiaryDay>(trackerKeys.day(input.to));
      const added = day.entries.length - (before?.entries.length ?? 0);
      queryClient.setQueryData(trackerKeys.day(input.to), day);
      notify(
        added > 0 ? copy.tracker.copyDay.copied(added).text : copy.tracker.copyDay.nothing.text,
      );
    },
    onError: (e) => notify(messageOr(e, copy.tracker.diary.couldntSave.text), "error"),
    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: trackerKeys.intake });
      void queryClient.invalidateQueries({ queryKey: trackerKeys.quick });
    },
  });
}

export function CopyDayDialog({
  to,
  open,
  onClose,
}: {
  to: string;
  open: boolean;
  onClose: () => void;
}) {
  return (
    <Dialog
      open={open}
      onClose={onClose}
      title={copy.tracker.copyDay.title(dayLabel(to, "long")).text}
    >
      {open ? <CopyForm key={to} to={to} onDone={onClose} /> : null}
    </Dialog>
  );
}

function CopyForm({ to, onDone }: { to: string; onDone: () => void }) {
  const [from, setFrom] = useState(addDays(to, -1));
  const [slot, setSlot] = useState<MealSlot | "all">("all");
  const [error, setError] = useState<string | null>(null);
  const copyDay = useCopyDay();

  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (from === to) return setError(copy.tracker.copyDay.sameDay.text);
    copyDay.mutate({ from, to, slot: slot === "all" ? null : slot }, { onSuccess: onDone });
  };

  return (
    <form onSubmit={submit} noValidate {...stylex.props(styles.form)}>
      <div {...stylex.props(styles.row)}>
        <Input
          type="date"
          label={copy.tracker.copyDay.from.text}
          value={from}
          max={to}
          onChange={(e) => {
            setError(null);
            setFrom(e.target.value);
          }}
          xstyle={styles.mono}
        />
        <Select
          label={copy.tracker.copyDay.meal.text}
          value={slot}
          onChange={(e) => setSlot(e.target.value as MealSlot | "all")}
        >
          <option value="all">{copy.tracker.copyDay.wholeDay.text}</option>
          {MEAL_SLOTS.map((s) => (
            <option key={s} value={s}>
              {copy.week.slots[s].text}
            </option>
          ))}
        </Select>
      </div>
      {error ? <FormMessage tone="error">{error}</FormMessage> : null}
      <div {...stylex.props(styles.actions)}>
        <Button type="submit" disabled={copyDay.isPending || from === ""}>
          {copy.tracker.copyDay.copy.text}
        </Button>
      </div>
    </form>
  );
}

const styles = stylex.create({
  form: { display: "flex", flexDirection: "column", gap: 12 },
  row: {
    display: "grid",
    gridTemplateColumns: { default: "1fr 1fr", "@media (max-width: 480px)": "1fr" },
    gap: 10,
  },
  mono: { fontFamily: fonts.mono },
  actions: { display: "flex", justifyContent: "flex-end", gap: 8 },
});
