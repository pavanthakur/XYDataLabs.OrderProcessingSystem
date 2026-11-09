import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import type { CustomerSummary, OrderProcessingApiClient } from "@xydatalabs/orderprocessing-api-sdk";
import { isEligiblePaymentOrder } from "../payment-order";

export function PaymentOrderPicker({ activeTenantCode, apiClient }: { activeTenantCode: string; apiClient: OrderProcessingApiClient }) {
  const navigate = useNavigate();
  const [customers, setCustomers] = useState<CustomerSummary[]>([]);
  const [customerId, setCustomerId] = useState("");
  const [orderId, setOrderId] = useState("");
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [error, setError] = useState<string | null>(null);
  const [reload, setReload] = useState(0);
  useEffect(() => {
    let cancelled = false;
    setCustomers([]); setCustomerId(""); setOrderId(""); setError(null); setState("loading");
    if (!activeTenantCode) return;
    apiClient.getAllCustomers().then(result => {
      if (!cancelled) { setCustomers(result); setState("ready"); }
    }).catch(reason => {
      if (!cancelled) { setState("error"); setError(reason instanceof Error ? reason.message : "Unable to load existing orders."); }
    });
    return () => { cancelled = true; };
  }, [activeTenantCode, apiClient, reload]);
  const customer = customers.find(item => String(item.customerId) === customerId);
  const orders = (customer?.orderDtos ?? []).filter(item => isEligiblePaymentOrder(item) && item.customerId === customer?.customerId);
  const selected = orders.find(item => String(item.orderId) === orderId);
  return <section className="route-panel"><article className="panel">
    <header className="panel-header"><div>
      <p className="eyebrow">Card Payment</p><h2>Take a card payment</h2>
      <p className="subtle-copy">Select a customer and an existing order for {activeTenantCode}. The order supplies the payment reference, amount and currency; standalone payment references are not supported.</p>
    </div></header>
    {error ? <p className="error-banner" role="alert">{error}</p> : null}
    {state === "loading" ? <p role="status">Loading customers and orders...</p> : null}
    {state === "ready" && customers.length === 0 ? <p>No customers are available for this tenant. Open Customers to get started.</p> : null}
    <div className="field-grid">
      <label className="search-field"><span>Customer for payment</span><select value={customerId} disabled={state !== "ready"}
        onChange={event => {setCustomerId(event.target.value);setOrderId("");}}>
        <option value="">Select a customer</option>
        {customers.map(item => <option key={item.customerId} value={item.customerId}>{item.name} — {item.email}</option>)}
      </select></label>
      <label className="search-field"><span>Order for payment</span><select value={orderId} disabled={!customer || orders.length === 0}
        onChange={event => setOrderId(event.target.value)}>
        <option value="">Select an existing order</option>
        {orders.map(item => <option key={item.orderId} value={item.orderId}>ORDER-{item.orderId} — {item.totalPrice.toFixed(2)} {item.currencyCode}</option>)}
      </select></label>
    </div>
    {customer && orders.length === 0 ? <p>No eligible orders for this customer. Create an order first. Paid, cancelled, zero-value or incomplete orders cannot be selected here.</p> : null}
    {selected ? <p role="status">Selected ORDER-{selected.orderId}: {selected.totalPrice.toFixed(2)} {selected.currencyCode}</p> : null}
    <div className="detail-actions">
      <button className="action-button action-button-primary" disabled={!selected} onClick={() => {
        if (selected && customer) navigate(`/customers/${customer.customerId}/orders/${selected.orderId}/payment?tenantCode=${encodeURIComponent(activeTenantCode)}`);
      }}>Continue to payment</button>
      {customer ? <Link className="action-button-link" to={`/customers/${customer.customerId}/orders/new`}>Create an order</Link> : null}
      <Link className="back-link" to="/customers">Browse customers</Link>
      <button className="action-button" disabled={state === "loading"} onClick={() => setReload(value => value + 1)}>Reload orders</button>
    </div>
  </article></section>;
}
