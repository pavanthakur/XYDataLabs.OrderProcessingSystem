import { useEffect, useMemo, useRef, useState } from "react";
import { BrowserRouter, Navigate, NavLink, Route, Routes } from "react-router-dom";
import {
  createOrderProcessingApiClient,
  type RuntimeConfiguration
} from "@xydatalabs/orderprocessing-api-sdk";
import { createTenantSession } from "@xydatalabs/orderprocessing-tenant-session";
import { CustomerDetailPage } from "./pages/CustomerDetailPage";
import { CustomerDirectoryPage } from "./pages/CustomerDirectoryPage";
import { OrderCreatePage } from "./pages/OrderCreatePage";
import { OrderDetailPage } from "./pages/OrderDetailPage";
import { PaymentCallbackPage } from "./pages/PaymentCallbackPage";
import { PaymentPage } from "./pages/PaymentPage";
import { setAccessToken } from "./payment-flow";

const tenantSession = createTenantSession();
const configuredApiBaseUrl = (import.meta.env.VITE_ORDERPROCESSING_API_BASE_URL ?? "").trim();
const configuredKeycloakAuthority = (import.meta.env.VITE_KEYCLOAK_AUTHORITY ?? "").trim().replace(/\/$/, "");
const configuredKeycloakRealm = (import.meta.env.VITE_KEYCLOAK_REALM ?? "").trim();
const configuredKeycloakClientId = (import.meta.env.VITE_KEYCLOAK_CLIENT_ID ?? "").trim();
const oidcStoragePrefix = "orderprocessing.oidc";
const apiClient = createOrderProcessingApiClient({
  baseUrl: configuredApiBaseUrl.length > 0 ? configuredApiBaseUrl.replace(/\/$/, "") : "",
  getTenantCode: () => tenantSession.getActiveTenantCode(),
  getTenantHeaderName: () => tenantSession.getTenantHeaderName(),
  getAccessToken: () => localStorage.getItem("orderprocessing.accessToken")
});

type LoadState = "idle" | "loading" | "ready" | "error";
type BootstrapTokenResult = {
  accessToken: string | null;
  authRedirectInitiated: boolean;
};

export default function App() {
  const [runtimeConfiguration, setRuntimeConfiguration] = useState<RuntimeConfiguration | null>(null);
  const [activeTenantCode, setActiveTenantCode] = useState("");
  const [bootstrapState, setBootstrapState] = useState<LoadState>("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const bootstrapStartedRef = useRef(false);
  const requestedBootstrapTenantCode = useMemo(
    () => resolveRequestedBootstrapTenantCode(window.location.pathname, window.location.search),
    []
  );

  useEffect(() => {
    if (bootstrapStartedRef.current) {
      return;
    }

    bootstrapStartedRef.current = true;
    let isCancelled = false;

    async function bootstrapShell() {
      setBootstrapState("loading");
      setErrorMessage(null);

      try {
        const bootstrapTokenResult = await bootstrapLocalAccessToken();

        if (isCancelled) {
          return;
        }

        if (bootstrapTokenResult.authRedirectInitiated) {
          return;
        }

        setAccessToken(bootstrapTokenResult.accessToken);
        if (bootstrapTokenResult.accessToken) {
          localStorage.setItem("orderprocessing.accessToken", bootstrapTokenResult.accessToken);
        }
        const bootstrap = await apiClient.getRuntimeConfiguration(requestedBootstrapTenantCode ?? undefined);
        const sessionState = tenantSession.initialize(bootstrap, requestedBootstrapTenantCode);
        setRuntimeConfiguration(bootstrap);
        setActiveTenantCode(sessionState.activeTenantCode);
        setBootstrapState("ready");
      } catch (error) {
        if (isCancelled) {
          return;
        }

        setBootstrapState("error");
        setErrorMessage(error instanceof Error ? error.message : "Unable to bootstrap runtime configuration.");
      }
    }

    void bootstrapShell();

    return () => {
      isCancelled = true;
    };
  }, [requestedBootstrapTenantCode]);

  function handleTenantChange(nextTenantCode: string) {
    const sessionState = tenantSession.setActiveTenantCode(nextTenantCode);
    setActiveTenantCode(sessionState.activeTenantCode);
  }

  return (
    <BrowserRouter>
      <main className="app-shell">
        {errorMessage ? <p className="error-banner">{errorMessage}</p> : null}

        <section className="shell-header panel">
          <div className="shell-copy">
            <p className="eyebrow">Order Processing Portal</p>
            <h1>Customers, orders, and card payments</h1>
            <p className="shell-lede">
              All actions are scoped to the selected tenant, so agents can move from customer lookup to payment collection without leaving the same browser workspace.
            </p>
            <p className="shell-meta">
              {bootstrapState === "ready"
                ? `Active tenant: ${activeTenantCode}`
                : bootstrapState === "loading"
                  ? "Preparing tenant session..."
                  : "Tenant session needs attention."}
            </p>
          </div>

          <div className="shell-actions shell-actions-compact">
            <nav className="shell-nav" aria-label="Primary">
              <NavLink
                to="/customers"
                className={({ isActive }) => (isActive ? "nav-link nav-link-active" : "nav-link")}
              >
                Customers
              </NavLink>
              <NavLink
                to="/payments/new"
                className={({ isActive }) => (isActive ? "nav-link nav-link-active" : "nav-link")}
              >
                Payments
              </NavLink>
            </nav>

            <label className="tenant-picker">
              <span>Tenant</span>
              <select
                value={activeTenantCode}
                onChange={(event) => handleTenantChange(event.target.value)}
                disabled={!runtimeConfiguration}
              >
                {runtimeConfiguration?.availableTenants.map((tenant) => (
                  <option key={tenant.tenantCode} value={tenant.tenantCode}>
                    {tenant.tenantName}
                  </option>
                ))}
              </select>
            </label>
          </div>
        </section>

        <Routes>
          <Route path="/" element={<Navigate to="/customers" replace />} />
          <Route
            path="/payments/new"
            element={<PaymentPage activeTenantCode={activeTenantCode} apiClient={apiClient} />}
          />
          <Route
            path="/payments/callback"
            element={
              <PaymentCallbackPage
                activeTenantCode={activeTenantCode}
                apiClient={apiClient}
                onTenantChange={handleTenantChange}
              />
            }
          />
          <Route
            path="/payment/callback"
            element={
              <PaymentCallbackPage
                activeTenantCode={activeTenantCode}
                apiClient={apiClient}
                onTenantChange={handleTenantChange}
              />
            }
          />
          <Route
            path="/customers"
            element={
              <CustomerDirectoryPage
                activeTenantCode={activeTenantCode}
                apiClient={apiClient}
                configuredActiveTenantCode={runtimeConfiguration?.configuredActiveTenantCode ?? "pending"}
              />
            }
          />
          <Route
            path="/customers/:customerId"
            element={<CustomerDetailPage activeTenantCode={activeTenantCode} apiClient={apiClient} />}
          />
          <Route
            path="/customers/:customerId/orders/new"
            element={<OrderCreatePage activeTenantCode={activeTenantCode} apiClient={apiClient} />}
          />
          <Route
            path="/customers/:customerId/orders/:orderId"
            element={<OrderDetailPage activeTenantCode={activeTenantCode} apiClient={apiClient} />}
          />
          <Route
            path="/customers/:customerId/orders/:orderId/payment"
            element={<PaymentPage activeTenantCode={activeTenantCode} apiClient={apiClient} />}
          />
        </Routes>
      </main>
    </BrowserRouter>
  );
}

function resolveRequestedBootstrapTenantCode(pathname: string, search: string): string | null {
  const callbackSearch = new URLSearchParams(search);
  if (callbackSearch.has("code")) {
    const returnUrl = sessionStorage.getItem(`${oidcStoragePrefix}.returnUrl`);
    if (returnUrl) {
      const savedUrl = new URL(returnUrl);
      return resolveRequestedBootstrapTenantCode(savedUrl.pathname, savedUrl.search);
    }
  }

  const trimmedPath = pathname.trim();
  if (!trimmedPath.startsWith("/payments/") && !trimmedPath.startsWith("/payment/")) {
    return null;
  }

  const tenantCode = callbackSearch.get("tenantCode")?.trim();
  return tenantCode || null;
}

async function bootstrapLocalAccessToken(): Promise<BootstrapTokenResult> {
  if (!configuredKeycloakAuthority || !configuredKeycloakRealm || !configuredKeycloakClientId) {
    return { accessToken: null, authRedirectInitiated: false };
  }

  const currentToken = localStorage.getItem("orderprocessing.accessToken");
  const expiresAt = Number(localStorage.getItem(`${oidcStoragePrefix}.expiresAt`) ?? "0");
  if (currentToken && expiresAt > Date.now() + 30_000) {
    return { accessToken: currentToken, authRedirectInitiated: false };
  }

  const currentUrl = new URL(window.location.href);
  const authorizationCode = currentUrl.searchParams.get("code");
  const returnedState = currentUrl.searchParams.get("state");
  if (authorizationCode) {
    const expectedState = sessionStorage.getItem(`${oidcStoragePrefix}.state`);
    const verifier = sessionStorage.getItem(`${oidcStoragePrefix}.verifier`);
    const redirectUri = sessionStorage.getItem(`${oidcStoragePrefix}.redirectUri`);
    if (!expectedState || expectedState !== returnedState || !verifier || !redirectUri) {
      throw new Error("The local OIDC callback state is invalid.");
    }

    const token = await exchangeAuthorizationCode(authorizationCode, verifier, redirectUri);
    sessionStorage.removeItem(`${oidcStoragePrefix}.state`);
    sessionStorage.removeItem(`${oidcStoragePrefix}.verifier`);
    sessionStorage.removeItem(`${oidcStoragePrefix}.redirectUri`);
    const returnUrl = sessionStorage.getItem(`${oidcStoragePrefix}.returnUrl`) ?? `${window.location.origin}/`;
    sessionStorage.removeItem(`${oidcStoragePrefix}.returnUrl`);
    window.history.replaceState({}, document.title, returnUrl);
    return { accessToken: token, authRedirectInitiated: false };
  }

  const verifier = createRandomUrlSafeValue(64);
  const state = createRandomUrlSafeValue(32);
  const challenge = await createCodeChallenge(verifier);
  const redirectUri = `${window.location.origin}${window.location.pathname}`;
  sessionStorage.setItem(`${oidcStoragePrefix}.state`, state);
  sessionStorage.setItem(`${oidcStoragePrefix}.verifier`, verifier);
  sessionStorage.setItem(`${oidcStoragePrefix}.redirectUri`, redirectUri);
  sessionStorage.setItem(`${oidcStoragePrefix}.returnUrl`, window.location.href);

  const authorizationUrl = new URL(
    `${configuredKeycloakAuthority}/realms/${configuredKeycloakRealm}/protocol/openid-connect/auth`
  );
  authorizationUrl.search = new URLSearchParams({
    client_id: configuredKeycloakClientId,
    response_type: "code",
    scope: "openid profile email",
    redirect_uri: redirectUri,
    code_challenge: challenge,
    code_challenge_method: "S256",
    state
  }).toString();
  window.location.assign(authorizationUrl);
  return { accessToken: null, authRedirectInitiated: true };
}

async function exchangeAuthorizationCode(
  authorizationCode: string,
  verifier: string,
  redirectUri: string
): Promise<string> {
  const tokenUrl = `${configuredKeycloakAuthority}/realms/${configuredKeycloakRealm}/protocol/openid-connect/token`;
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: configuredKeycloakClientId,
    code: authorizationCode,
    code_verifier: verifier,
    redirect_uri: redirectUri
  });

  const response = await fetch(tokenUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body: body.toString()
  });

  if (!response.ok) {
    throw new Error(`Local OIDC token exchange failed with HTTP ${response.status}.`);
  }

  const payload = await response.json() as { access_token?: string; expires_in?: number };
  if (!payload.access_token) {
    throw new Error("Local OIDC token exchange returned no access token.");
  }

  const expiresInSeconds = Math.max(payload.expires_in ?? 300, 30);
  localStorage.setItem(
    `${oidcStoragePrefix}.expiresAt`,
    String(Date.now() + expiresInSeconds * 1000)
  );
  return payload.access_token;
}

function createRandomUrlSafeValue(byteLength: number): string {
  const bytes = crypto.getRandomValues(new Uint8Array(byteLength));
  return toBase64Url(bytes);
}

async function createCodeChallenge(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  return toBase64Url(new Uint8Array(digest));
}

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}
