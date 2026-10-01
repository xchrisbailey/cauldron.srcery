import { authErrorMessage, copy, NewPasswordInput } from "@cauldron/shared";
import { useForm } from "@tanstack/react-form";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Schema } from "effect";
import { useState } from "react";
import { AuthCard, Button, FormMessage, Stack, TextField, TextLink } from "../../components/ui";
import { authClient, errorCode } from "../../lib/auth-client";

const Search = Schema.toStandardSchemaV1(
  Schema.Struct({ token: Schema.optional(Schema.String), error: Schema.optional(Schema.String) }),
);

export const Route = createFileRoute("/_public/reset-password")({
  validateSearch: Search,
  component: ResetPassword,
});

function ResetPassword() {
  const { token, error: linkError } = Route.useSearch();
  const navigate = useNavigate();
  const [error, setError] = useState<string | null>(null);
  const form = useForm({
    defaultValues: { password: "" },
    validators: { onSubmit: Schema.toStandardSchemaV1(NewPasswordInput) },
    onSubmit: async ({ value }) => {
      setError(null);
      const res = await authClient.resetPassword({
        newPassword: value.password,
        token: token ?? "",
      });
      if (res.error) return setError(authErrorMessage(errorCode(res.error)));
      await navigate({ to: "/sign-in", search: { reset: 1 } });
    },
  });

  if (!token || linkError) {
    return (
      <AuthCard title={copy.auth.chooseNewPassword.text}>
        <FormMessage tone="error">{copy.auth.linkExpired.text}</FormMessage>
        <TextLink to="/forgot-password">{copy.auth.forgotPassword.text}</TextLink>
      </AuthCard>
    );
  }

  return (
    <AuthCard title={copy.auth.chooseNewPassword.text}>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          void form.handleSubmit();
        }}
        noValidate
      >
        <Stack>
          <form.Field name="password">
            {(field) => (
              <TextField
                field={field}
                label={copy.auth.newPassword.text}
                type="password"
                autoComplete="new-password"
              />
            )}
          </form.Field>
          {error ? <FormMessage tone="error">{error}</FormMessage> : null}
          <form.Subscribe selector={(s) => s.isSubmitting}>
            {(submitting) => (
              <Button type="submit" disabled={submitting}>
                {copy.auth.chooseNewPassword.text}
              </Button>
            )}
          </form.Subscribe>
        </Stack>
      </form>
    </AuthCard>
  );
}
