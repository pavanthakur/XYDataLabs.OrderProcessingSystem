window.OrderProcessingUiTelemetry = (() => {
    const defaultTenantHeaderName = 'X-Tenant-Code';
    const resolveApiBaseUrl = () => document.body?.dataset?.apiBaseUrl?.replace(/\/$/, '') || '';
    const resolveEndpointPath = () => {
        const apiBaseUrl = resolveApiBaseUrl();
        return apiBaseUrl ? `${apiBaseUrl}/payment/client-event` : '/payment/client-event';
    };

    const createFlowId = () => {
        if (window.crypto?.randomUUID) {
            return window.crypto.randomUUID();
        }

        return `flow-${Date.now()}-${Math.random().toString(16).slice(2, 10)}`;
    };

    const trimValue = (value, maxLength) => {
        if (value === undefined || value === null) {
            return null;
        }

        const trimmed = value.toString().trim();
        if (!trimmed) {
            return null;
        }

        return trimmed.length <= maxLength ? trimmed : trimmed.slice(0, maxLength);
    };

    const buildPayload = payload => ({
        eventName: trimValue(payload.eventName, 100),
        severity: trimValue(payload.severity || 'information', 16),
        tenantCode: trimValue(payload.tenantCode, 64),
        clientFlowId: trimValue(payload.clientFlowId, 64),
        customerOrderId: trimValue(payload.customerOrderId, 128),
        attemptOrderId: trimValue(payload.attemptOrderId, 128),
        paymentId: trimValue(payload.paymentId, 128),
        paymentStatus: trimValue(payload.paymentStatus, 64),
        statusCategory: trimValue(payload.statusCategory, 32),
        httpStatus: Number.isInteger(payload.httpStatus) ? payload.httpStatus : null,
        errorCode: trimValue(payload.errorCode, 64),
        errorMessage: trimValue(payload.errorMessage, 512),
        pagePath: trimValue(payload.pagePath || window.location.pathname, 256),
        clientTimestampUtc: new Date().toISOString()
    });

    const track = (payload, options = {}) => {
        const normalizedPayload = buildPayload(payload || {});
        if (!normalizedPayload.eventName) {
            return Promise.resolve(false);
        }

        const body = JSON.stringify(normalizedPayload);

        const tenantHeaderName = window.OrderProcessingTenant?.getTenantHeaderName?.() || defaultTenantHeaderName;
        const headers = {
            'Content-Type': 'application/json'
        };

        if (normalizedPayload.tenantCode) {
            headers[tenantHeaderName] = normalizedPayload.tenantCode;
        }

        return fetch(resolveEndpointPath(), {
            method: 'POST',
            headers,
            body,
            keepalive: options.keepalive === true || options.useBeacon === true
        })
            .then(() => true)
            .catch(error => {
                console.warn('Unable to persist UI payment telemetry event.', error);
                return false;
            });
    };

    return {
        createFlowId,
        track
    };
})();