import { Option } from "effect";
import type { HttpServerRequest } from "effect/http";

/**
 * The one header the web proxy (apps/web/forward-headers.ts) always overwrites
 * with the client address it worked out itself.
 */
export const CLIENT_IP_HEADER = "x-client-ip";

/**
 * The client's address. With `trustProxy` (the API sits behind our web proxy)
 * it is the proxy's `x-client-ip`; otherwise the socket's remote address. No
 * other header is ever read, so a client can't choose its own rate-limit key.
 */
export const resolveClientIp = (
  request: HttpServerRequest.HttpServerRequest,
  trustProxy: boolean,
): string => {
  if (trustProxy) {
    const header = request.headers[CLIENT_IP_HEADER]?.trim();
    if (header) return header;
  }
  return Option.getOrElse(request.remoteAddress, () => "unknown");
};
