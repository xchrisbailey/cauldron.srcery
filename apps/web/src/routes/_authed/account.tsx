import { authErrorMessage, copy, DeleteAccountInput } from "@cauldron/shared";
import { useForm } from "@tanstack/react-form";
import { useQueryClient } from "@tanstack/react-query";
import { createFileRoute, useNavigate, useRouter } from "@tanstack/react-router";
import { Schema } from "effect";
import { useState } from "react";
import { AuthCard, Button, FormMessage, Stack, TextField } from "../../components/ui";
import { authClient, errorCode } from "../../lib/auth-client";

export const Route = createFileRoute("/_authed/account")({ component: Account });

function Account() {
  const { session } = Route.useRouteContext();
  const navigate = useNavigate();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const leave = async () => {
    queryClient.clear();
    await router.invalidate();
    await navigate({ to: "/sign-in" });
  };

  const form = useForm({
    defaultValues: { password: "" },
    validators: { onSubmit: Schema.toStandardSchemaV1(DeleteAccountInput) },
    onSubmit: async ({ value }) => {
      setError(null);
      const res = await authClient.deleteUser({ password: value.password });
      if (res.error) return setError(authErrorMessage(errorCode(res.error)));
      await leave();
    },
  });

  return (
    <AuthCard title={copy.auth.account.text}>
      <p>
        {copy.auth.signedInAs.text} <strong>{session.user.email}</strong>
      </p>
      <Button variant="secondary" onClick={() => authClient.signOut().then(leave)}>
        {copy.auth.signOut.text}
      </Button>
      {confirming ? (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            void form.handleSubmit();
          }}
          noValidate
        >
          <Stack>
            <FormMessage tone="error">{copy.auth.deleteAccountConfirm.text}</FormMessage>
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
            <Button type="submit" variant="danger">
              {copy.auth.deleteAccount.text}
            </Button>
          </Stack>
        </form>
      ) : (
        <Button variant="danger" onClick={() => setConfirming(true)}>
          {copy.auth.deleteAccount.text}
        </Button>
      )}
    </AuthCard>
  );
}
