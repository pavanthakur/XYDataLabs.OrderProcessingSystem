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

const callbackRetryDelayMs = 2500;
const maxPendingConfirmationAttempts = 4;
const receivedCallbackTelemetryKeys = new Set<string>();
const inFlightReconciliations = new Map<string, Promise<PaymentStatusDetails>>();

interface PaymentCallbackPageProps {
  activeTenantCode: string;
  apiClient: OrderProcessingApiClient;
  onTenantChange: (tenantCode: string) => void;
}

function getOrStartReconciliation(
  reconciliationKey: string,
  factory: () => Promise<PaymentStatusDetails>
): Promise<PaymentStatusDetails> {
  const existingReconciliation = inFlightReconciliations.get(reconciliationKey);
  if (existingReconciliation) {
    return existingReconciliation;
  }

  const reconciliationPromise = factory().finally(() => {
    inFlightReconciliations.delete(reconciliationKey);
  });

  inFlightReconciliations.set(reconciliationKey, reconciliationPromise);
  return reconciliationPromise;
}

export function PaymentCallbackPage({ activeTenantCode, apiClient, onTenantChange }: PaymentCallbackPageProps) {
  const [searchParams] = useSearchParams();
  const [callbackState, setCallbackState] = useState<CallbackState>("idle");
  const [paymentStatus, setPaymentStatus] = useState<PaymentStatusDetails | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [reconciliationAttempt, setReconciliationAttempt] = useState(0);
  const receivedTelemetryKeyRef = useRef<string | null>(null);

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
  const callbackSource = resolveFirstValue(callbackParameters, "source");
  const resolvedTenantCode = callbackTenantCode ?? activeTenantCode;
  const pendingContext = useMemo(() => loadPendingPaymentContext(paymentId), [paymentId]);
  const isDirectStatusEntry = (callbackSource ?? "").toLowerCase() === "direct";
  const visibleCallbackEntries = useMemo(
    () => Object.entries(callbackParameters).filter(([key]) => key !== "source"),
    [callbackParameters]
  );

  useEffect(() => {
    setPaymentStatus(null);
    setErrorMessage(null);
    setCallbackState(paymentId ? "idle" : "error");
    setReconciliationAttempt(0);
    receivedTelemetryKeyRef.current = null;
  }, [paymentId, resolvedTenantCode]);

  useEffect(() => {
    if (!activeTenantCode) {
      return;
    }

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
    const receivedTelemetryKey = JSON.stringify({ paymentId: confirmedPaymentId, resolvedTenantCode, request });
    const reconciliationKey = JSON.stringify({ paymentId: confirmedPaymentId, resolvedTenantCode, request, reconciliationAttempt });

    let isCancelled = false;
    let retryTimeoutId: number | null = null;

    async function reconcileCallback() {
      setCallbackState("loading");
      setErrorMessage(null);

      if (receivedTelemetryKeyRef.current !== receivedTelemetryKey && !receivedCallbackTelemetryKeys.has(receivedTelemetryKey)) {
        receivedTelemetryKeyRef.current = receivedTelemetryKey;
        receivedCallbackTelemetryKeys.add(receivedTelemetryKey);

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
      }

      try {
        const nextPaymentStatus = await getOrStartReconciliation(
          reconciliationKey,
          () => apiClient.confirmPaymentStatus(confirmedPaymentId, request, resolvedTenantCode)
        );
        if (isCancelled) {
          return;
        }

        setPaymentStatus(nextPaymentStatus);

        if (nextPaymentStatus.isPending && reconciliationAttempt < maxPendingConfirmationAttempts - 1) {
          retryTimeoutId = window.setTimeout(() => {
            setReconciliationAttempt((currentAttempt) => currentAttempt + 1);
          }, callbackRetryDelayMs);

          void trackPaymentEvent({
            eventName: "ui_payment_callback_pending_retry_scheduled",
            severity: "information",
            tenantCode: resolvedTenantCode,
            clientFlowId: pendingContext?.clientFlowId,
            customerOrderId: nextPaymentStatus.customerOrderId || pendingContext?.customerOrderId,
            attemptOrderId,
            paymentId: confirmedPaymentId,
            paymentStatus: nextPaymentStatus.status,
            statusCategory: nextPaymentStatus.statusCategory,
            errorMessage: nextPaymentStatus.errorMessage
          });

          return;
        }

        setCallbackState("ready");
        if (!nextPaymentStatus.isPending) {
          clearPendingPaymentContext(confirmedPaymentId);
        }

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
      if (retryTimeoutId !== null) {
        window.clearTimeout(retryTimeoutId);
      }
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
    reconciliationAttempt,
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
  const retrySummary = formatRetrySummary(reconciliationAttempt, callbackState, paymentStatus?.isPending ?? false);
  const showRetrySummary = paymentStatus?.isPending || reconciliationAttempt > 0;
  const customerContextValue = pendingContext?.customerId ? `Customer #${pendingContext.customerId}` : "Standalone payment";
  const orderContextValue = pendingContext?.orderId ? `Order #${pendingContext.orderId}` : "Standalone payment";

  return (
    <section className="route-panel detail-layout">
      <article className="panel">
        <header className="panel-header">
          <div>
            <p className="eyebrow">Payment Status</p>
            <h2>Review the final payment outcome.</h2>
          </div>
        </header>

        <dl className="definition-list definition-list-compact">
          <div>
            <dt>Payment ID</dt>
            <dd>{paymentId ?? "missing"}</dd>
          </div>
          {!isDirectStatusEntry ? (
            <div>
              <dt>Provider order reference</dt>
              <dd>{attemptOrderId ?? "Not provided by provider"}</dd>
            </div>
          ) : null}
          {!isDirectStatusEntry ? (
            <div>
              <dt>Provider callback status</dt>
              <dd>{callbackStatus ?? "Not provided by provider"}</dd>
            </div>
          ) : null}
        </dl>

        {errorMessage ? <p className="error-banner">{errorMessage}</p> : null}
        {!errorMessage && paymentStatus ? (
          <p className={bannerClassName}>{paymentStatus.statusMessage}</p>
        ) : null}
        {!errorMessage && callbackState === "loading" ? (
          <div className="loading-progress-panel info-banner" role="status" aria-live="polite">
            <span className="loading-spinner" aria-hidden="true" />
            <div>
              <strong>
                {paymentStatus?.isPending
                  ? "Waiting for the provider to finish confirmation."
                  : "Confirming the final payment status with the payment service."}
              </strong>
              <p>
                {paymentStatus?.isPending
                  ? `Retry ${reconciliationAttempt + 1} of ${maxPendingConfirmationAttempts} will run automatically in a moment.`
                  : "The browser returned before the provider had fully settled the charge, so the callback page is holding the user here until reconciliation completes."}
              </p>
            </div>
          </div>
        ) : null}

        <section className="callback-layout">
          <article className="detail-card">
            <h3>Confirmed payment status</h3>
            <dl className="definition-list definition-list-single">
              <div>
                <dt>Status</dt>
                <dd>{paymentStatus?.status ?? "Pending confirmation"}</dd>
              </div>
              <div>
                <dt>Status category</dt>
                <dd>{paymentStatus?.statusCategory ?? "Awaiting provider confirmation"}</dd>
              </div>
              <div>
                <dt>Confirmation source</dt>
                <dd>{formatStatusSource(paymentStatus?.statusSource)}</dd>
              </div>
              {!isDirectStatusEntry ? (
                <div>
                  <dt>Callback payload received</dt>
                  <dd>{paymentStatus ? (paymentStatus.callbackRecorded ? "Yes" : "No") : "Waiting"}</dd>
                </div>
              ) : null}
              <div>
                <dt>Provider confirmed</dt>
                <dd>{paymentStatus ? (paymentStatus.remoteStatusConfirmed ? "Yes" : "No") : "Waiting"}</dd>
              </div>
              <div>
                <dt>Authorization reference</dt>
                <dd>{paymentStatus?.transactionReferenceId ?? "Not available"}</dd>
              </div>
              {showRetrySummary ? (
                <div>
                  <dt>Confirmation retries</dt>
                  <dd>{retrySummary}</dd>
                </div>
              ) : null}
            </dl>
          </article>

          <aside className="detail-card order-summary-card">
            <h3>Next step</h3>
            <p className="subtle-copy">
              {isDirectStatusEntry
                ? "This payment completed without an additional verification step, and the final result is now available for review."
                : "The payment provider returned control to this status page after verification, and the final result is now available for review."}
            </p>
            <Link to={continueLink} className="action-button action-button-primary">
              {continueLabel}
            </Link>
          </aside>
        </section>

        <section className="result-panel detail-grid">
          <article className="detail-card">
            <h3>Payment context</h3>
            <dl className="definition-list definition-list-single">
              <div>
                <dt>Customer order ID</dt>
                <dd>{paymentStatus?.customerOrderId ?? pendingContext?.customerOrderId ?? "Not available"}</dd>
              </div>
              <div>
                <dt>Customer context</dt>
                <dd>{customerContextValue}</dd>
              </div>
              <div>
                <dt>Order context</dt>
                <dd>{orderContextValue}</dd>
              </div>
            </dl>
          </article>

          {!isDirectStatusEntry ? (
            <article className="detail-card">
              <h3>Provider return details</h3>
              <ul className="callback-debug-list">
                {visibleCallbackEntries.map(([key, value]) => (
                  <li key={key}>
                    <span>{key}</span>
                    <strong>{value}</strong>
                  </li>
                ))}
              </ul>
            </article>
          ) : null}
        </section>

        <details className="technical-details">
          <summary>Technical details</summary>
          <dl className="definition-list definition-list-single technical-details-list">
            <div>
              <dt>Resolved tenant</dt>
              <dd>{resolvedTenantCode || "Pending"}</dd>
            </div>
            <div>
              <dt>Page state</dt>
              <dd>{formatCallbackState(callbackState)}</dd>
            </div>
            <div>
              <dt>Client flow ID</dt>
              <dd>{pendingContext?.clientFlowId ?? "Not available"}</dd>
            </div>
          </dl>
        </details>
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

function formatCallbackState(value: CallbackState): string {
  switch (value) {
    case "idle":
      return "Waiting to start";
    case "loading":
      return "Confirming payment";
    case "ready":
      return "Completed";
    case "error":
      return "Attention needed";
    default:
      return value;
  }
}

function formatStatusSource(value: string | null | undefined): string {
  switch ((value ?? "").toLowerCase()) {
    case "openpay":
      return "Provider confirmation (OpenPay)";
    case "callback":
      return "Provider callback payload";
    case "database":
      return "Local transaction record";
    default:
      return value ?? "Waiting";
  }
}

function formatRetrySummary(
  reconciliationAttempt: number,
  callbackState: CallbackState,
  isPending: boolean
): string {
  const attemptsUsed = Math.min(reconciliationAttempt, maxPendingConfirmationAttempts);

  if (!isPending && attemptsUsed === 0) {
    return "Not needed";
  }

  if (isPending && callbackState === "loading") {
    const activeAttempt = Math.min(reconciliationAttempt + 1, maxPendingConfirmationAttempts);
    return `${activeAttempt} of ${maxPendingConfirmationAttempts} in progress`;
  }

  return `${attemptsUsed} of ${maxPendingConfirmationAttempts} used`;
}