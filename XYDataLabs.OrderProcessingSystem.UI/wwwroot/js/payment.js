// Initialize device session ID when the page loads
let deviceSessionId;
const payButton = document.getElementById('pay-button');
const pendingPaymentStorageKeyPrefix = 'pending-payment:';
let runtimeConfigurationPromise;

const trackPaymentEvent = (payload, options) =>
    window.OrderProcessingUiTelemetry?.track(payload, options) || Promise.resolve(false);

const setPayButtonState = (enabled, text) => {
    if (!payButton) {
        return;
    }

    payButton.disabled = !enabled;
    payButton.textContent = text;
};

const getTenantRuntime = () => {
    if (!window.OrderProcessingTenant) {
        return Promise.reject(new Error('Tenant bootstrap script is unavailable.'));
    }

    return window.OrderProcessingTenant.ready();
};

const persistPendingPaymentContext = payment => {
    if (!payment?.id) {
        return;
    }

    try {
        sessionStorage.setItem(`${pendingPaymentStorageKeyPrefix}${payment.id}`, JSON.stringify({
            attemptOrderId: payment.attemptOrderId || null,
            customerOrderId: payment.customerOrderId || null,
            clientFlowId: payment.clientFlowId || null
        }));
    } catch (error) {
        console.warn('Unable to persist pending payment context before 3DS redirect.', error);
    }
};

if (payButton) {
    setPayButtonState(false, 'Loading tenant configuration...');
    runtimeConfigurationPromise = getTenantRuntime()
        .then(runtimeConfiguration => {
            setPayButtonState(true, 'Process Payment');
            return runtimeConfiguration;
        })
        .catch(error => {
            setPayButtonState(false, 'Tenant configuration unavailable');
            void trackPaymentEvent({
                eventName: 'ui_payment_runtime_unavailable',
                severity: 'warning',
                errorMessage: error.message || 'Tenant runtime configuration unavailable.'
            });
            console.error('Unable to load tenant runtime configuration from API:', error);
            throw error;
        });
}

window.addEventListener('load', function () {
    try {
        // Initialize OpenPay with sandbox credentials
        OpenPay.setId('mt2ummntdjhxgoeycbgj');
        OpenPay.setApiKey('pk_4881b1c79b064f7397685d7d491c7338');
        OpenPay.setSandboxMode(true);
        deviceSessionId = OpenPay.deviceData.setup("payment-form", "deviceIdHiddenFieldName");
        console.log("Device session ID created:", deviceSessionId);
    } catch (error) {
        void trackPaymentEvent({
            eventName: 'ui_payment_device_setup_failed',
            severity: 'error',
            errorMessage: error.message || 'OpenPay device setup failed.'
        });
        console.error("Error setting up device session:", error);
    }
});

document.getElementById('payment-form').addEventListener('submit', async function (e) {
    e.preventDefault();

    const clientFlowId = window.OrderProcessingUiTelemetry?.createFlowId?.() || null;

    let runtimeConfiguration;
    try {
        runtimeConfiguration = await runtimeConfigurationPromise;
    } catch (error) {
        void trackPaymentEvent({
            eventName: 'ui_payment_submit_blocked',
            severity: 'warning',
            clientFlowId,
            errorMessage: error.message || 'Tenant configuration unavailable.'
        });
        alert(error.message || 'API tenant configuration is missing.');
        return;
    }

    const tenantCode = window.OrderProcessingTenant?.getSelectedTenantCode() || runtimeConfiguration.activeTenantCode;
    const tenantHeaderName = window.OrderProcessingTenant?.getTenantHeaderName() || runtimeConfiguration.tenantHeaderName || 'X-Tenant-Code';

    // Show loading state
    const submitButton = this.querySelector('button[type="submit"]');
    const originalButtonText = submitButton.innerHTML;
    submitButton.disabled = true;
    submitButton.innerHTML = 'Processing...';

    const cardData = {
        holder_name: document.getElementById('holderName').value,
        card_number: document.getElementById('cardNumber').value.replace(/\s/g, ''),
        expiration_month: document.getElementById('expiryMonth').value,
        expiration_year: document.getElementById('expiryYear').value,
        cvv2: document.getElementById('cvv').value,
        email: document.getElementById('email').value,
        customerOrderId: document.getElementById('customerOrderId').value,
        device_session_id: deviceSessionId
    };

    void trackPaymentEvent({
        eventName: 'ui_payment_submit_started',
        severity: 'information',
        tenantCode,
        clientFlowId,
        customerOrderId: cardData.customerOrderId
    });

    //console.log("Creating token with data:", {
    //    ...cardData,
    //    card_number: '****' + cardData.card_number.slice(-4),
    //    cvv2: '***'
    //});

    // Create OpenPay token
    OpenPay.token.create(
        cardData,
        function (response) {
            console.log("Token created successfully:", response.data.id);

            void trackPaymentEvent({
                eventName: 'ui_payment_token_created',
                severity: 'information',
                tenantCode,
                clientFlowId,
                customerOrderId: cardData.customerOrderId
            });

            const paymentData = {
                "token": response.data.id,
                "name": cardData.holder_name,
                "email": cardData.email,
                "cardNumber": cardData.card_number,
                "expirationYear": cardData.expiration_year,
                "expirationMonth": cardData.expiration_month,
                "cvv2": cardData.cvv2,
                "customerOrderId": cardData.customerOrderId,
                "deviceSessionId": cardData.device_session_id
            };

            void trackPaymentEvent({
                eventName: 'ui_payment_processing_requested',
                severity: 'information',
                tenantCode,
                clientFlowId,
                customerOrderId: cardData.customerOrderId
            });

            // Call your API endpoint
            fetch(API_BASE_URL + '/api/v1/payments/processpayment', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [tenantHeaderName]: tenantCode
                },
                body: JSON.stringify(paymentData)
            })
                .then(async response => {
                    const contentType = response.headers.get('content-type') || '';
                    const data = contentType.includes('application/json')
                        ? await response.json()
                        : null;

                    if (!response.ok) {
                        const message = data?.message || `Payment request failed with status ${response.status}`;
                        const requestError = new Error(message);
                        requestError.httpStatus = response.status;
                        throw requestError;
                    }

                    return data;
                })
                .then(apiResponse => {
                    if (!apiResponse?.success || !apiResponse?.data) {
                        throw new Error(apiResponse?.message || 'Payment response did not include a valid result.');
                    }

                    const payment = apiResponse.data;
                    payment.clientFlowId = clientFlowId;
                    const paymentStatus = (payment.status || '').toLowerCase();

                    if (paymentStatus === 'charge_pending' && payment.threeDSecureUrl) {
                        persistPendingPaymentContext(payment);
                        void trackPaymentEvent({
                            eventName: 'ui_payment_3ds_redirect_started',
                            severity: 'information',
                            tenantCode,
                            clientFlowId,
                            customerOrderId: payment.customerOrderId || cardData.customerOrderId,
                            attemptOrderId: payment.attemptOrderId,
                            paymentId: payment.id,
                            paymentStatus: payment.status,
                            statusCategory: payment.statusCategory
                        }, { useBeacon: true });
                        window.location.assign(payment.threeDSecureUrl);
                        return;
                    }

                    if (paymentStatus && paymentStatus !== 'unknown') {
                        void trackPaymentEvent({
                            eventName: 'ui_payment_completed',
                            severity: 'information',
                            tenantCode,
                            clientFlowId,
                            customerOrderId: payment.customerOrderId || cardData.customerOrderId,
                            attemptOrderId: payment.attemptOrderId,
                            paymentId: payment.id,
                            paymentStatus: payment.status,
                            statusCategory: payment.statusCategory
                        });
                        alert('Payment processed successfully!');
                        document.getElementById('payment-form').reset();
                        return;
                    }

                    throw new Error(payment.errorMessage || apiResponse.message || 'Payment failed.');
                })
                .catch(error => {
                    void trackPaymentEvent({
                        eventName: 'ui_payment_processing_failed',
                        severity: 'warning',
                        tenantCode,
                        clientFlowId,
                        customerOrderId: cardData.customerOrderId,
                        httpStatus: Number.isInteger(error.httpStatus) ? error.httpStatus : null,
                        errorMessage: error.message || 'Payment processing failed.'
                    });
                    console.error('Error processing payment:', error);
                    alert(error.message || 'An error occurred while processing the payment.');
                })
                .finally(() => {
                    // Reset button state
                    submitButton.disabled = false;
                    submitButton.innerHTML = originalButtonText;
                });
        },
        function (error) {
            const providerErrorCode = error?.data?.error_code || error?.data?.errorCode || null;
            const providerErrorDescription = error?.data?.description || null;

            void trackPaymentEvent({
                eventName: 'ui_payment_token_failed',
                severity: 'warning',
                tenantCode,
                clientFlowId,
                customerOrderId: cardData.customerOrderId,
                errorCode: providerErrorCode,
                errorMessage: providerErrorDescription || error?.message || 'OpenPay token creation failed.'
            });
            console.error('Error creating token:', error);
            let errorMessage = 'Error creating payment token. Please check your card details.';

            if (error && error.data) {
                errorMessage = error.data.description || errorMessage;
            }

            alert(errorMessage);

            // Reset button state
            submitButton.disabled = false;
            submitButton.innerHTML = originalButtonText;
        }
    );
});

// Input validation and formatting
document.getElementById('cardNumber').addEventListener('input', function (e) {
    let value = this.value.replace(/\D/g, '');
    // Format card number in groups of 4
    this.value = value.replace(/(\d{4})(?=\d)/g, '$1 ').trim();
});

document.getElementById('expiryMonth').addEventListener('input', function (e) {
    this.value = this.value.replace(/\D/g, '');
    let month = parseInt(this.value);
    if (month > 12) this.value = '12';
    if (month < 1 && this.value.length) this.value = '01';
    if (this.value.length === 1 && month !== 0) this.value = month;
});

document.getElementById('expiryYear').addEventListener('input', function (e) {
    this.value = this.value.replace(/\D/g, '');
    const currentYear = new Date().getFullYear().toString().slice(-2);
    const year = parseInt(this.value);
    if (year < parseInt(currentYear) && this.value.length === 2) {
        this.value = currentYear;
    }
});

document.getElementById('cvv').addEventListener('input', function (e) {
    this.value = this.value.replace(/\D/g, '');
});

console.log('API_BASE_URL (from payment.js):', typeof API_BASE_URL !== 'undefined' ? API_BASE_URL : 'NOT DEFINED');
