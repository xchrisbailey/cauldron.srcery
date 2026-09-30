import { copy, SignInInput, authErrorMessage } from "@cauldron/shared";
import { useForm } from "@tanstack/react-form";
import { createFileRoute, redirect, useNavigate } from "@tanstack/react-router";
import { Schema } from "effect";
import { SearchFlag } from "../lib/search";
import { useState } from "react";
import { SocialSignIn } from "../components/SocialSignIn";
import { AuthCard, Button, FormMessage, Stack, TextField, TextLink } from "../components/ui";
import { authClient, errorCode } from "../lib/auth-client";
import { getSession } from "../lib/session";

const Search = Schema.toStandardSchemaV1(
  Schema.Struct({
    redirect: Schema.optional(Schema.String),
    verified: SearchFlag,
    reset: SearchFlag,
  }),
);

// Only same-site paths, so a crafted link can't bounce people to another site.
export const safeRedirect = (to: string | undefined) =>
  to && to.startsWith("/") && !to.startsWith("//") && !to.startsWith("/\\") ? to : "/";

export const Route = createFileRoute("/sign-in")({
  validateSearch: Search,
  beforeLoad: async ({ search }) => {
    if (await getSession()) throw redirect({ href: safeRedirect(search.redirect) });
  },
  component: SignIn,
});

function SignIn() {
  const search = Route.useSearch();
  const navigate = useNavigate();
  const [error, setError] = useState<string | null>(null);
  const to = safeRedirect(search.redirect);
  const form = useForm({
    defaultValues: { email: "", password: "" },
    validators: { onSubmit: Schema.toStandardSchemaV1(SignInInput) },
    onSubmit: async ({ value }) => {
      setError(null);
      const res = await authClient.signIn.email(value);
      if (res.error) return setError(authErrorMessage(errorCode(res.error)));
      await navigate({ href: to });
    },
  });

  return (
    <AuthCard title={copy.auth.signInTitle.text}>
      {search.reset ? (
        <FormMessage tone="info">{copy.auth.passwordUpdated.text}</FormMessage>
      ) : null}
      <form
        onSubmit={(e) => {
          e.preventDefault();
          void form.handleSubmit();
        }}
        noValidate
      >
        <Stack>
          <form.Field name="email">
            {(field) => (
              <TextField
                field={field}
                label={copy.auth.email.text}
                type="email"
                autoComplete="email"
              />
            )}
          </form.Field>
          <form.Field name="password">
            {(field) => (
              <TextField
                field={field}
                label={copy.auth.password.text}
                type="password"
                autoComplete="current-password"
              />
            )}
          </form.Field>
          {error ? <FormMessage tone="error">{error}</FormMessage> : null}
          <form.Subscribe selector={(s) => s.isSubmitting}>
            {(submitting) => (
              <Button type="submit" disabled={submitting}>
                {copy.auth.signIn.text}
              </Button>
            )}
          </form.Subscribe>
        </Stack>
      </form>
      <SocialSignIn callbackURL={to} />
      <Stack>
        <TextLink to="/forgot-password">{copy.auth.forgotPassword.text}</TextLink>
        <TextLink to="/sign-up">{copy.auth.noAccount.text}</TextLink>
      </Stack>
    </AuthCard>
  );
}
