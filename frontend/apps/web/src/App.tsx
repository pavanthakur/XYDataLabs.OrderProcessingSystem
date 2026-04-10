import { useEffect, useState } from "react";
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
const apiClient = createOrderProcessingApiClient({
  getTenantCode: () => tenantSession.getActiveTenantCode(),
  getTenantHeaderName: () => tenantSession.getTenantHeaderName()
});

type LoadState = "idle" | "loading" | "ready" | "error";

export default function App() {
  const [runtimeConfiguration, setRuntimeConfiguration] = useState<RuntimeConfiguration | null>(null);
  const [activeTenantCode, setActiveTenantCode] = useState("");
  const [bootstrapState, setBootstrapState] = useState<LoadState>("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    let isCancelled = false;

    async function bootstrapShell() {
      setBootstrapState("loading");
      setErrorMessage(null);

      try {
        const bootstrap = await apiClient.getRuntimeConfiguration();
        const sessionState = tenantSession.initialize(bootstrap);

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
  }, []);

  function handleTenantChange(nextTenantCode: string) {
    const sessionState = tenantSession.setActiveTenantCode(nextTenantCode);
    setActiveTenantCode(sessionState.activeTenantCode);
  }

  return (
    <BrowserRouter>
      <main className="app-shell">
        <section className="hero-panel">
          <p className="eyebrow">Track U Order Slice</p>
          <h1>React browser routes now cover customer browsing, order execution, and payment initiation.</h1>
          <p className="lede">
            The shell now carries tenant bootstrap, customer browsing, order detail, order creation,
            payment initiation, and callback result rendering on the existing v1 API while the
            provider return path remains server-owned on the API callback surface.
          </p>
        </section>

        <section className="status-grid" aria-label="Bootstrap status">
          <article className="status-card">
            <span>Bootstrap</span>
            <strong>{bootstrapState}</strong>
          </article>
          <article className="status-card">
            <span>Resolved Tenant</span>
            <strong>{activeTenantCode || "pending"}</strong>
          </article>
          <article className="status-card">
            <span>Tenant Header</span>
            <strong>{runtimeConfiguration?.tenantHeaderName ?? "pending"}</strong>
          </article>
          <article className="status-card">
            <span>Route Surface</span>
            <strong>Customers + Orders + Payments + Callback</strong>
          </article>
        </section>

        {errorMessage ? <p className="error-banner">{errorMessage}</p> : null}

        <section className="shell-toolbar panel">
          <div>
            <p className="eyebrow">Navigation</p>
            <h2>Tenant-aware browser shell</h2>
          </div>

          <div className="shell-actions">
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
              <span>Active tenant</span>
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