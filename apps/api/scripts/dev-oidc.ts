// A throwaway OIDC provider for local dev and the spike, standing in for
// Google and Apple. Point the API at it with
// DEV_OAUTH_DISCOVERY_URL=http://localhost:9400/.well-known/openid-configuration
import { OAuth2Server } from "oauth2-mock-server";

const server = new OAuth2Server();
await server.issuer.keys.generate("RS256");
server.service.on("beforeTokenSigning", (token) => {
  token.payload.email = "oidc@example.com";
  token.payload.name = "Dev OIDC User";
  token.payload.email_verified = true;
});
server.service.on("beforeUserinfo", (res) => {
  res.body = {
    sub: "dev-oidc-user",
    email: "oidc@example.com",
    name: "Dev OIDC User",
    email_verified: true,
  };
});
await server.start(9400, "localhost");
console.log(`dev OIDC issuer at ${server.issuer.url}`);
