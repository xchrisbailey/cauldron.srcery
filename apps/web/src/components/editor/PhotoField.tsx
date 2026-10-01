import * as stylex from "@stylexjs/stylex";
import { copy, photoUrl } from "@cauldron/shared";
import { useId, useRef, useState } from "react";
import { PHOTO_ACCEPT, photoError, uploadPhoto } from "../../lib/photos";
import { colors } from "../../styles/tokens.stylex";
import { Mark } from "../Mark";
import { Button } from "../ui";

// The cover photo: pick a file and it uploads straight away; the recipe keeps
// the photo's id. Replacing or removing it leaves the old one for cleanup.

export function PhotoField({
  photoKey,
  title,
  onChange,
}: {
  photoKey: string | null;
  title: string;
  onChange: (photoKey: string | null) => void;
}) {
  const id = useId();
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const pick = async (file: File | undefined) => {
    if (!file) return;
    setBusy(true);
    setError(null);
    try {
      const photo = await uploadPhoto(file);
      onChange(photo.id);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : photoError(cause));
    } finally {
      setBusy(false);
      if (input.current) input.current.value = "";
    }
  };

  return (
    <div {...stylex.props(styles.field)}>
      <div {...stylex.props(styles.frame)} aria-busy={busy}>
        {photoKey ? (
          <img
            src={photoUrl(photoKey, "card")}
            alt={copy.photos.alt(title || copy.editor.title.text).text}
            {...stylex.props(styles.image)}
          />
        ) : (
          <Mark size={40} />
        )}
      </div>
      <div {...stylex.props(styles.controls)}>
        <input
          ref={input}
          id={id}
          type="file"
          accept={PHOTO_ACCEPT}
          onChange={(e) => void pick(e.target.files?.[0])}
          {...stylex.props(styles.file)}
        />
        <Button variant="secondary" disabled={busy} onClick={() => input.current?.click()}>
          {busy
            ? copy.photos.uploading.text
            : photoKey
              ? copy.photos.replace.text
              : copy.photos.add.text}
        </Button>
        {photoKey && !busy ? (
          <Button variant="ghost" onClick={() => onChange(null)}>
            {copy.photos.remove.text}
          </Button>
        ) : null}
        <p role="status" {...stylex.props(styles.message)}>
          {busy ? copy.photos.uploading.text : (error ?? "")}
        </p>
      </div>
    </div>
  );
}

const styles = stylex.create({
  field: { display: "flex", flexWrap: "wrap", alignItems: "center", gap: 16 },
  frame: {
    display: "grid",
    placeItems: "center",
    width: 160,
    aspectRatio: "4 / 3",
    overflow: "hidden",
    borderRadius: 12,
    backgroundColor: `color-mix(in srgb, ${colors.magic} 10%, ${colors.crust})`,
  },
  image: { width: "100%", height: "100%", objectFit: "cover" },
  controls: { display: "flex", flexWrap: "wrap", alignItems: "center", gap: 8 },
  // Visually hidden; the button opens it and it stays reachable for tests.
  file: {
    position: "absolute",
    width: 1,
    height: 1,
    overflow: "hidden",
    clipPath: "inset(50%)",
  },
  message: { flexBasis: "100%", margin: 0, fontSize: 13, color: colors.subtext, minHeight: 18 },
});
