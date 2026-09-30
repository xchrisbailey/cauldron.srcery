import { authErrorMessage, copy, SignUpInput } from "@cauldron/shared";
import { useForm } from "@tanstack/react-form";
import { createFileRoute, redirect } from "@tanstack/react-router";
import { Schema } from "effect";
import { useState } from "react";
import { SocialSignIn } from "../components/SocialSignIn";
import { AuthCard, Button, FormMessage, Stack, TextField, TextLink } from "../components/ui";
import { authClient, errorCode } from "../lib/auth-client";
import { getSession } from "../lib/session";

export const Route = createFileRoute("/sign-up")({
  beforeLoad: async () => {
    if (await getSession()) throw redirect({ to: "/" });
  },
  component: SignUp,
});

function SignUp() {
  const [error, setError] = useState<string | null>(null);
  const [sentTo, setSentTo] = useState<string | null>(null);
  const form = useForm({
    defaultValues: { name: "", email: "", password: "" },
    validators: { onSubmit: Schema.toStandardSchemaV1(SignUpInput) },
    onSubmit: async ({ value }) => {
      setError(null);
      // The verification link signs the user in and lands them on the home page.
      const res = await authClient.signUp.email({ ...value, callbackURL: "/?verified=1" });
      if (res.error) return setError(authErrorMessage(errorCode(res.error)));
      setSentTo(value.email);
    },
  });

  if (sentTo) {
    return (
      <AuthCard title={copy.auth.signUpTitle.text}>
        <FormMessage tone="info">{copy.auth.checkEmail.text}</FormMessage>
        <Button
          variant="secondary"
          onClick={() =>
            authClient.sendVerificationEmail({ email: sentTo, callbackURL: "/?verified=1" })
          }
        >
          {copy.auth.resendVerification.text}
        </Button>
        <TextLink to="/sign-in">{copy.auth.backToSignIn.text}</TextLink>
      </AuthCard>
    );
  }

  return (
    <AuthCard title={copy.auth.signUpTitle.text}>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          void form.handleSubmit();
        }}
        noValidate
      >
        <Stack>
          <form.Field name="name">
            {(field) => <TextField field={field} label={copy.auth.name.text} autoComplete="name" />}
          </form.Field>
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
                autoComplete="new-password"
              />
            )}
          </form.Field>
          {error ? <FormMessage tone="error">{error}</FormMessage> : null}
          <form.Subscribe selector={(s) => s.isSubmitting}>
            {(submitting) => (
              <Button type="submit" disabled={submitting}>
                {copy.auth.signUp.text}
              </Button>
            )}
          </form.Subscribe>
        </Stack>
      </form>
      <SocialSignIn callbackURL="/" />
      <TextLink to="/sign-in">{copy.auth.haveAccount.text}</TextLink>
    </AuthCard>
  );
}
