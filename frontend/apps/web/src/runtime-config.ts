export interface PublicRuntimeConfig {
  mode: "KeycloakLocal" | "Entra" | "Disabled";
  authority: string;
  clientId: string;
  scopes: string[];
  apiBaseUrl: string;
  redirectUri: string;
  postLogoutRedirectUri: string;
}

let current: PublicRuntimeConfig = { mode: "Disabled", authority: "", clientId: "", scopes: [], apiBaseUrl: "", redirectUri: "", postLogoutRedirectUri: "" };
export function getPublicRuntimeConfig() { return current; }
export function configurePublicRuntime(config: PublicRuntimeConfig) { current = config; }
export async function loadPublicRuntimeConfig() {
  const response = await fetch("/runtime-config.json", { cache: "no-store" });
  if (!response.ok || !response.headers.get("content-type")?.includes("application/json")) throw new Error("Public identity configuration is unavailable.");
  const config = await response.json() as PublicRuntimeConfig;
  if (!["Disabled", "KeycloakLocal", "Entra"].includes(config.mode)
      || (config.mode !== "Disabled" && (!config.authority || !config.clientId || new URL(config.redirectUri).origin !== location.origin)))
    throw new Error("Public identity configuration is invalid.");
  configurePublicRuntime(config);
}
