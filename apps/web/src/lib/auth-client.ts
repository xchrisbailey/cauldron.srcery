import { createAuthClient } from "better-auth/react";

export const authClient = createAuthClient({ basePath: "/v1/auth" });

/** Better Auth reports failures as `{ error: { code, message } }`; pull the code out. */
export const errorCode = (error: unknown): string | undefined =>
  typeof error === "object" && error !== null && "code" in error && typeof error.code === "string"
    ? error.code
    : undefined;
