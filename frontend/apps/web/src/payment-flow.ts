export interface PendingPaymentContext {
  customerOrderId?: string | null;
  clientFlowId?: string | null;
  customerId?: number | null;
  orderId?: number | null;
}

const pendingPaymentStorageKeyPrefix = "pending-payment:";

export function createFlowId(): string {
  if (window.crypto?.randomUUID) {
    return window.crypto.randomUUID();
  }

  return `flow-${Date.now()}-${Math.random().toString(16).slice(2, 10)}`;
}

export function persistPendingPaymentContext(paymentId: string, context: PendingPaymentContext) {
  if (!paymentId) {
    return;
  }

  try {
    sessionStorage.setItem(`${pendingPaymentStorageKeyPrefix}${paymentId}`, JSON.stringify(context));
  } catch {
  }
}

export function loadPendingPaymentContext(paymentId: string | null | undefined): PendingPaymentContext | null {
  if (!paymentId) {
    return null;
  }

  try {
    const rawValue = sessionStorage.getItem(`${pendingPaymentStorageKeyPrefix}${paymentId}`);
    if (!rawValue) {
      return null;
    }

    return JSON.parse(rawValue) as PendingPaymentContext;
  } catch {
    return null;
  }
}

export function clearPendingPaymentContext(paymentId: string | null | undefined) {
  if (!paymentId) {
    return;
  }

  try {
    sessionStorage.removeItem(`${pendingPaymentStorageKeyPrefix}${paymentId}`);
  } catch {
  }
}

export function trackPaymentEvent(
  payload: Record<string, unknown>,
  options?: { useBeacon?: boolean }
): Promise<boolean> {
  const body = JSON.stringify({
    eventName: trimValue(payload.eventName, 100),
    severity: trimValue(payload.severity ?? "information", 16),
    tenantCode: trimValue(payload.tenantCode, 64),
    clientFlowId: trimValue(payload.clientFlowId, 64),
    customerOrderId: trimValue(payload.customerOrderId, 128),
    attemptOrderId: trimValue(payload.attemptOrderId, 128),
    paymentId: trimValue(payload.paymentId, 128),
    paymentStatus: trimValue(payload.paymentStatus, 64),
    statusCategory: trimValue(payload.statusCategory, 32),
    errorCode: trimValue(payload.errorCode, 64),
    errorMessage: trimValue(payload.errorMessage, 512),
    pagePath: window.location.pathname,
    clientTimestampUtc: new Date().toISOString()
  });

  const headers: Record<string, string> = {
    "Content-Type": "application/json"
  };

  const tenantCode = trimValue(payload.tenantCode, 64);
  if (tenantCode) {
    headers["X-Tenant-Code"] = tenantCode;
  }

  return fetch("/payment/client-event", {
    method: "POST",
    headers,
    body,
    keepalive: options?.useBeacon === true
  })
    .then(() => true)
    .catch(() => false);
}

function trimValue(value: unknown, maxLength: number): string | null {
  if (value === undefined || value === null) {
    return null;
  }

  const trimmed = String(value).trim();
  if (!trimmed) {
    return null;
  }

  return trimmed.length <= maxLength ? trimmed : trimmed.slice(0, maxLength);
}