import * as stylex from "@stylexjs/stylex";
import { copy } from "@cauldron/shared";
import { colors } from "../styles/tokens.stylex";
import { Dialog, Input } from "./ui";

/** ⌘K search. #11 fills in the results; for now it's the field and a hint. */
export function SummonDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  return (
    <Dialog open={open} onClose={onClose} title={copy.recipes.summon.text} hideTitle>
      <Input
        label={copy.recipes.summon.text}
        type="search"
        name="q"
        autoComplete="off"
        data-autofocus
      />
      <p {...stylex.props(styles.hint)}>{copy.recipes.summonHint.text}</p>
    </Dialog>
  );
}

const styles = stylex.create({ hint: { margin: 0, fontSize: 14, color: colors.subtext } });
