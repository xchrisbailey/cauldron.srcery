import { copy } from "@cauldron/shared";
import { useQuery } from "@tanstack/react-query";
import { authClient } from "../lib/auth-client";
import { signInOptionsQuery } from "../lib/sign-in-options";
import { Button, Divider, Stack } from "./ui";

/** Google, Apple (and the dev provider locally), for whichever the API has configured. */
export function SocialSignIn({ callbackURL }: { callbackURL: string }) {
  const options = useQuery(signInOptionsQuery);
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
          onClick={() =>
            // A refused sign-in (sign-up closed, say) comes back to our page, not Better Auth's.
            authClient.signIn.social({ provider: p.id, callbackURL, errorCallbackURL: "/sign-in" })
          }
        >
          {p.label}
        </Button>
      ))}
    </Stack>
  );
}
