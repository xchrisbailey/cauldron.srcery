import * as stylex from "@stylexjs/stylex";
import { createLink, type LinkComponent } from "@tanstack/react-router";
import { type ComponentProps, forwardRef } from "react";
import { button, type ButtonVariant, focusRing } from "./controls";

export function Button({
  variant = "primary",
  type = "button",
  ...props
}: ComponentProps<"button"> & { variant?: ButtonVariant }) {
  return (
    <button
      type={type}
      {...props}
      {...stylex.props(button.base, button[variant], focusRing.ring)}
    />
  );
}

/** A square button holding only an icon; `label` is its accessible name and tooltip. */
export function IconButton({
  label,
  ...props
}: Omit<ComponentProps<"button">, "aria-label"> & { label: string }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      {...props}
      {...stylex.props(button.base, button.ghost, button.icon, focusRing.ring)}
    />
  );
}

const ButtonAnchor = forwardRef<
  HTMLAnchorElement,
  ComponentProps<"a"> & { variant?: ButtonVariant }
>(function ButtonAnchor({ variant = "primary", ...props }, ref) {
  return <a ref={ref} {...props} {...stylex.props(button.base, button[variant], focusRing.ring)} />;
});

/** A router link that looks like a button. */
export const ButtonLink: LinkComponent<typeof ButtonAnchor> = createLink(ButtonAnchor);

const IconAnchor = forwardRef<
  HTMLAnchorElement,
  Omit<ComponentProps<"a">, "aria-label"> & { label: string }
>(function IconAnchor({ label, ...props }, ref) {
  return (
    <a
      ref={ref}
      aria-label={label}
      title={label}
      {...props}
      {...stylex.props(button.base, button.ghost, button.icon, focusRing.ring)}
    />
  );
});

/** A router link that looks like an `IconButton`; `label` is its accessible name and tooltip. */
export const IconButtonLink: LinkComponent<typeof IconAnchor> = createLink(IconAnchor);
