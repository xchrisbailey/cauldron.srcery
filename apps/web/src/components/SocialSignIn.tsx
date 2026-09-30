import { copy } from "@cauldron/shared";
import { useQuery } from "@tanstack/react-query";
import { callApi } from "../lib/api";
import { authClient } from "../lib/auth-client";
import { Button, Divider, Stack } from "./ui";

/** Google, Apple (and the dev provider locally), for whichever the API has configured. */
export function SocialSignIn({ callbackURL }: { callbackURL: string }) {
  const options = useQuery({
    queryKey: ["sign-in-options"],
    queryFn: () => callApi((c) => c.signInOptions()),
    staleTime: Infinity,
  });
  const providers = [
    options.data?.google && { id: "google", label: copy.auth.signInWithGoogle.text },
    options.data?.apple && { id: "apple", label: copy.auth.signInWithApple.text },
    options.data?.dev && { id: "dev", label: copy.auth.signInWithDevOidc.text },
  ].filter((p): p is { id: string; label: string } => Boolean(p));
  if (providers.length === 0) return null;
  return (
    <Stack>
      <Divider label={copy.auth.or.text} />
      {providers.map((p) => (
        <Button
          key={p.id}
          type="button"
          variant="secondary"
          onClick={() => authClient.signIn.social({ provider: p.id, callbackURL })}
        >
          {p.label}
        </Button>
      ))}
    </Stack>
  );
}
