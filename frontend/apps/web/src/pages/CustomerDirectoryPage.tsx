import { useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import type { CustomerSummary, OrderProcessingApiClient } from "@xydatalabs/orderprocessing-api-sdk";

type LoadState = "idle" | "loading" | "ready" | "error";

interface CustomerDirectoryPageProps {
  activeTenantCode: string;
  apiClient: OrderProcessingApiClient;
  configuredActiveTenantCode: string;
}

export function CustomerDirectoryPage({
  activeTenantCode,
  apiClient,
  configuredActiveTenantCode
}: CustomerDirectoryPageProps) {
  const [searchParams, setSearchParams] = useSearchParams();
  const appliedSearchTerm = searchParams.get("q")?.trim() ?? "";
  const [draftSearchTerm, setDraftSearchTerm] = useState(appliedSearchTerm);
  const [customers, setCustomers] = useState<CustomerSummary[]>([]);
  const [loadState, setLoadState] = useState<LoadState>("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    setDraftSearchTerm(appliedSearchTerm);
  }, [appliedSearchTerm]);

  useEffect(() => {
    if (!activeTenantCode) {
      return;
    }

    let isCancelled = false;

    async function loadCustomers() {
      setLoadState("loading");
      setErrorMessage(null);

      try {
        const nextCustomers = appliedSearchTerm.length > 0
          ? await apiClient.searchCustomersByName(appliedSearchTerm, 1, 25)
          : await apiClient.getAllCustomers();

        if (isCancelled) {
          return;
        }

        setCustomers(nextCustomers);
        setLoadState("ready");
      } catch (error) {
        if (isCancelled) {
          return;
        }

        setCustomers([]);
        setLoadState("error");
        setErrorMessage(error instanceof Error ? error.message : "Unable to load customers.");
      }
    }

    void loadCustomers();

    return () => {
      isCancelled = true;
    };
  }, [activeTenantCode, apiClient, appliedSearchTerm]);

  function handleSearchSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const nextSearchTerm = draftSearchTerm.trim();
    if (nextSearchTerm.length === 0) {
      setSearchParams({});
      return;
    }

    setSearchParams({ q: nextSearchTerm });
  }

  function handleClearSearch() {
    setDraftSearchTerm("");
    setSearchParams({});
  }

  return (
    <section className="route-panel">
      <article className="panel">
        <header className="panel-header">
          <div>
            <p className="eyebrow">Customer Directory</p>
            <h2>Search and browse tenant-scoped customers</h2>
          </div>
          <span className="count-pill">{customers.length} visible</span>
        </header>

        <form className="search-form" onSubmit={handleSearchSubmit}>
          <label className="search-field">
            <span>Search by customer name</span>
            <input
              type="search"
              value={draftSearchTerm}
              onChange={(event) => setDraftSearchTerm(event.target.value)}
              placeholder="e.g. Alice"
            />
          </label>

          <div className="search-actions">
            <button type="submit" className="action-button action-button-primary">
              Search
            </button>
            <button type="button" className="action-button" onClick={handleClearSearch}>
              Clear
            </button>
          </div>
        </form>

        <dl className="definition-list definition-list-compact">
          <div>
            <dt>Resolved tenant</dt>
            <dd>{activeTenantCode}</dd>
          </div>
          <div>
            <dt>Configured tenant</dt>
            <dd>{configuredActiveTenantCode}</dd>
          </div>
          <div>
            <dt>Applied search</dt>
            <dd>{appliedSearchTerm || "All customers"}</dd>
          </div>
          <div>
            <dt>Data state</dt>
            <dd>{loadState}</dd>
          </div>
        </dl>

        {errorMessage ? <p className="error-banner">{errorMessage}</p> : null}

        {customers.length > 0 ? (
          <ul className="customer-list">
            {customers.map((customer) => (
              <li key={customer.customerId}>
                <Link className="customer-link" to={`/customers/${customer.customerId}`}>
                  <div>
                    <strong>{customer.name}</strong>
                    <p>{customer.email}</p>
                  </div>
                  <span>{customer.orderDtos.length} orders</span>
                </Link>
              </li>
            ))}
          </ul>
        ) : (
          <p className="empty-state">
            {loadState === "loading"
              ? "Loading customer data for the selected tenant."
              : "No customers matched the current filter for this tenant."}
          </p>
        )}
      </article>
    </section>
  );
}