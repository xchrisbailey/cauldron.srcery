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
const FORWARDING = [
  "forwarded",
  "x-forwarded-for",
  "x-forwarded-host",
  "x-forwarded-proto",
  "x-real-ip",
];

/** Headers for the upstream API request: no hop-by-hop headers, and an X-Forwarded-For we set ourselves. */
export const forwardHeaders = (incoming: Headers, peer: string | undefined, trust: boolean) => {
  const headers = new Headers(incoming);
  for (const name of HOP_BY_HOP) headers.delete(name);
  const forwardedFor = trust ? incoming.get("x-forwarded-for") : null;
  for (const name of FORWARDING) headers.delete(name);
  const chain = [forwardedFor, peer].filter(Boolean).join(", ");
  if (chain) headers.set("x-forwarded-for", chain);
  return headers;
};
