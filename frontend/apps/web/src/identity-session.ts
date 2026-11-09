import { getPublicRuntimeConfig } from "./runtime-config";
import { setAccessToken } from "./payment-flow";

const prefix = "orderprocessing.oidc";
export interface SessionBootstrap { accessToken: string | null; authRedirectInitiated: boolean }
export interface IdentitySession {
  bootstrap(): Promise<SessionBootstrap>;
  signIn(): Promise<void>;
  signOut(): Promise<void>;
}

export function clearApplicationSession() {
  for (const storage of [localStorage, sessionStorage]) {
    for (const key of Object.keys(storage)) {
      if (key.startsWith("orderprocessing.") || key.startsWith("pending-payment:")) storage.removeItem(key);
    }
  }
  setAccessToken(null);
  // Other tabs listen for this event; it contains no identity material.
  localStorage.setItem("orderprocessing.logout", String(Date.now()));
}

export function requestedEntryTenant(): string | null {
  const current = new URL(location.href);
  const saved = current.searchParams.has("code") ? sessionStorage.getItem(`${prefix}.returnUrl`) : null;
  return new URL(saved ?? current.href).searchParams.get("tenantCode")?.trim() || null;
}

function randomValue(length: number) {
  return encode(crypto.getRandomValues(new Uint8Array(length)));
}
function encode(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

class KeycloakSession implements IdentitySession {
  async bootstrap(): Promise<SessionBootstrap> {
    const config = getPublicRuntimeConfig();
    const currentUrl = new URL(location.href);
    if (currentUrl.searchParams.has("error")) throw new Error("Identity provider rejected sign-in. Please sign in again.");
    const code = currentUrl.searchParams.get("code");
    if (code) {
      const state = sessionStorage.getItem(`${prefix}.state`);
      const verifier = sessionStorage.getItem(`${prefix}.verifier`);
      if (!state || state !== currentUrl.searchParams.get("state") || !verifier) throw new Error("OIDC callback state is invalid.");
      const response = await fetch(`${config.authority}/protocol/openid-connect/token`, {
        method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ grant_type: "authorization_code", client_id: config.clientId, code,
          code_verifier: verifier, redirect_uri: config.redirectUri }).toString()
      });
      if (!response.ok) throw new Error(`Sign-in token exchange failed with HTTP ${response.status}.`);
      const token = await response.json() as { access_token?: string; id_token?: string; expires_in?: number };
      if (!token.access_token) throw new Error("Sign-in returned no API access token.");
      if (token.id_token) sessionStorage.setItem(`${prefix}.idToken`, token.id_token);
      const returnUrl = sessionStorage.getItem(`${prefix}.returnUrl`) ?? `${location.origin}/customers`;
      if (new URL(returnUrl).origin !== location.origin) throw new Error("Invalid login return origin.");
      for (const key of ["state", "verifier", "returnUrl"]) sessionStorage.removeItem(`${prefix}.${key}`);
      history.replaceState({}, document.title, returnUrl);
      remember(token.access_token, Date.now() + (token.expires_in ?? 300) * 1000);
      return { accessToken: token.access_token, authRedirectInitiated: false };
    }
    const token = localStorage.getItem("orderprocessing.accessToken");
    if (token && Number(localStorage.getItem(`${prefix}.expiresAt`)) > Date.now() + 30000)
      return { accessToken: token, authRedirectInitiated: false };
    await this.startLogin(false);
    return { accessToken: null, authRedirectInitiated: true };
  }
  async signIn() { await this.startLogin(true); }
  private async startLogin(explicit: boolean) {
    const config = getPublicRuntimeConfig();
    const verifier = randomValue(64);
    const state = randomValue(32);
    const challenge = encode(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))));
    sessionStorage.setItem(`${prefix}.verifier`, verifier);
    sessionStorage.setItem(`${prefix}.state`, state);
    sessionStorage.setItem(`${prefix}.returnUrl`, location.pathname === "/signed-out" ? `${location.origin}/customers` : location.href);
    const url = new URL(`${config.authority}/protocol/openid-connect/auth`);
    url.search = new URLSearchParams({ client_id: config.clientId, response_type: "code", scope: "openid profile email",
      redirect_uri: config.redirectUri, state, code_challenge: challenge, code_challenge_method: "S256",
      ...(explicit ? { prompt: "login" } : {}) }).toString();
    location.assign(url.href);
  }
  async signOut() {
    const config = getPublicRuntimeConfig();
    const hint = sessionStorage.getItem(`${prefix}.idToken`);
    clearApplicationSession();
    // Confirm the provider is reachable before navigating away. No token is sent to this endpoint.
    const discovery = await fetch(`${config.authority}/.well-known/openid-configuration`);
    if (!discovery.ok) throw new Error("Local access cleared; provider logout could not be confirmed.");
    const url = new URL(`${config.authority}/protocol/openid-connect/logout`);
    url.search = new URLSearchParams({ client_id: config.clientId, post_logout_redirect_uri: config.postLogoutRedirectUri,
      ...(hint ? { id_token_hint: hint } : {}) }).toString();
    location.assign(url.href);
  }
}

class EntraSession implements IdentitySession {
  private client?: import("@azure/msal-browser").PublicClientApplication;
  private async getClient() {
    if (!this.client) {
      const { PublicClientApplication } = await import("@azure/msal-browser");
      const config = getPublicRuntimeConfig();
      this.client = new PublicClientApplication({ auth: { clientId: config.clientId, authority: config.authority,
        redirectUri: config.redirectUri, postLogoutRedirectUri: config.postLogoutRedirectUri }, cache: { cacheLocation: "sessionStorage" } });
      await this.client.initialize();
    }
    return this.client;
  }
  async bootstrap(): Promise<SessionBootstrap> {
    const client = await this.getClient();
    const result = await client.handleRedirectPromise({ navigateToLoginRequestUrl: false });
    const accounts = client.getAllAccounts();
    const account = result?.account ?? client.getActiveAccount() ?? (accounts.length === 1 ? accounts[0] : null);
    if (!account) { await this.signIn(); return { accessToken: null, authRedirectInitiated: true }; }
    client.setActiveAccount(account);
    try {
      const token = await client.acquireTokenSilent({ account, scopes: getPublicRuntimeConfig().scopes });
      remember(token.accessToken, token.expiresOn?.getTime() ?? Date.now() + 300000);
      const returnUrl = sessionStorage.getItem(`${prefix}.returnUrl`);
      if (returnUrl && new URL(returnUrl).origin === location.origin) history.replaceState({}, document.title, returnUrl);
      sessionStorage.removeItem(`${prefix}.returnUrl`);
      return { accessToken: token.accessToken, authRedirectInitiated: false };
    } catch { throw new Error("Your session requires sign-in. Please sign in again."); }
  }
  async signIn() {
    const client = await this.getClient();
    sessionStorage.setItem(`${prefix}.returnUrl`, location.pathname === "/signed-out" ? `${location.origin}/customers` : location.href);
    await client.loginRedirect({ scopes: getPublicRuntimeConfig().scopes, prompt: "select_account" });
  }
  async signOut() {
    const client = await this.getClient();
    const account = client.getActiveAccount();
    clearApplicationSession();
    await client.logoutRedirect({ account, postLogoutRedirectUri: getPublicRuntimeConfig().postLogoutRedirectUri });
  }
}

function remember(token: string, expiresAt: number) {
  localStorage.setItem("orderprocessing.accessToken", token);
  localStorage.setItem(`${prefix}.expiresAt`, String(expiresAt));
  localStorage.removeItem("orderprocessing.logout");
}

const local = new KeycloakSession();
const entra = new EntraSession();
const disabled: IdentitySession = { bootstrap: async () => ({ accessToken: null, authRedirectInitiated: false }), signIn: async () => {}, signOut: async () => { clearApplicationSession(); } };
export function identitySession(): IdentitySession {
  return getPublicRuntimeConfig().mode === "Entra" ? entra : getPublicRuntimeConfig().mode === "KeycloakLocal" ? local : disabled;
}
