// Public allowlist only. Never serialize process.env or backend credentials.
export function createPublicRuntimeConfig(env) {
  const mode = env.IDENTITY_MODE;
  if (!["KeycloakLocal", "Entra", "Disabled"].includes(mode)) throw new Error("IDENTITY_MODE must explicitly select KeycloakLocal, Entra or Disabled.");
  const environment = env.APP_ENVIRONMENT ?? "local";
  const cloud = !["local", "docker"].includes(environment);
  if (cloud && mode !== "Entra") throw new Error("Cloud UI requires Entra identity; anonymous or local identity is not allowed.");
  const origin = env.PUBLIC_WEB_ORIGIN;
  if (!origin) throw new Error("PUBLIC_WEB_ORIGIN is required.");
  const web = new URL(origin);
  if (web.origin !== origin || (cloud && (web.protocol !== "https:" || web.hostname === "localhost" || web.hostname === "127.0.0.1"))) throw new Error("Invalid public web origin.");
  const authority = (env.PUBLIC_IDENTITY_AUTHORITY ?? "").replace(/\/$/, "");
  const clientId = env.PUBLIC_IDENTITY_CLIENT_ID ?? "";
  const scopes = (env.PUBLIC_IDENTITY_SCOPES ?? "").split(" ").filter(Boolean);
  if (mode !== "Disabled" && (!authority || !clientId)) throw new Error("Public identity authority and client ID are required.");
  if (mode !== "Disabled") {
    const issuer = new URL(authority);
    if (mode === "Entra" && (issuer.protocol !== "https:" || issuer.hostname !== "login.microsoftonline.com" || !/^\/[0-9a-f-]{36}\/v2\.0$/i.test(issuer.pathname) || scopes.length === 0)) throw new Error("Entra requires a directory-specific v2 authority and API scopes.");
    if (mode === "KeycloakLocal" && !["localhost", "127.0.0.1"].includes(issuer.hostname)) throw new Error("KeycloakLocal is restricted to local identity instances.");
  }
  return { mode, authority, clientId, scopes, apiBaseUrl: "", redirectUri: `${origin}/auth/callback`, postLogoutRedirectUri: `${origin}/signed-out` };
}
