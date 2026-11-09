import { useEffect, useRef, useState } from "react";
import { BrowserRouter, Navigate, NavLink, Route, Routes, useNavigate } from "react-router-dom";
import { createOrderProcessingApiClient, type RuntimeConfiguration } from "@xydatalabs/orderprocessing-api-sdk";
import { createTenantSession } from "@xydatalabs/orderprocessing-tenant-session";
import { CustomerDetailPage } from "./pages/CustomerDetailPage";
import { CustomerDirectoryPage } from "./pages/CustomerDirectoryPage";
import { OrderCreatePage } from "./pages/OrderCreatePage";
import { OrderDetailPage } from "./pages/OrderDetailPage";
import { PaymentCallbackPage } from "./pages/PaymentCallbackPage";
import { PaymentPage } from "./pages/PaymentPage";
import { setAccessToken } from "./payment-flow";
import { clearApplicationSession, identitySession, requestedEntryTenant } from "./identity-session";
import { getPublicRuntimeConfig } from "./runtime-config";

export default function App() { return <BrowserRouter><ApplicationShell /></BrowserRouter>; }

function ApplicationShell() {
  const navigate = useNavigate();
  const [tenantSession] = useState(() => createTenantSession());
  const [apiClient] = useState(() => createOrderProcessingApiClient({
    baseUrl: getPublicRuntimeConfig().apiBaseUrl,
    getTenantCode: () => tenantSession.getActiveTenantCode(),
    getTenantHeaderName: () => tenantSession.getTenantHeaderName(),
    getAccessToken: () => localStorage.getItem("orderprocessing.accessToken")
  }));
  const [configuration, setConfiguration] = useState<RuntimeConfiguration | null>(null);
  const [activeTenantCode, setActiveTenantCode] = useState("");
  const [state, setState] = useState<"loading" | "ready" | "error" | "signed-out">(location.pathname === "/signed-out" ? "signed-out" : "loading");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const started = useRef(false);

  useEffect(() => {
    if (started.current || location.pathname === "/signed-out") return;
    started.current = true;
    let cancelled = false;
    async function bootstrap() {
      try {
        const requested = requestedEntryTenant();
        const token = await identitySession().bootstrap();
        if (cancelled || token.authRedirectInitiated) return;
        setAccessToken(token.accessToken);
        const runtime = await apiClient.getRuntimeConfiguration();
        if (getPublicRuntimeConfig().mode !== "Disabled" && !runtime.session)
          throw new Error("The API did not confirm an authenticated session. Please sign in again.");
        const saved = localStorage.getItem("orderprocessing.activeTenantCode");
        const authorizedSaved = runtime.session?.canAccessAllTenants
          && runtime.availableTenants.some(t => t.tenantCode === saved) ? saved : null;
        const entryTenant = requested ?? authorizedSaved;
        if (requested && !runtime.availableTenants.some(t => t.tenantCode.toLowerCase() === requested.toLowerCase()))
          throw new Error("The requested application tenant is not authorized or is not active.");
        const session = tenantSession.initialize(runtime, entryTenant);
        if (cancelled) return;
        setConfiguration(runtime);
        setActiveTenantCode(session.activeTenantCode);
        setState("ready");
        navigate(`${location.pathname}${location.search}`, { replace: true });
      } catch (error) {
        if (!cancelled) {
          setState("error");
          setErrorMessage(error instanceof Error ? error.message : "Unable to prepare the tenant session.");
        }
      }
    }
    void bootstrap();
    return () => { cancelled = true; };
  }, [apiClient, navigate, tenantSession]);

  useEffect(() => {
    function invalidate() {
      apiClient.cancelPendingRequests();
      setAccessToken(null);
      setConfiguration(null);
      setActiveTenantCode("");
      setState("signed-out");
      navigate("/signed-out", { replace: true });
    }
    function storageChanged(event: StorageEvent) {
      if (event.key === "orderprocessing.logout" && event.newValue) invalidate();
    }
    function expired() {
      clearApplicationSession();
      invalidate();
      setErrorMessage("Your session has expired. Please sign in again.");
    }
    window.addEventListener("storage", storageChanged);
    window.addEventListener("orderprocessing.session-expired", expired);
    const expiry = Number(localStorage.getItem("orderprocessing.oidc.expiresAt"));
    const timer = state === "ready" && expiry > 0 ? window.setTimeout(expired, Math.max(0, expiry - Date.now())) : undefined;
    return () => {
      window.removeEventListener("storage", storageChanged);
      window.removeEventListener("orderprocessing.session-expired", expired);
      if (timer !== undefined) clearTimeout(timer);
    };
  }, [apiClient, navigate, state]);

  async function signOut() {
    apiClient.cancelPendingRequests();
    setConfiguration(null);
    setActiveTenantCode("");
    setState("signed-out");
    try { await identitySession().signOut(); }
    catch {
      clearApplicationSession();
      setErrorMessage("Local access cleared. Identity-provider logout could not be confirmed; please retry Sign out before changing accounts.");
      navigate("/signed-out", { replace: true });
    }
  }
  async function signIn() {
    setErrorMessage(null);
    try { await identitySession().signIn(); }
    catch { setErrorMessage("Unable to start sign-in. Check the identity provider and try again."); }
  }
  function changeTenant(next: string) {
    const nextState = tenantSession.setActiveTenantCode(next);
    if (nextState.activeTenantCode === activeTenantCode) return;
    apiClient.cancelPendingRequests();
    setActiveTenantCode(nextState.activeTenantCode);
    navigate(`/customers?tenantCode=${encodeURIComponent(nextState.activeTenantCode)}`, { replace: true });
  }

  return <main className="app-shell">
    {errorMessage ? <p className="error-banner" role="alert">{errorMessage}</p> : null}
    <section className="shell-header panel">
      <div className="shell-copy">
        <p className="eyebrow">Order Processing Portal</p>
        <h1>Customers, orders, and card payments</h1>
        <p className="shell-lede">All actions are scoped to the selected tenant, so agents can move from customer lookup to payment collection without leaving the same browser workspace.</p>
        <p className="shell-meta">{state === "ready" ? `Active tenant: ${activeTenantCode}` : state === "loading" ? "Preparing tenant session..." : "Tenant session needs attention."}</p>
      </div>
      <div className="shell-actions shell-actions-compact">
        {configuration?.session ? <div className="account-summary">
          <p>Signed in as <strong>{configuration.session.username}</strong></p>
          <p>{configuration.session.canAccessAllTenants ? "All active tenants" : `Access: ${configuration.session.tenantCode}`}</p>
        </div> : null}
        {state === "ready" ? <>
          <nav className="shell-nav" aria-label="Primary">
            <NavLink to="/customers" className={({ isActive }) => isActive ? "nav-link nav-link-active" : "nav-link"}>Customers</NavLink>
            <NavLink to="/payments/new" className={({ isActive }) => isActive ? "nav-link nav-link-active" : "nav-link"}>Payments</NavLink>
          </nav>
          <label className="tenant-picker"><span>Tenant</span><select value={activeTenantCode}
            onChange={event => changeTenant(event.target.value)}
            disabled={!configuration || configuration.availableTenants.length < 2 || configuration.tenantSelectorEnabled === false}>
            {configuration?.availableTenants.map(tenant => <option key={tenant.tenantCode} value={tenant.tenantCode}>{tenant.tenantName}</option>)}
          </select></label>
        </> : null}
        {getPublicRuntimeConfig().mode !== "Disabled" ? <button className="action-button" onClick={() => void signOut()}>Sign out</button> : null}
      </div>
    </section>
    {state === "signed-out" || state === "error" ? <section className="panel"><h2>{state === "signed-out" ? "Signed out of the application" : "Sign-in needs attention"}</h2>
      <button className="action-button action-button-primary" onClick={() => void signIn()}>Sign in</button>
    </section> : null}
    {state === "ready" ? <Routes key={activeTenantCode}>
      <Route path="/" element={<Navigate to="/customers" replace />} />
      <Route path="/auth/callback" element={<p>Restoring the signed-in page...</p>} />
      <Route path="/payments/new" element={<PaymentPage activeTenantCode={activeTenantCode} apiClient={apiClient} />} />
      <Route path="/payments/callback" element={<PaymentCallbackPage activeTenantCode={activeTenantCode} apiClient={apiClient} onTenantChange={changeTenant} />} />
      <Route path="/payment/callback" element={<PaymentCallbackPage activeTenantCode={activeTenantCode} apiClient={apiClient} onTenantChange={changeTenant} />} />
      <Route path="/customers" element={<CustomerDirectoryPage activeTenantCode={activeTenantCode} apiClient={apiClient} configuredActiveTenantCode={configuration?.configuredActiveTenantCode ?? "pending"} />} />
      <Route path="/customers/:customerId" element={<CustomerDetailPage activeTenantCode={activeTenantCode} apiClient={apiClient} />} />
      <Route path="/customers/:customerId/orders/new" element={<OrderCreatePage activeTenantCode={activeTenantCode} apiClient={apiClient} />} />
      <Route path="/customers/:customerId/orders/:orderId" element={<OrderDetailPage activeTenantCode={activeTenantCode} apiClient={apiClient} />} />
      <Route path="/customers/:customerId/orders/:orderId/payment" element={<PaymentPage activeTenantCode={activeTenantCode} apiClient={apiClient} />} />
    </Routes> : null}
  </main>;
}
