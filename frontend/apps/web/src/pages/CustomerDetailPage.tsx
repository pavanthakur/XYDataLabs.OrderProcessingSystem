import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import type { CustomerSummary, OrderProcessingApiClient } from "@xydatalabs/orderprocessing-api-sdk";

type LoadState = "idle" | "loading" | "ready" | "error";

interface CustomerDetailPageProps {
  activeTenantCode: string;
  apiClient: OrderProcessingApiClient;
}

export function CustomerDetailPage({ activeTenantCode, apiClient }: CustomerDetailPageProps) {
  const params = useParams<{ customerId: string }>();
  const customerId = Number(params.customerId);
  const [customer, setCustomer] = useState<CustomerSummary | null>(null);
  const [loadState, setLoadState] = useState<LoadState>("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!activeTenantCode) {
      return;
    }

    if (!Number.isInteger(customerId) || customerId <= 0) {
      setCustomer(null);
      setLoadState("error");
      setErrorMessage("The requested customer id is invalid.");
      return;
    }

    let isCancelled = false;

    async function loadCustomer() {
      setLoadState("loading");
      setErrorMessage(null);

      try {
        const nextCustomer = await apiClient.getCustomerById(customerId);

        if (isCancelled) {
          return;
        }

        setCustomer(nextCustomer);
        setLoadState("ready");
      } catch (error) {
        if (isCancelled) {
          return;
        }

        setCustomer(null);
        setLoadState("error");
        setErrorMessage(error instanceof Error ? error.message : "Unable to load customer details.");
      }
    }

    void loadCustomer();

    return () => {
      isCancelled = true;
    };
  }, [activeTenantCode, apiClient, customerId]);

  return (
    <section className="route-panel detail-layout">
      <article className="panel">
        <header className="panel-header">
          <div>
            <p className="eyebrow">Customer Detail</p>
            <h2>{customer?.name ?? "Customer record"}</h2>
          </div>
          <div className="detail-actions">
            <Link to="/customers" className="back-link">
              Back to directory
            </Link>
            {Number.isInteger(customerId) && customerId > 0 ? (
              <Link to={`/customers/${customerId}/orders/new`} className="action-button-link action-button-link-primary">
                Create order
              </Link>
            ) : null}
          </div>
        </header>

        <dl className="definition-list definition-list-compact">
          <div>
            <dt>Resolved tenant</dt>
            <dd>{activeTenantCode || "pending"}</dd>
          </div>
          <div>
            <dt>Requested id</dt>
            <dd>{Number.isInteger(customerId) ? customerId : "invalid"}</dd>
          </div>
          <div>
            <dt>Data state</dt>
            <dd>{loadState}</dd>
          </div>
          <div>
            <dt>Email</dt>
            <dd>{customer?.email ?? "pending"}</dd>
          </div>
        </dl>

        {errorMessage ? <p className="error-banner">{errorMessage}</p> : null}

        {customer ? (
          <div className="detail-grid">
            <section className="detail-card">
              <h3>Orders</h3>
              {customer.orderDtos.length > 0 ? (
                <ul className="order-list">
                  {customer.orderDtos.map((order) => (
                    <li key={order.orderId}>
                      <Link className="order-link" to={`/customers/${customerId}/orders/${order.orderId}`}>
                        <div>
                          <strong>Order #{order.orderId}</strong>
                          <p>{formatOrderDate(order.orderDate)}</p>
                        </div>
                        <div className="order-meta">
                          <span>{order.status}</span>
                          <span>{formatCurrency(order.totalPrice)}</span>
                        </div>
                      </Link>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="empty-state">No orders are currently attached to this customer.</p>
              )}
            </section>

            <section className="detail-card">
              <h3>Migration signal</h3>
              <p className="subtle-copy">
                This route is a direct React replacement for the customer read flow and uses the
                existing GET customer endpoint with tenant header injection.
              </p>
            </section>
          </div>
        ) : (
          <p className="empty-state">
            {loadState === "loading"
              ? "Loading customer details."
              : "No customer record is available for the current selection."}
          </p>
        )}
      </article>
    </section>
  );
}

function formatOrderDate(value: string): string {
  const parsedDate = new Date(value);
  if (Number.isNaN(parsedDate.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric"
  }).format(parsedDate);
}

function formatCurrency(value: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD"
  }).format(value);
}