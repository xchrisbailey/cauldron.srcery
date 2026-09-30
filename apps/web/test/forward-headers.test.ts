import { describe, expect, it } from "vite-plus/test";
import { forwardHeaders } from "../forward-headers.ts";

describe("forwardHeaders", () => {
  const incoming = new Headers({
    cookie: "a=b",
    "x-forwarded-for": "6.6.6.6",
    "x-real-ip": "6.6.6.6",
    "x-client-ip": "6.6.6.6",
    forwarded: "for=6.6.6.6",
    connection: "keep-alive",
    host: "example.com",
  });

  it("replaces client-sent forwarding headers with the peer address", () => {
    const headers = forwardHeaders(incoming, "10.0.0.1", false);
    expect(headers.get("x-forwarded-for")).toBe("10.0.0.1");
    expect(headers.get("x-client-ip")).toBe("10.0.0.1");
    expect(headers.get("x-real-ip")).toBeNull();
    expect(headers.get("forwarded")).toBeNull();
    expect(headers.get("cookie")).toBe("a=b");
  });

  it("drops hop-by-hop headers", () => {
    const headers = forwardHeaders(incoming, "10.0.0.1", false);
    expect(headers.get("connection")).toBeNull();
    expect(headers.get("host")).toBeNull();
  });

  it("appends the peer to a trusted proxy's chain and takes its rightmost entry as the client", () => {
    const headers = forwardHeaders(
      new Headers({ "x-forwarded-for": "6.6.6.6, 9.9.9.9", "x-client-ip": "6.6.6.6" }),
      "10.0.0.1",
      true,
    );
    expect(headers.get("x-forwarded-for")).toBe("6.6.6.6, 9.9.9.9, 10.0.0.1");
    expect(headers.get("x-client-ip")).toBe("9.9.9.9");
  });

  it("falls back to the peer when a trusted proxy sent no chain, and overwrites x-client-ip", () => {
    const headers = forwardHeaders(new Headers({ "x-client-ip": "6.6.6.6" }), "10.0.0.1", true);
    expect(headers.get("x-client-ip")).toBe("10.0.0.1");
  });

  it("omits x-client-ip when there is no peer address", () => {
    expect(forwardHeaders(incoming, undefined, false).get("x-client-ip")).toBeNull();
  });
});
