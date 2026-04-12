import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import type { OrderProcessingApiClient, ProductSummary } from "@xydatalabs/orderprocessing-api-sdk";

type LoadState = "idle" | "loading" | "ready" | "error";
type SubmitState = "idle" | "submitting" | "error";

interface OrderCreatePageProps {
  activeTenantCode: string;
  apiClient: OrderProcessingApiClient;
}

export function OrderCreatePage({ activeTenantCode, apiClient }: OrderCreatePageProps) {
  const navigate = useNavigate();
  const params = useParams<{ customerId: string }>();
  const customerId = Number(params.customerId);
  const [products, setProducts] = useState<ProductSummary[]>([]);
  const [selectedProductIds, setSelectedProductIds] = useState<number[]>([]);
  const [loadState, setLoadState] = useState<LoadState>("idle");
  const [submitState, setSubmitState] = useState<SubmitState>("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!activeTenantCode) {
      return;
    }

    if (!Number.isInteger(customerId) || customerId <= 0) {
      setLoadState("error");
      setErrorMessage("The requested customer id is invalid.");
      return;
    }

    let isCancelled = false;

    async function loadProducts() {
      setLoadState("loading");
      setErrorMessage(null);

      try {
        const nextProducts = await apiClient.getAllProducts();

        if (isCancelled) {
          return;
        }

        setProducts(nextProducts);
        setLoadState("ready");
      } catch (error) {
        if (isCancelled) {
          return;
        }

        setProducts([]);
        setLoadState("error");
        setErrorMessage(error instanceof Error ? error.message : "Unable to load products.");
      }
    }

    void loadProducts();

    return () => {
      isCancelled = true;
    };
  }, [activeTenantCode, apiClient, customerId]);

  const selectedProducts = useMemo(
    () => products.filter((product) => selectedProductIds.includes(product.productId)),
    [products, selectedProductIds]
  );

  const totalPrice = useMemo(
    () => selectedProducts.reduce((sum, product) => sum + product.price, 0),
    [selectedProducts]
  );

  function toggleProduct(productId: number) {
    setSelectedProductIds((current) =>
      current.includes(productId)
        ? current.filter((value) => value !== productId)
        : [...current, productId]
    );
  }

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!Number.isInteger(customerId) || customerId <= 0) {
      setErrorMessage("The requested customer id is invalid.");
      return;
    }

    if (selectedProductIds.length === 0) {
      setErrorMessage("Select at least one product before creating an order.");
      return;
    }

    setSubmitState("submitting");
    setErrorMessage(null);

    try {
      const order = await apiClient.createOrder({
        customerId,
        productIds: selectedProductIds
      });

      navigate(`/customers/${customerId}/orders/${order.orderId}`);
    } catch (error) {
      setSubmitState("error");
      setErrorMessage(error instanceof Error ? error.message : "Unable to create the order.");
    }
  }

  return (
    <section className="route-panel detail-layout">
      <article className="panel">
        <header className="panel-header">
          <div>
            <p className="eyebrow">Order Create</p>
            <h2>Build a new order for customer #{Number.isInteger(customerId) ? customerId : "invalid"}</h2>
          </div>
          <div className="detail-actions">
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
            <dt>Products state</dt>
            <dd>{loadState}</dd>
          </div>
          <div>
            <dt>Submit state</dt>
            <dd>{submitState}</dd>
          </div>
          <div>
            <dt>Selected items</dt>
            <dd>{selectedProductIds.length}</dd>
          </div>
        </dl>

        {errorMessage ? <p className="error-banner">{errorMessage}</p> : null}

        <form className="order-create-layout" onSubmit={handleSubmit}>
          <section className="detail-card">
            <h3>Available products</h3>
            {products.length > 0 ? (
              <ul className="selection-list">
                {products.map((product) => {
                  const isSelected = selectedProductIds.includes(product.productId);

                  return (
                    <li key={product.productId}>
                      <label className={isSelected ? "selection-card selection-card-selected" : "selection-card"}>
                        <input
                          type="checkbox"
                          checked={isSelected}
                          onChange={() => toggleProduct(product.productId)}
                        />
                        <div>
                          <strong>{product.name}</strong>
                          <p>{product.description || "No description provided."}</p>
                        </div>
                        <span>{formatCurrency(product.price)}</span>
                      </label>
                    </li>
                  );
                })}
              </ul>
            ) : (
              <p className="empty-state">
                {loadState === "loading" ? "Loading available products." : "No products are available."}
              </p>
            )}
          </section>

          <aside className="detail-card order-summary-card">
            <h3>Order summary</h3>
            <p className="subtle-copy">
              The browser selects products, but order creation still posts to the server-owned Order API.
            </p>

            <dl className="definition-list definition-list-single">
              <div>
                <dt>Customer id</dt>
                <dd>{Number.isInteger(customerId) ? customerId : "invalid"}</dd>
              </div>
              <div>
                <dt>Total selected</dt>
                <dd>{selectedProductIds.length}</dd>
              </div>
              <div>
                <dt>Projected total</dt>
                <dd>{formatCurrency(totalPrice)}</dd>
              </div>
            </dl>

            <button type="submit" className="action-button action-button-primary" disabled={submitState === "submitting"}>
              {submitState === "submitting" ? "Creating order..." : "Create order"}
            </button>
          </aside>
        </form>
      </article>
    </section>
  );
}

function formatCurrency(value: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD"
  }).format(value);
}