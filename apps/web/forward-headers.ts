// Headers for requests the production server proxies to the API.

const HOP_BY_HOP = [
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade",
  "host",
];
export const CLIENT_IP_HEADER = "x-client-ip";
const FORWARDING = [
  "forwarded",
  "x-forwarded-for",
  "x-forwarded-host",
  "x-forwarded-proto",
  "x-real-ip",
];

/**
 * Headers for the upstream API request: no hop-by-hop headers, and forwarding
 * headers we set ourselves. `x-client-ip` is the one the API trusts (when its
 * TRUST_PROXY is on); it is always overwritten, never passed through.
 *
 * The client address is the peer's, or, with `trust` (a load balancer we
 * control sits in front), the rightmost X-Forwarded-For entry: the one that
 * balancer appended. Entries to its left were supplied by the client.
 */
export const forwardHeaders = (incoming: Headers, peer: string | undefined, trust: boolean) => {
  const headers = new Headers(incoming);
  for (const name of HOP_BY_HOP) headers.delete(name);
  const forwardedFor = trust ? incoming.get("x-forwarded-for") : null;
  for (const name of [...FORWARDING, CLIENT_IP_HEADER]) headers.delete(name);
  const rightmost = forwardedFor?.split(",").at(-1)?.trim();
  const clientIp = rightmost || peer;
  if (clientIp) headers.set(CLIENT_IP_HEADER, clientIp);
  const chain = [forwardedFor, peer].filter(Boolean).join(", ");
  if (chain) headers.set("x-forwarded-for", chain);
  return headers;
};
