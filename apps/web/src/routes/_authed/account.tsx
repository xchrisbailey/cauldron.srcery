import { authErrorMessage, copy, DeleteAccountInput } from "@cauldron/shared";
import { useForm } from "@tanstack/react-form";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute, useNavigate, useRouter } from "@tanstack/react-router";
import { Schema } from "effect";
import { useState } from "react";
import { AuthCard, Button, FormMessage, Stack, TextField } from "../../components/ui";
import { authClient, errorCode } from "../../lib/auth-client";
import { pageTitle } from "../../lib/page-title";

export const Route = createFileRoute("/_authed/account")({
  head: () => pageTitle(copy.pageTitles.account),
  component: Account,
});

function Account() {
  const { session } = Route.useRouteContext();
  const navigate = useNavigate();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sessionExpired, setSessionExpired] = useState(false);
  // Accounts created through Google or Apple have no password to confirm with.
  const accounts = useQuery({
    queryKey: ["accounts"],
    queryFn: async () => {
      const res = await authClient.listAccounts();
      if (res.error) throw new Error(res.error.message);
      return res.data;
    },
  });
  const hasPassword = accounts.data?.some((a) => a.providerId === "credential") ?? true;

  const leave = async () => {
    queryClient.clear();
    await router.invalidate();
    await navigate({ to: "/sign-in" });
  };

  const form = useForm({
    defaultValues: { password: "" },
    validators: {
      onSubmit: Schema.toStandardSchemaV1(
        hasPassword ? DeleteAccountInput : Schema.Struct({ password: Schema.String }),
      ),
    },
    onSubmit: async ({ value }) => {
      setError(null);
      const res = await authClient.deleteUser(hasPassword ? { password: value.password } : {});
      if (res.error) {
        const code = errorCode(res.error);
        setSessionExpired(code === "SESSION_EXPIRED");
        return setError(authErrorMessage(code));
      }
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
            {hasPassword ? (
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
            ) : null}
            {error ? <FormMessage tone="error">{error}</FormMessage> : null}
            {sessionExpired ? (
              // Sign-in skips signed-in visitors, so end this session first.
              <Button
                type="button"
                variant="secondary"
                onClick={() =>
                  authClient
                    .signOut()
                    .then(() => queryClient.clear())
                    .then(() => router.invalidate())
                    .then(() => navigate({ to: "/sign-in", search: { redirect: "/account" } }))
                }
              >
                {copy.auth.signInAgain.text}
              </Button>
            ) : null}
            <Button type="submit" variant="danger">
              {copy.auth.deleteAccount.text}
            </Button>
          </Stack>
        </form>
      ) : (
        <Button variant="danger" disabled={accounts.isPending} onClick={() => setConfirming(true)}>
          {copy.auth.deleteAccount.text}
        </Button>
      )}
    </AuthCard>
  );
}
