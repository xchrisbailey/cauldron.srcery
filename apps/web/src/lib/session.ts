import { createServerFn } from "@tanstack/react-start";
import { getRequestHeaders } from "@tanstack/react-start/server";

export interface Session {
  readonly user: { readonly id: string; readonly name: string; readonly email: string };
}

const apiOrigin = () => process.env.API_ORIGIN ?? "http://localhost:3001";

// Runs on the web server for SSR and client navigations alike, forwarding the
// visitor's cookie to the API, so route guards see the same session either way.
export const getSession = createServerFn({ method: "GET" }).handler(
  async (): Promise<Session | null> => {
    const cookie = getRequestHeaders().get("cookie");
    if (!cookie) return null;
    const res = await fetch(`${apiOrigin()}/v1/auth/get-session`, { headers: { cookie } });
    if (!res.ok) return null;
    const body = (await res.json()) as Session | null;
    return body?.user
      ? { user: { id: body.user.id, name: body.user.name, email: body.user.email } }
      : null;
  },
);
