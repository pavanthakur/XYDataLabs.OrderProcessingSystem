import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import type {
  OrderProcessingApiClient,
  PaymentStatusDetails,
  PaymentStatusLookupRequest
} from "@xydatalabs/orderprocessing-api-sdk";
import {
  clearPendingPaymentContext,
  loadPendingPaymentContext,
  trackPaymentEvent
} from "../payment-flow";

type CallbackState = "idle" | "loading" | "ready" | "error";

interface PaymentCallbackPageProps {
  activeTenantCode: string;
  apiClient: OrderProcessingApiClient;
  onTenantChange: (tenantCode: string) => void;
}

export function PaymentCallbackPage({ activeTenantCode, apiClient, onTenantChange }: PaymentCallbackPageProps) {
  const [searchParams] = useSearchParams();
  const [callbackState, setCallbackState] = useState<CallbackState>("idle");
  const [paymentStatus, setPaymentStatus] = useState<PaymentStatusDetails | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const reconciliationKeyRef = useRef<string | null>(null);

  const callbackParameters = useMemo(() => {
    const parameters: Record<string, string> = {};
    searchParams.forEach((value, key) => {
      if (!(key in parameters)) {
        parameters[key] = value;
      }
    });

    return parameters;
  }, [searchParams]);

  const paymentId = resolveFirstValue(callbackParameters, "id", "transaction_id", "payment_id");
  const attemptOrderId = resolveFirstValue(callbackParameters, "order_id", "orderId");
  const callbackStatus = resolveFirstValue(callbackParameters, "status", "transaction_status", "operation_status");
  const callbackError = resolveFirstValue(callbackParameters, "error_message", "error", "message", "description");
  const callbackTenantCode = resolveFirstValue(callbackParameters, "tenantCode");
  const resolvedTenantCode = callbackTenantCode ?? activeTenantCode;
  const pendingContext = useMemo(() => loadPendingPaymentContext(paymentId), [paymentId]);

  useEffect(() => {
    if (callbackTenantCode && callbackTenantCode !== activeTenantCode) {
      onTenantChange(callbackTenantCode);
    }
  }, [activeTenantCode, callbackTenantCode, onTenantChange]);

  useEffect(() => {
    if (!paymentId) {
      setCallbackState("error");
      setErrorMessage("The payment callback did not include a payment identifier.");
      return;
    }

    if (!resolvedTenantCode) {
      setCallbackState("loading");
      return;
    }

    const request: PaymentStatusLookupRequest = {
      attemptOrderId,
      callbackStatus,
      errorMessage: callbackError,
      callbackParameters
    };
    const confirmedPaymentId = paymentId;
    const reconciliationKey = JSON.stringify({ paymentId: confirmedPaymentId, resolvedTenantCode, request });
    if (reconciliationKeyRef.current === reconciliationKey) {
      return;
    }

    reconciliationKeyRef.current = reconciliationKey;

    let isCancelled = false;

    async function reconcileCallback() {
      setCallbackState("loading");
      setErrorMessage(null);

      void trackPaymentEvent({
        eventName: "ui_payment_callback_received",
        severity: "information",
        tenantCode: resolvedTenantCode,
        clientFlowId: pendingContext?.clientFlowId,
        customerOrderId: pendingContext?.customerOrderId,
        attemptOrderId,
        paymentId,
        paymentStatus: callbackStatus,
        errorMessage: callbackError
      }, { useBeacon: true });

      try {
        const nextPaymentStatus = await apiClient.confirmPaymentStatus(confirmedPaymentId, request, resolvedTenantCode);
        if (isCancelled) {
          return;
        }

        setPaymentStatus(nextPaymentStatus);
        setCallbackState("ready");
        clearPendingPaymentContext(confirmedPaymentId);

        void trackPaymentEvent({
          eventName: "ui_payment_callback_reconciled",
          severity: nextPaymentStatus.isFailure ? "warning" : "information",
          tenantCode: resolvedTenantCode,
          clientFlowId: pendingContext?.clientFlowId,
          customerOrderId: nextPaymentStatus.customerOrderId || pendingContext?.customerOrderId,
          attemptOrderId,
          paymentId: confirmedPaymentId,
          paymentStatus: nextPaymentStatus.status,
          statusCategory: nextPaymentStatus.statusCategory,
          errorMessage: nextPaymentStatus.errorMessage
        });
      } catch (error) {
        if (isCancelled) {
          return;
        }

        const nextErrorMessage = error instanceof Error ? error.message : "Unable to reconcile the payment callback.";
        setCallbackState("error");
        setErrorMessage(nextErrorMessage);

        void trackPaymentEvent({
          eventName: "ui_payment_callback_failed",
          severity: "error",
          tenantCode: resolvedTenantCode,
          clientFlowId: pendingContext?.clientFlowId,
          customerOrderId: pendingContext?.customerOrderId,
          attemptOrderId,
          paymentId: confirmedPaymentId,
          paymentStatus: callbackStatus,
          errorMessage: nextErrorMessage
        });
      }
    }

    void reconcileCallback();

    return () => {
      isCancelled = true;
    };
  }, [
    apiClient,
    attemptOrderId,
    callbackError,
    callbackParameters,
    callbackStatus,
    paymentId,
    pendingContext?.clientFlowId,
    pendingContext?.customerOrderId,
    resolvedTenantCode
  ]);

  const bannerClassName = paymentStatus
    ? paymentStatus.isFailure
      ? "error-banner"
      : paymentStatus.isSuccess
        ? "success-banner"
        : "info-banner"
    : "info-banner";
  const continueLink = pendingContext?.customerId && pendingContext?.orderId
    ? `/customers/${pendingContext.customerId}/orders/${pendingContext.orderId}`
    : "/payments/new";
  const continueLabel = pendingContext?.customerId && pendingContext?.orderId
    ? "Return to order"
    : "Start another payment";

  return (
    <section className="route-panel detail-layout">
      <article className="panel">
        <header className="panel-header">
          <div>
            <p className="eyebrow">Payment Callback</p>
            <h2>React status route reconciles the provider callback through the existing Payments API.</h2>
          </div>
          <div className="detail-actions">
            <Link to={continueLink} className="back-link">
              {continueLabel}
            </Link>
          </div>
        </header>

        <dl className="definition-list definition-list-compact">
          <div>
            <dt>Resolved tenant</dt>
            <dd>{resolvedTenantCode || "pending"}</dd>
          </div>
          <div>
            <dt>Callback state</dt>
            <dd>{callbackState}</dd>
          </div>
          <div>
            <dt>Payment id</dt>
            <dd>{paymentId ?? "missing"}</dd>
          </div>
          <div>
            <dt>Attempt order id</dt>
            <dd>{attemptOrderId ?? "not provided"}</dd>
          </div>
          <div>
            <dt>Raw callback status</dt>
            <dd>{callbackStatus ?? "not provided"}</dd>
          </div>
        </dl>

        {errorMessage ? <p className="error-banner">{errorMessage}</p> : null}
        {!errorMessage && paymentStatus ? (
          <p className={bannerClassName}>{paymentStatus.statusMessage}</p>
        ) : null}
        {!errorMessage && callbackState === "loading" ? (
          <p className="info-banner">The React callback route is confirming the final payment status with the API.</p>
        ) : null}

        <section className="callback-layout">
          <article className="detail-card">
            <h3>Confirmed payment status</h3>
            <dl className="definition-list definition-list-single">
              <div>
                <dt>Status</dt>
                <dd>{paymentStatus?.status ?? "pending"}</dd>
              </div>
              <div>
                <dt>Status category</dt>
                <dd>{paymentStatus?.statusCategory ?? "pending"}</dd>
              </div>
              <div>
                <dt>Status source</dt>
                <dd>{paymentStatus?.statusSource ?? "pending"}</dd>
              </div>
              <div>
                <dt>Callback recorded</dt>
                <dd>{paymentStatus ? (paymentStatus.callbackRecorded ? "yes" : "no") : "pending"}</dd>
              </div>
              <div>
                <dt>Remote confirmed</dt>
                <dd>{paymentStatus ? (paymentStatus.remoteStatusConfirmed ? "yes" : "no") : "pending"}</dd>
              </div>
              <div>
                <dt>Reference id</dt>
                <dd>{paymentStatus?.transactionReferenceId ?? "not available"}</dd>
              </div>
            </dl>
          </article>

          <aside className="detail-card order-summary-card">
            <h3>Next step</h3>
            <p className="subtle-copy">
              The provider returned to the API-owned `/payment/callback` endpoint, and that endpoint handed the browser back to this React route so the final status can render without the MVC callback view.
            </p>
            <Link to={continueLink} className="action-button action-button-primary">
              {continueLabel}
            </Link>
          </aside>
        </section>

        <section className="result-panel detail-grid">
          <article className="detail-card">
            <h3>Stored browser context</h3>
            <dl className="definition-list definition-list-single">
              <div>
                <dt>Customer order id</dt>
                <dd>{paymentStatus?.customerOrderId ?? pendingContext?.customerOrderId ?? "not available"}</dd>
              </div>
              <div>
                <dt>Linked customer</dt>
                <dd>{pendingContext?.customerId ?? "manual flow"}</dd>
              </div>
              <div>
                <dt>Linked order</dt>
                <dd>{pendingContext?.orderId ?? "manual flow"}</dd>
              </div>
              <div>
                <dt>Client flow id</dt>
                <dd>{pendingContext?.clientFlowId ?? "not available"}</dd>
              </div>
            </dl>
          </article>

          <article className="detail-card">
            <h3>Callback payload</h3>
            <ul className="callback-debug-list">
              {Object.entries(callbackParameters).map(([key, value]) => (
                <li key={key}>
                  <span>{key}</span>
                  <strong>{value}</strong>
                </li>
              ))}
            </ul>
          </article>
        </section>
      </article>
    </section>
  );
}

function resolveFirstValue(parameters: Record<string, string>, ...keys: string[]): string | null {
  for (const key of keys) {
    const value = parameters[key]?.trim();
    if (value) {
      return value;
    }
  }

  return null;
}