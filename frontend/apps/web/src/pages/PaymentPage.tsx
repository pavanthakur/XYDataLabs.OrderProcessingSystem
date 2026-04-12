import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import type { OrderDetail, OrderProcessingApiClient } from "@xydatalabs/orderprocessing-api-sdk";
import { createFlowId, persistPendingPaymentContext, trackPaymentEvent } from "../payment-flow";

type LoadState = "idle" | "loading" | "ready" | "error";
type SubmitState = "idle" | "submitting" | "redirecting" | "success" | "error";

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

interface ThreeDSRedirectState {
  targetUrl: string;
  paymentId: string;
  customerOrderId: string;
}

const openPayMerchantId = "mt2ummntdjhxgoeycbgj";
const openPayPublicKey = "pk_4881b1c79b064f7397685d7d491c7338";
const threeDSecureRedirectDelayMs = 1200;

export function PaymentPage({ activeTenantCode, apiClient }: PaymentPageProps) {
  const navigate = useNavigate();
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
  const [threeDSRedirectState, setThreeDSRedirectState] = useState<ThreeDSRedirectState | null>(null);
  const [redirectCountdownMs, setRedirectCountdownMs] = useState<number>(0);
  const [formState, setFormState] = useState<PaymentFormState>({
    name: "",
    email: "",
    customerOrderId: buildCustomerOrderId(orderId, hasOrderRouteContext),
    cardNumber: "",
    expirationMonth: "",
    expirationYear: "",
    cvv2: ""
  });
  const isManualFlow = !hasValidOrderContext;

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

  useEffect(() => {
    if (!threeDSRedirectState) {
      setRedirectCountdownMs(0);
      return;
    }

    const redirectStartedAt = Date.now();
    setRedirectCountdownMs(threeDSecureRedirectDelayMs);

    const countdownIntervalId = window.setInterval(() => {
      const elapsedMs = Date.now() - redirectStartedAt;
      setRedirectCountdownMs(Math.max(0, threeDSecureRedirectDelayMs - elapsedMs));
    }, 100);

    const redirectTimeoutId = window.setTimeout(() => {
      window.location.assign(threeDSRedirectState.targetUrl);
    }, threeDSecureRedirectDelayMs);

    return () => {
      window.clearInterval(countdownIntervalId);
      window.clearTimeout(redirectTimeoutId);
    };
  }, [threeDSRedirectState]);

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
    setThreeDSRedirectState(null);

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
        customerOrderId: formState.customerOrderId,
        clientCallbackOrigin: window.location.origin
      });

      persistPendingPaymentContext(payment.id, {
        customerOrderId: payment.customerOrderId,
        clientFlowId,
        customerId: hasValidCustomerContext ? customerId : null,
        orderId: hasValidOrderContext ? orderId : null
      });

      const normalizedStatus = (payment.status || "").toLowerCase();

      if (normalizedStatus === "charge_pending" && payment.threeDSecureUrl) {
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

        setSubmitState("redirecting");
        setThreeDSRedirectState({
          targetUrl: payment.threeDSecureUrl,
          paymentId: payment.id,
          customerOrderId: payment.customerOrderId
        });
        return;
      }

      setSubmitState("success");

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

      const summarySearchParams = new URLSearchParams({
        tenantCode: activeTenantCode,
        id: payment.id,
        source: "direct"
      });

      if (payment.status) {
        summarySearchParams.set("status", payment.status);
      }

      navigate(`/payments/callback?${summarySearchParams.toString()}`, { replace: true });
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
          <div className="payment-header-copy">
            <p className="eyebrow">Card Payment</p>
            <h2>{order ? `Collect payment for order #${order.orderId}` : "Take a card payment"}</h2>
            <p className="subtle-copy">
              {order
                ? "Review the order amount, capture the card details, and continue through secure verification only when the provider requires it."
                : "Create a standalone card payment with a clear customer reference and a secure provider-managed verification step when needed."}
            </p>
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

        {errorMessage ? <p className="error-banner">{errorMessage}</p> : null}

        {threeDSRedirectState ? (
          <section className="redirect-transition-card detail-card" role="status" aria-live="polite">
            <div className="loading-progress-panel">
              <span className="loading-spinner" aria-hidden="true" />
              <div>
                <p className="eyebrow">3D Secure Redirect</p>
                <h3>Opening the provider OTP challenge</h3>
                <p className="subtle-copy">
                  Secure verification is required for this payment. The browser will move to the provider challenge automatically in {formatRedirectCountdown(redirectCountdownMs)} seconds.
                </p>
              </div>
            </div>

            <dl className="definition-list definition-list-single redirect-transition-list">
              <div>
                <dt>Payment id</dt>
                <dd>{threeDSRedirectState.paymentId}</dd>
              </div>
              <div>
                <dt>Customer order id</dt>
                <dd>{threeDSRedirectState.customerOrderId}</dd>
              </div>
            </dl>

            <a href={threeDSRedirectState.targetUrl} className="action-button-link action-button-link-primary">
              Continue to secure verification now
            </a>
          </section>
        ) : (
          <form id="payment-form" className="payment-layout" onSubmit={handleSubmit}>
            <section className="detail-card">
              <div className="form-section">
                <p className="section-kicker">Contact</p>
                <h3>Payer details</h3>
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
                </div>
              </div>

              <div className="form-section">
                <p className="section-kicker">Reference</p>
                <h3>Payment reference</h3>
                <p className="subtle-copy">
                  Use a reference your operations team can trace later in reconciliation, statements, and callback reviews.
                </p>
                <div className="field-grid">
                  <label className="search-field field-span-full">
                    <span>Customer order id</span>
                    <input
                      value={formState.customerOrderId}
                      onChange={(event) => updateFormState("customerOrderId", event.target.value)}
                      required
                    />
                  </label>
                </div>
              </div>

              <div className="form-section">
                <p className="section-kicker">Card details</p>
                <h3>Payment information</h3>
                <div className="field-grid">
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
                      onChange={(event) => updateFormState("expirationMonth", sanitizeMonthInput(event.target.value))}
                      onBlur={(event) => updateFormState("expirationMonth", normalizeMonth(event.target.value))}
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
              </div>
            </section>

            <aside className="detail-card order-summary-card">
              <p className="section-kicker">Summary</p>
              <h3>Payment summary</h3>
              <p className="subtle-copy">
                The cardholder is sent to an additional verification step only when the provider requests 3D Secure for this transaction.
              </p>
              <dl className="definition-list definition-list-single">
                <div>
                  <dt>Reference</dt>
                  <dd>{formState.customerOrderId}</dd>
                </div>
                <div>
                  <dt>Customer context</dt>
                  <dd>{hasValidCustomerContext ? `Customer #${customerId}` : "Standalone payment"}</dd>
                </div>
                <div>
                  <dt>Order context</dt>
                  <dd>{hasValidOrderContext ? `Order #${orderId}` : "Standalone payment"}</dd>
                </div>
                <div>
                  <dt>Amount</dt>
                  <dd>{hasValidOrderContext ? formatCurrency(totalPrice) : "Determined by the payment provider"}</dd>
                </div>
                <div>
                  <dt>Verification</dt>
                  <dd>3D Secure when required</dd>
                </div>
              </dl>

              <p className="subtle-copy payment-trust-copy">
                Card details stay inside the secure payment flow, and the callback page brings the browser back with the final payment result.
              </p>

              <button
                type="submit"
                className="action-button action-button-primary"
                disabled={submitState === "submitting" || submitState === "redirecting" || !deviceSessionId || loadState !== "ready"}
              >
                {submitState === "submitting"
                  ? "Processing payment..."
                  : submitState === "redirecting"
                    ? "Opening 3D Secure..."
                    : "Process payment"}
              </button>
            </aside>
          </form>
        )}

        <details className="technical-details">
          <summary>Technical details</summary>
          <dl className="definition-list definition-list-single technical-details-list">
            <div>
              <dt>Resolved tenant</dt>
              <dd>{activeTenantCode || "Pending"}</dd>
            </div>
            <div>
              <dt>Order load state</dt>
              <dd>{formatLoadState(loadState)}</dd>
            </div>
            <div>
              <dt>Payment mode</dt>
              <dd>{isManualFlow ? "Standalone" : "Order-linked"}</dd>
            </div>
            <div>
              <dt>Submission state</dt>
              <dd>{formatSubmitState(submitState)}</dd>
            </div>
            <div>
              <dt>Device session</dt>
              <dd>{deviceSessionId ? "Ready" : "Pending"}</dd>
            </div>
          </dl>
        </details>
      </article>
    </section>
  );
}

function formatRedirectCountdown(valueMs: number): string {
  const seconds = Math.max(0, valueMs) / 1000;
  return seconds.toFixed(seconds >= 1 ? 1 : 1);
}

function formatLoadState(value: LoadState): string {
  switch (value) {
    case "idle":
      return "Not started";
    case "loading":
      return "Loading";
    case "ready":
      return "Ready";
    case "error":
      return "Needs attention";
    default:
      return value;
  }
}

function formatSubmitState(value: SubmitState): string {
  switch (value) {
    case "idle":
      return "Ready";
    case "submitting":
      return "Submitting";
    case "redirecting":
      return "Redirecting to 3D Secure";
    case "success":
      return "Completed";
    case "error":
      return "Needs attention";
    default:
      return value;
  }
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
  const digitsOnly = sanitizeMonthInput(value);
  if (digitsOnly.length === 0) {
    return "";
  }

  if (digitsOnly.length === 1) {
    const singleDigitMonth = Number(digitsOnly);
    if (Number.isNaN(singleDigitMonth) || singleDigitMonth <= 0) {
      return "01";
    }

    return digitsOnly.padStart(2, "0");
  }

  const month = Number(digitsOnly);
  if (Number.isNaN(month) || month <= 0) {
    return "01";
  }

  return String(Math.min(month, 12)).padStart(2, "0");
}

function sanitizeMonthInput(value: string): string {
  return value.replace(/\D/g, "").slice(0, 2);
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