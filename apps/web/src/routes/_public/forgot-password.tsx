import { copy, EmailInput } from "@cauldron/shared";
import { useForm } from "@tanstack/react-form";
import { createFileRoute } from "@tanstack/react-router";
import { Schema } from "effect";
import { useState } from "react";
import { AuthCard, Button, FormMessage, Stack, TextField, TextLink } from "../../components/ui";
import { authClient } from "../../lib/auth-client";
import { pageTitle } from "../../lib/page-title";

export const Route = createFileRoute("/_public/forgot-password")({
  head: () => pageTitle(copy.pageTitles.forgotPassword),
  component: ForgotPassword,
});

function ForgotPassword() {
  const [sent, setSent] = useState(false);
  const form = useForm({
    defaultValues: { email: "" },
    validators: { onSubmit: Schema.toStandardSchemaV1(EmailInput) },
    onSubmit: async ({ value }) => {
      // Same answer whether or not the account exists.
      await authClient.requestPasswordReset({ email: value.email, redirectTo: "/reset-password" });
      setSent(true);
    },
  });

  return (
    <AuthCard title={copy.auth.forgotPasswordTitle.text}>
      {sent ? (
        <FormMessage tone="info">{copy.auth.resetLinkSent.text}</FormMessage>
      ) : (
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
            <form.Subscribe selector={(s) => s.isSubmitting}>
              {(submitting) => (
                <Button type="submit" disabled={submitting}>
                  {copy.auth.sendResetLink.text}
                </Button>
              )}
            </form.Subscribe>
          </Stack>
        </form>
      )}
      <TextLink to="/sign-in">{copy.auth.backToSignIn.text}</TextLink>
    </AuthCard>
  );
}
