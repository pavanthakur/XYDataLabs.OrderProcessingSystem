import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import type { OrderDetail, OrderProcessingApiClient, PaymentResult } from "@xydatalabs/orderprocessing-api-sdk";
import { createFlowId, persistPendingPaymentContext, trackPaymentEvent } from "../payment-flow";

type LoadState = "idle" | "loading" | "ready" | "error";
type SubmitState = "idle" | "submitting" | "success" | "error";

interface PaymentPageProps {
  activeTenantCode: string;
  apiClient: OrderProcessingApiClient;
}

interface PaymentFormState {
  name: string;
  email: string;
  customerOrderId: string;
  cardNumber: string;
  expirationMonth: string;
  expirationYear: string;
  cvv2: string;
}

const openPayMerchantId = "mt2ummntdjhxgoeycbgj";
const openPayPublicKey = "pk_4881b1c79b064f7397685d7d491c7338";

export function PaymentPage({ activeTenantCode, apiClient }: PaymentPageProps) {
  const params = useParams<{ customerId: string; orderId: string }>();
  const customerId = Number(params.customerId);
  const orderId = Number(params.orderId);
  const hasOrderRouteContext = params.orderId !== undefined;
  const hasValidOrderContext = Number.isInteger(orderId) && orderId > 0;
  const hasValidCustomerContext = Number.isInteger(customerId) && customerId > 0;
  const [order, setOrder] = useState<OrderDetail | null>(null);
  const [deviceSessionId, setDeviceSessionId] = useState<string>("");
  const [loadState, setLoadState] = useState<LoadState>("idle");
  const [submitState, setSubmitState] = useState<SubmitState>("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [paymentMessage, setPaymentMessage] = useState<string | null>(null);
  const [paymentResult, setPaymentResult] = useState<PaymentResult | null>(null);
  const [formState, setFormState] = useState<PaymentFormState>({
    name: "",
    email: "",
    customerOrderId: buildCustomerOrderId(orderId, hasOrderRouteContext),
    cardNumber: "",
    expirationMonth: "",
    expirationYear: "",
    cvv2: ""
  });

  useEffect(() => {
    if (!hasOrderRouteContext) {
      return;
    }

    setFormState((current) => ({
      ...current,
      customerOrderId: buildCustomerOrderId(orderId, hasOrderRouteContext)
    }));
  }, [hasOrderRouteContext, orderId]);

  useEffect(() => {
    if (!activeTenantCode) {
      return;
    }

    if (!hasOrderRouteContext) {
      setOrder(null);
      setLoadState("ready");
      return;
    }

    if (!hasValidOrderContext) {
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

        setLoadState("error");
        setErrorMessage(error instanceof Error ? error.message : "Unable to load the order for payment.");
      }
    }

    void loadOrder();

    return () => {
      isCancelled = true;
    };
  }, [activeTenantCode, apiClient, hasOrderRouteContext, hasValidOrderContext, orderId]);

  useEffect(() => {
    if (!activeTenantCode) {
      return;
    }

    try {
      const openPay = getOpenPay();
      openPay.setId(openPayMerchantId);
      openPay.setApiKey(openPayPublicKey);
      openPay.setSandboxMode(true);
      const nextDeviceSessionId = openPay.deviceData.setup("payment-form", "deviceIdHiddenFieldName");
      setDeviceSessionId(nextDeviceSessionId);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "OpenPay initialization failed.");
      void trackPaymentEvent({
        eventName: "ui_payment_device_setup_failed",
        severity: "error",
        tenantCode: activeTenantCode,
        errorMessage: error instanceof Error ? error.message : "OpenPay initialization failed."
      });
    }
  }, [activeTenantCode]);

  const totalPrice = useMemo(() => order?.totalPrice ?? 0, [order]);

  function updateFormState<K extends keyof PaymentFormState>(key: K, value: PaymentFormState[K]) {
    setFormState((current) => ({
      ...current,
      [key]: value
    }));
  }

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!activeTenantCode) {
      setErrorMessage("Tenant runtime configuration is unavailable.");
      return;
    }

    if (!deviceSessionId) {
      setErrorMessage("OpenPay device session is unavailable.");
      return;
    }

    const clientFlowId = createFlowId();

    setSubmitState("submitting");
    setErrorMessage(null);
    setPaymentMessage(null);
    setPaymentResult(null);

    void trackPaymentEvent({
      eventName: "ui_payment_submit_started",
      severity: "information",
      tenantCode: activeTenantCode,
      clientFlowId,
      customerOrderId: formState.customerOrderId
    });

    try {
      const payment = await apiClient.processPayment({
        name: formState.name,
        email: formState.email,
        deviceSessionId,
        cardNumber: formState.cardNumber.replace(/\s/g, ""),
        expirationYear: formState.expirationYear,
        expirationMonth: formState.expirationMonth,
        cvv2: formState.cvv2,
        customerOrderId: formState.customerOrderId
      });
      setPaymentResult(payment);

      const normalizedStatus = (payment.status || "").toLowerCase();

      if (normalizedStatus === "charge_pending" && payment.threeDSecureUrl) {
        persistPendingPaymentContext(payment.id, {
          customerOrderId: payment.customerOrderId,
          clientFlowId,
          customerId: hasValidCustomerContext ? customerId : null,
          orderId: hasValidOrderContext ? orderId : null
        });

        void trackPaymentEvent({
          eventName: "ui_payment_3ds_redirect_started",
          severity: "information",
          tenantCode: activeTenantCode,
          clientFlowId,
          customerOrderId: payment.customerOrderId,
          paymentId: payment.id,
          paymentStatus: payment.status,
          statusCategory: payment.threeDSecureStage
        }, { useBeacon: true });

        setPaymentMessage("3D Secure verification is required. Redirecting to the provider now.");
        window.location.assign(payment.threeDSecureUrl);
        return;
      }

      setSubmitState("success");
      setPaymentMessage(`Payment request completed with status ${payment.status}.`);

      void trackPaymentEvent({
        eventName: "ui_payment_completed",
        severity: "information",
        tenantCode: activeTenantCode,
        clientFlowId,
        customerOrderId: payment.customerOrderId,
        paymentId: payment.id,
        paymentStatus: payment.status,
        statusCategory: payment.threeDSecureStage
      });
    } catch (error) {
      setSubmitState("error");
      const nextErrorMessage = error instanceof Error ? error.message : "Payment processing failed.";
      setErrorMessage(nextErrorMessage);

      void trackPaymentEvent({
        eventName: "ui_payment_processing_failed",
        severity: "warning",
        tenantCode: activeTenantCode,
        clientFlowId,
        customerOrderId: formState.customerOrderId,
        errorMessage: nextErrorMessage
      });
    }
  }

  return (
    <section className="route-panel detail-layout">
      <article className="panel">
        <header className="panel-header">
          <div>
            <p className="eyebrow">Payment Initiation</p>
            <h2>{order ? `Charge order #${order.orderId}` : "React payment workspace"}</h2>
          </div>
          <div className="detail-actions">
            {hasValidOrderContext && hasValidCustomerContext ? (
              <Link to={`/customers/${customerId}/orders/${orderId}`} className="back-link">
                Back to order
              </Link>
            ) : null}
            {hasValidCustomerContext ? (
              <Link to={`/customers/${customerId}`} className="back-link">
                Back to customer
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
            <dt>Order state</dt>
            <dd>{loadState}</dd>
          </div>
          <div>
            <dt>Payment mode</dt>
            <dd>{hasValidOrderContext ? "Order-linked" : "Manual"}</dd>
          </div>
          <div>
            <dt>Submit state</dt>
            <dd>{submitState}</dd>
          </div>
          <div>
            <dt>Device session</dt>
            <dd>{deviceSessionId ? "ready" : "pending"}</dd>
          </div>
        </dl>

        {errorMessage ? <p className="error-banner">{errorMessage}</p> : null}
        {paymentMessage ? <p className="success-banner">{paymentMessage}</p> : null}

        <form id="payment-form" className="payment-layout" onSubmit={handleSubmit}>
          <section className="detail-card">
            <h3>Payment information</h3>
            <p className="subtle-copy">
              {hasValidOrderContext
                ? "This route replaces the old MVC payment entry from an order context and posts directly to the existing Payments API."
                : "This manual payment route replaces the old standalone MVC payment form while keeping the provider return path on the server-owned /payment surface."}
            </p>
            <div className="field-grid">
              <label className="search-field">
                <span>Cardholder name</span>
                <input
                  value={formState.name}
                  onChange={(event) => updateFormState("name", event.target.value)}
                  autoComplete="cc-name"
                  required
                />
              </label>
              <label className="search-field">
                <span>Email</span>
                <input
                  type="email"
                  value={formState.email}
                  onChange={(event) => updateFormState("email", event.target.value)}
                  autoComplete="email"
                  required
                />
              </label>
              <label className="search-field field-span-full">
                <span>Customer order id</span>
                <input
                  value={formState.customerOrderId}
                  onChange={(event) => updateFormState("customerOrderId", event.target.value)}
                  required
                />
              </label>
              <label className="search-field field-span-full">
                <span>Card number</span>
                <input
                  value={formState.cardNumber}
                  onChange={(event) => updateFormState("cardNumber", formatCardNumber(event.target.value))}
                  autoComplete="cc-number"
                  inputMode="numeric"
                  required
                />
              </label>
              <label className="search-field">
                <span>Expiry month</span>
                <input
                  value={formState.expirationMonth}
                  onChange={(event) => updateFormState("expirationMonth", normalizeMonth(event.target.value))}
                  autoComplete="cc-exp-month"
                  inputMode="numeric"
                  maxLength={2}
                  required
                />
              </label>
              <label className="search-field">
                <span>Expiry year</span>
                <input
                  value={formState.expirationYear}
                  onChange={(event) => updateFormState("expirationYear", normalizeYear(event.target.value))}
                  autoComplete="cc-exp-year"
                  inputMode="numeric"
                  maxLength={2}
                  required
                />
              </label>
              <label className="search-field">
                <span>CVV</span>
                <input
                  value={formState.cvv2}
                  onChange={(event) => updateFormState("cvv2", event.target.value.replace(/\D/g, "").slice(0, 4))}
                  autoComplete="cc-csc"
                  inputMode="numeric"
                  maxLength={4}
                  required
                />
              </label>
            </div>
          </section>

          <aside className="detail-card order-summary-card">
            <h3>Charge summary</h3>
            <dl className="definition-list definition-list-single">
              <div>
                <dt>Customer id</dt>
                <dd>{hasValidCustomerContext ? customerId : "Manual flow"}</dd>
              </div>
              <div>
                <dt>Order id</dt>
                <dd>{hasValidOrderContext ? orderId : "Manual flow"}</dd>
              </div>
              <div>
                <dt>Total amount</dt>
                <dd>{hasValidOrderContext ? formatCurrency(totalPrice) : "Calculated by payment provider"}</dd>
              </div>
            </dl>

            <p className="subtle-copy">
              Client telemetry posts to the API-owned `/payment/client-event` endpoint, and provider callbacks return through API-owned `/payment/callback` before landing on the React status route.
            </p>

            <button
              type="submit"
              className="action-button action-button-primary"
              disabled={submitState === "submitting" || !deviceSessionId || loadState !== "ready"}
            >
              {submitState === "submitting" ? "Processing payment..." : "Process payment"}
            </button>
          </aside>
        </form>

        {paymentResult ? (
          <section className="result-panel detail-grid">
            <article className="detail-card">
              <h3>Payment result</h3>
              <dl className="definition-list definition-list-single">
                <div>
                  <dt>Payment id</dt>
                  <dd>{paymentResult.id}</dd>
                </div>
                <div>
                  <dt>Customer order id</dt>
                  <dd>{paymentResult.customerOrderId}</dd>
                </div>
                <div>
                  <dt>Status</dt>
                  <dd>{paymentResult.status}</dd>
                </div>
                <div>
                  <dt>3DS stage</dt>
                  <dd>{paymentResult.threeDSecureStage || "not-required"}</dd>
                </div>
              </dl>
            </article>
            <article className="detail-card">
              <h3>Next step</h3>
              <p className="subtle-copy">
                {paymentResult.threeDSecureUrl
                  ? "The provider may redirect this browser through 3D Secure verification. The browser will return through the API-owned callback path and land on the React callback route for final status rendering."
                  : "This payment completed without a provider redirect. The React page now holds the immediate result state instead of handing the user back to the old MVC form."}
              </p>
            </article>
          </section>
        ) : null}
      </article>
    </section>
  );
}

function buildCustomerOrderId(orderId: number, hasOrderRouteContext: boolean): string {
  if (hasOrderRouteContext && Number.isInteger(orderId) && orderId > 0) {
    return `ORDER-${orderId}`;
  }

  return `PAY-${new Date().toISOString().slice(0, 10).replace(/-/g, "")}-${Math.random().toString(16).slice(2, 8).toUpperCase()}`;
}

function formatCardNumber(value: string): string {
  return value
    .replace(/\D/g, "")
    .slice(0, 16)
    .replace(/(\d{4})(?=\d)/g, "$1 ")
    .trim();
}

function normalizeMonth(value: string): string {
  const digitsOnly = value.replace(/\D/g, "").slice(0, 2);
  if (digitsOnly.length === 0) {
    return "";
  }

  const month = Number(digitsOnly);
  if (Number.isNaN(month) || month <= 0) {
    return "01";
  }

  return String(Math.min(month, 12)).padStart(2, "0");
}

function normalizeYear(value: string): string {
  return value.replace(/\D/g, "").slice(0, 2);
}

function formatCurrency(value: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD"
  }).format(value);
}

function getOpenPay(): NonNullable<OpenPayWindow["OpenPay"]> {
  const globalWindow = window as Window & OpenPayWindow;
  if (!globalWindow.OpenPay) {
    throw new Error("OpenPay browser SDK is unavailable.");
  }

  return globalWindow.OpenPay;
}
interface OpenPayWindow {
  OpenPay?: {
    setId(value: string): void;
    setApiKey(value: string): void;
    setSandboxMode(value: boolean): void;
    deviceData: {
      setup(formId: string, fieldName: string): string;
    };
  };
}