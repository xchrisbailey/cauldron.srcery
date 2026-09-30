import * as stylex from "@stylexjs/stylex";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { callApi } from "../lib/api";
import { authClient } from "../lib/auth-client";
import { colors, fonts } from "../styles/tokens.stylex";

export const Route = createFileRoute("/")({ component: Home });

function Home() {
  const queryClient = useQueryClient();
  const health = useQuery({ queryKey: ["health"], queryFn: () => callApi((c) => c.health()) });
  const me = useQuery({
    queryKey: ["me"],
    queryFn: () => callApi((c) => c.account.me()),
    retry: false,
  });
  const [email, setEmail] = useState("ada@example.com");
  const [password, setPassword] = useState("correct-horse-1");
  const [error, setError] = useState<string | null>(null);

  const refresh = () => queryClient.resetQueries({ queryKey: ["me"] });
  const signIn = async (mode: "up" | "in") => {
    setError(null);
    const res =
      mode === "up"
        ? await authClient.signUp.email({ email, password, name: email.split("@")[0] ?? email })
        : await authClient.signIn.email({ email, password });
    if (res.error) setError(res.error.message ?? "Couldn't sign in.");
    await refresh();
  };

  return (
    <main {...stylex.props(styles.main)}>
      <h1 {...stylex.props(styles.title)}>Cauldron spike</h1>
      <p>
        API health: <span {...stylex.props(styles.mono)}>{health.data?.status ?? "…"}</span>
      </p>
      {me.data ? (
        <section {...stylex.props(styles.card)}>
          <p data-testid="signed-in">
            Signed in as <strong>{me.data.name}</strong>{" "}
            <span {...stylex.props(styles.mono)}>{me.data.email}</span>
          </p>
          <button
            {...stylex.props(styles.button)}
            onClick={() => authClient.signOut().then(refresh)}
          >
            Sign out
          </button>
        </section>
      ) : (
        <section {...stylex.props(styles.card)}>
          <p data-testid="signed-out">Not signed in.</p>
          <input
            {...stylex.props(styles.input)}
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
          <input
            {...stylex.props(styles.input)}
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
          <div {...stylex.props(styles.row)}>
            <button {...stylex.props(styles.button)} onClick={() => signIn("up")}>
              Sign up
            </button>
            <button {...stylex.props(styles.button)} onClick={() => signIn("in")}>
              Sign in
            </button>
            <button
              {...stylex.props(styles.button, styles.secondary)}
              onClick={() => authClient.signIn.social({ provider: "dev", callbackURL: "/" })}
            >
              Sign in with dev OIDC
            </button>
          </div>
          {error && <p {...stylex.props(styles.error)}>{error}</p>}
        </section>
      )}
    </main>
  );
}

const styles = stylex.create({
  main: { maxWidth: 560, marginInline: "auto", padding: 32 },
  title: { fontSize: 34, fontWeight: 700, letterSpacing: "-0.025em", color: colors.magic },
  mono: { fontFamily: fonts.mono, color: colors.fresh },
  card: {
    display: "flex",
    flexDirection: "column",
    gap: 12,
    padding: 20,
    borderRadius: 12,
    backgroundColor: colors.mantle,
  },
  row: { display: "flex", gap: 8, flexWrap: "wrap" },
  input: {
    padding: 8,
    borderRadius: 8,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
    backgroundColor: colors.base,
    color: colors.ink,
    fontFamily: fonts.ui,
  },
  button: {
    paddingBlock: 8,
    paddingInline: 14,
    borderRadius: 8,
    borderWidth: 0,
    cursor: "pointer",
    fontWeight: 500,
    backgroundColor: colors.magic,
    color: colors.base,
  },
  secondary: { backgroundColor: colors.surface0, color: colors.ink },
  error: { color: colors.heat },
});
