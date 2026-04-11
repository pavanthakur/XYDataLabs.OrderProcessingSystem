import { useEffect, useMemo, useState } from "react";
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

const tenantSession = createTenantSession();
const configuredApiBaseUrl = (import.meta.env.VITE_ORDERPROCESSING_API_BASE_URL ?? "").trim();
const apiClient = createOrderProcessingApiClient({
  baseUrl: configuredApiBaseUrl.length > 0 ? configuredApiBaseUrl.replace(/\/$/, "") : "",
  getTenantCode: () => tenantSession.getActiveTenantCode(),
  getTenantHeaderName: () => tenantSession.getTenantHeaderName()
});

type LoadState = "idle" | "loading" | "ready" | "error";

export default function App() {
  const [runtimeConfiguration, setRuntimeConfiguration] = useState<RuntimeConfiguration | null>(null);
  const [activeTenantCode, setActiveTenantCode] = useState("");
  const [bootstrapState, setBootstrapState] = useState<LoadState>("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const requestedBootstrapTenantCode = useMemo(
    () => resolveRequestedBootstrapTenantCode(window.location.pathname, window.location.search),
    []
  );

  useEffect(() => {
    let isCancelled = false;

    async function bootstrapShell() {
      setBootstrapState("loading");
      setErrorMessage(null);

      try {
        const bootstrap = await apiClient.getRuntimeConfiguration(requestedBootstrapTenantCode ?? undefined);
        let sessionState = tenantSession.initialize(bootstrap);

        if (
          requestedBootstrapTenantCode
          && sessionState.activeTenantCode.localeCompare(requestedBootstrapTenantCode, undefined, { sensitivity: "accent" }) !== 0
        ) {
          sessionState = tenantSession.setActiveTenantCode(requestedBootstrapTenantCode);
        }

        if (isCancelled) {
          return;
        }

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
  const trimmedPath = pathname.trim();
  if (!trimmedPath.startsWith("/payments/")) {
    return null;
  }

  const searchParams = new URLSearchParams(search);
  const tenantCode = searchParams.get("tenantCode")?.trim();
  return tenantCode || null;
}