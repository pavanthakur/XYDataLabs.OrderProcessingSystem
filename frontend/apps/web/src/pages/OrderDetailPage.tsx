import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import type { OrderDetail, OrderProcessingApiClient } from "@xydatalabs/orderprocessing-api-sdk";

type LoadState = "idle" | "loading" | "ready" | "error";

interface OrderDetailPageProps {
  activeTenantCode: string;
  apiClient: OrderProcessingApiClient;
}

export function OrderDetailPage({ activeTenantCode, apiClient }: OrderDetailPageProps) {
  const params = useParams<{ customerId: string; orderId: string }>();
  const customerId = Number(params.customerId);
  const orderId = Number(params.orderId);
  const [order, setOrder] = useState<OrderDetail | null>(null);
  const [loadState, setLoadState] = useState<LoadState>("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!activeTenantCode) {
      return;
    }

    if (!Number.isInteger(orderId) || orderId <= 0) {
      setOrder(null);
      setLoadState("error");
      setErrorMessage("The requested order id is invalid.");
      return;
    }

    let isCancelled = false;

    async function loadOrder() {
      setLoadState("loading");
      setErrorMessage(null);

      try {
        const nextOrder = await apiClient.getOrderById(orderId);

        if (isCancelled) {
          return;
        }

        setOrder(nextOrder);
        setLoadState("ready");
      } catch (error) {
        if (isCancelled) {
          return;
        }

        setOrder(null);
        setLoadState("error");
        setErrorMessage(error instanceof Error ? error.message : "Unable to load order details.");
      }
    }

    void loadOrder();

    return () => {
      isCancelled = true;
    };
  }, [activeTenantCode, apiClient, orderId]);

  return (
    <section className="route-panel detail-layout">
      <article className="panel">
        <header className="panel-header">
          <div>
            <p className="eyebrow">Order Detail</p>
            <h2>{order ? `Order #${order.orderId}` : "Order record"}</h2>
          </div>
          <div className="detail-actions">
            {Number.isInteger(customerId) && Number.isInteger(orderId) && customerId > 0 && orderId > 0 ? (
              <Link to={`/customers/${customerId}/orders/${orderId}/payment`} className="action-button-link action-button-link-primary">
                Initiate payment
              </Link>
            ) : null}
            <Link to={`/customers/${customerId}`} className="back-link">
              Back to customer
            </Link>
          </div>
        </header>

        <dl className="definition-list definition-list-compact">
          <div>
            <dt>Resolved tenant</dt>
            <dd>{activeTenantCode || "pending"}</dd>
          </div>
          <div>
            <dt>Requested order</dt>
            <dd>{Number.isInteger(orderId) ? orderId : "invalid"}</dd>
          </div>
          <div>
            <dt>Data state</dt>
            <dd>{loadState}</dd>
          </div>
          <div>
            <dt>Total price</dt>
            <dd>{order ? formatCurrency(order.totalPrice) : "pending"}</dd>
          </div>
        </dl>

        {errorMessage ? <p className="error-banner">{errorMessage}</p> : null}

        {order ? (
          <div className="detail-grid">
            <section className="detail-card">
              <h3>Line items</h3>
              {order.orderProductDtos && order.orderProductDtos.length > 0 ? (
                <ul className="selection-list selection-list-compact">
                  {order.orderProductDtos.map((item) => (
                    <li key={item.sysId}>
                      <div className="selection-card selection-card-static">
                        <div>
                          <strong>{item.productDto?.name ?? `Product #${item.productId}`}</strong>
                          <p>{item.productDto?.description || "Line item returned by the order detail API."}</p>
                        </div>
                        <div className="order-meta">
                          <span>Qty {item.quantity}</span>
                          <span>{formatCurrency(item.price)}</span>
                        </div>
                      </div>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="empty-state">No order products were returned.</p>
              )}
            </section>

            <section className="detail-card">
              <h3>Order status</h3>
              <dl className="definition-list definition-list-single">
                <div>
                  <dt>Status</dt>
                  <dd>{order.status}</dd>
                </div>
                <div>
                  <dt>Fulfilled</dt>
                  <dd>{order.isFulfilled ? "Yes" : "No"}</dd>
                </div>
                <div>
                  <dt>Order date</dt>
                  <dd>{formatOrderDate(order.orderDate)}</dd>
                </div>
              </dl>
            </section>
          </div>
        ) : (
          <p className="empty-state">
            {loadState === "loading" ? "Loading order details." : "No order record is available."}
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