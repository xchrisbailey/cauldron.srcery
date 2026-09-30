import { copy, EmailInput, SignInInput, authErrorMessage } from "@cauldron/shared";
import { useForm } from "@tanstack/react-form";
import { createFileRoute, redirect, useNavigate } from "@tanstack/react-router";
import { Schema } from "effect";
import { SearchFlag } from "../lib/search";
import { safeRedirect } from "../lib/safe-redirect";
import { useState } from "react";
import { SocialSignIn } from "../components/SocialSignIn";
import { AuthCard, Button, FormMessage, Stack, TextField, TextLink } from "../components/ui";
import { authClient, errorCode } from "../lib/auth-client";
import { getSession } from "../lib/session";

const Search = Schema.toStandardSchemaV1(
  Schema.Struct({
    redirect: Schema.optional(Schema.String),
    reset: SearchFlag,
    // Better Auth sends a bad verification link here as `error=INVALID_TOKEN`.
    error: Schema.optional(Schema.String),
  }),
);

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
  const [resent, setResent] = useState(false);
  const [needsVerification, setNeedsVerification] = useState(false);
  const to = safeRedirect(search.redirect);
  const form = useForm({
    defaultValues: { email: "", password: "" },
    validators: { onSubmit: Schema.toStandardSchemaV1(SignInInput) },
    onSubmit: async ({ value }) => {
      setError(null);
      const res = await authClient.signIn.email(value);
      if (res.error) {
        const code = errorCode(res.error);
        setNeedsVerification(code === "EMAIL_NOT_VERIFIED");
        return setError(authErrorMessage(code));
      }
      await navigate({ href: to });
    },
  });

  const resend = async () => {
    const email = form.getFieldValue("email");
    setResent(false);
    if (!Schema.is(EmailInput)({ email })) return setError(copy.auth.invalidEmail.text);
    setError(null);
    const res = await authClient.sendVerificationEmail({ email, callbackURL: "/?verified=1" });
    if (res.error) return setError(authErrorMessage(errorCode(res.error)));
    setResent(true);
  };
  const showResend = Boolean(search.error) || needsVerification;

  return (
    <AuthCard title={copy.auth.signInTitle.text}>
      {search.error ? <FormMessage tone="error">{copy.auth.linkExpired.text}</FormMessage> : null}
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
          {resent ? <FormMessage tone="info">{copy.auth.checkEmail.text}</FormMessage> : null}
          <form.Subscribe selector={(s) => s.isSubmitting}>
            {(submitting) => (
              <Button type="submit" disabled={submitting}>
                {copy.auth.signIn.text}
              </Button>
            )}
          </form.Subscribe>
        </Stack>
      </form>
      {showResend ? (
        <Stack>
          <p>{copy.auth.resendVerificationFor.text}</p>
          <Button type="button" variant="secondary" onClick={() => void resend()}>
            {copy.auth.resendVerification.text}
          </Button>
        </Stack>
      ) : null}
      <SocialSignIn callbackURL={to} />
      <Stack>
        <TextLink to="/forgot-password">{copy.auth.forgotPassword.text}</TextLink>
        <TextLink to="/sign-up">{copy.auth.noAccount.text}</TextLink>
      </Stack>
    </AuthCard>
  );
}
