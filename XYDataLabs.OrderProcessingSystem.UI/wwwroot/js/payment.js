// Initialize device session ID when the page loads
let deviceSessionId;
window.addEventListener('load', function () {
    try {
        // Initialize OpenPay with sandbox credentials
        OpenPay.setId('mt2ummntdjhxgoeycbgj');
        OpenPay.setApiKey('pk_4881b1c79b064f7397685d7d491c7338');
        OpenPay.setSandboxMode(true);
        deviceSessionId = OpenPay.deviceData.setup("payment-form", "deviceIdHiddenFieldName");
        console.log("Device session ID created:", deviceSessionId);
    } catch (error) {
        console.error("Error setting up device session:", error);
    }
});

document.getElementById('payment-form').addEventListener('submit', function (e) {
    e.preventDefault();

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
        orderId: document.getElementById('orderId').value,
        device_session_id: deviceSessionId
    };

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

            const paymentData = {
                "token": response.data.id,
                "name": cardData.holder_name,
                "email": cardData.email,
                "cardNumber": cardData.card_number,
                "expirationYear": cardData.expiration_year,
                "expirationMonth": cardData.expiration_month,
                "cvv2": cardData.cvv2,
                "orderId": cardData.orderId,
                "deviceSessionId": cardData.device_session_id
            };

            // Call your API endpoint
            fetch('https://localhost:44393/api/payments/processpayment', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(paymentData)
            })
                .then(response => response.json())
                .then(data => {
                    if (data && data.status && data.status.length > 0 && data.status !== 'unknown') {
                        alert('Payment processed successfully!');
                        // Reset form
                        document.getElementById('payment-form').reset();
                    } else {
                        alert('Payment failed: ' + data.message);
                    }
                })
                .catch(error => {
                    console.error('Error processing payment:', error);
                    alert('An error occurred while processing the payment.');
                })
                .finally(() => {
                    // Reset button state
                    submitButton.disabled = false;
                    submitButton.innerHTML = originalButtonText;
                });
        },
        function (error) {
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