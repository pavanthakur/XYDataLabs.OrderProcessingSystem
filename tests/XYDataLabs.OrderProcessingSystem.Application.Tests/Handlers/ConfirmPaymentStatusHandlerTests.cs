using FluentAssertions;
using Moq;
using Openpay.Entities;
using XYDataLabs.OrderProcessingSystem.Application.Tests.TestBase;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.Handlers;

/// <summary>
/// Unit tests for ConfirmPaymentStatusCommandHandler covering the state-machine sequence,
/// callback-vs-remote sources, and the regressions fixed in commit ff59d64.
/// </summary>
public class ConfirmPaymentStatusHandlerTests : PaymentServiceTestBase
{
    // ------------------------------------------------------------------ validation guard

    [Fact]
    public async Task HandleAsync_EmptyPaymentId_ShouldReturnValidationError()
    {
        // Arrange
        SetupConfirmPaymentDbSets();
        var handler = CreateConfirmPaymentHandler();
        var command = BuildConfirmPaymentCommand(paymentId: "");

        // Act
        var result = await handler.HandleAsync(command);

        // Assert
        result.IsFailure.Should().BeTrue();
        result.Error.Code.Should().Be("Validation");
    }

    // ------------------------------------------------------------------ not found guard

    [Fact]
    public async Task HandleAsync_UnknownPaymentId_ShouldReturnNotFound()
    {
        // Arrange — no matching CardTransaction in the DB
        SetupConfirmPaymentDbSets(existingTransaction: null);
        MockOpenPayAdapter
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new Charge { Id = "charge-001", Status = "completed" });

        var handler = CreateConfirmPaymentHandler();

        // Act
        var result = await handler.HandleAsync(BuildConfirmPaymentCommand(paymentId: "charge-001"));

        // Assert
        result.IsFailure.Should().BeTrue();
        result.Error.Code.Should().Be("NotFound");
    }

    [Fact]
    public async Task HandleAsync_RazorpayProviderOrderIdCallback_ShouldResolveTransactionViaStoredProviderOrderId()
    {
        var transaction = BuildStubCardTransaction(billingCustomerId: 42, isThreeDSecureEnabled: false);
        transaction.TransactionId = "razorpay-token-pending";
        transaction.TransactionCustomerId = "razorpay-cust-john";
        transaction.AttemptOrderId = "attempt-rzp-001";
        transaction.TransactionStatus = "completed";
        transaction.ThreeDSecureStage = "not_applicable";

        var payinLog = BuildStubPayinLog(billingCustomerId: 42, isThreeDSecureEnabled: false);
        payinLog.AttemptOrderId = transaction.AttemptOrderId;
        payinLog.OpenPayChargeId = "order_rzp_123";

        var paymentAttempt = new PaymentAttempt
        {
            Id = 9,
            TenantId = 1,
            CustomerOrderId = transaction.CustomerOrderId,
            AttemptOrderId = transaction.AttemptOrderId!,
            AttemptNumber = 1,
            PaymentTraceId = transaction.PaymentTraceId!,
            PaymentProviderName = PaymentProviderTypes.Razorpay,
            ProviderChargeId = payinLog.OpenPayChargeId,
            Status = PaymentAttemptStatus.ProviderAccepted,
        };

        SetupConfirmPaymentDbSets(
            existingTransaction: transaction,
            existingPayinLog: payinLog,
            existingPaymentAttempt: paymentAttempt);

        MockPaymentGateway
            .Setup(g => g.GetChargeAsync("pay_rzp_123", transaction.TransactionCustomerId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PaymentGatewayChargeResult(
                Id: "pay_rzp_123",
                Status: "completed",
                Amount: 100m,
                CreatedAt: UtcNow,
                Authorization: null,
                ErrorMessage: null,
                RedirectUrl: null));

        var handler = CreateConfirmPaymentHandler(providerType: PaymentProviderTypes.Razorpay);

        var result = await handler.HandleAsync(BuildConfirmPaymentCommand(
            paymentId: "pay_rzp_123",
            attemptOrderId: "order_rzp_123",
            callbackParameters: new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["tenantCode"] = "TenantA",
                ["razorpay_order_id"] = "order_rzp_123",
                ["razorpay_payment_id"] = "pay_rzp_123",
                ["razorpay_signature"] = BuildRazorpaySignature("order_rzp_123", "pay_rzp_123")
            }));

        result.IsSuccess.Should().BeTrue();
        result.Value!.CustomerOrderId.Should().Be(transaction.CustomerOrderId);
        result.Value.Status.Should().Be("completed");
        result.Value.StatusSource.Should().Be(PaymentProviderTypes.Razorpay);
        result.Value.StatusMessage.Should().Contain("Razorpay");
        result.Value.StatusMessage.Should().NotContain("OpenPay");
        paymentAttempt.Status.Should().Be(PaymentAttemptStatus.Succeeded);
        paymentAttempt.ProviderChargeId.Should().Be("pay_rzp_123");
    }

    [Fact]
    public async Task HandleAsync_RazorpaySuccessfulCallback_WithInvalidSignature_ShouldReturnValidationError()
    {
        var transaction = BuildStubCardTransaction(billingCustomerId: 42, isThreeDSecureEnabled: false);
        transaction.TransactionId = "order_rzp_bad_sig";
        transaction.TransactionCustomerId = "razorpay-cust-john";
        transaction.AttemptOrderId = "attempt-rzp-bad-sig";
        transaction.TransactionStatus = "charge_pending";
        transaction.ThreeDSecureStage = "not_applicable";

        var payinLog = BuildStubPayinLog(billingCustomerId: 42, isThreeDSecureEnabled: false);
        payinLog.AttemptOrderId = transaction.AttemptOrderId;
        payinLog.OpenPayChargeId = "order_rzp_bad_sig";

        SetupConfirmPaymentDbSets(existingTransaction: transaction, existingPayinLog: payinLog);

        MockPaymentGateway
            .Setup(g => g.GetChargeAsync("pay_rzp_bad_sig", transaction.TransactionCustomerId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PaymentGatewayChargeResult(
                Id: "pay_rzp_bad_sig",
                Status: "completed",
                Amount: 100m,
                CreatedAt: UtcNow,
                Authorization: null,
                ErrorMessage: null,
                RedirectUrl: null));

        var handler = CreateConfirmPaymentHandler(providerType: PaymentProviderTypes.Razorpay);

        var result = await handler.HandleAsync(BuildConfirmPaymentCommand(
            paymentId: "pay_rzp_bad_sig",
            attemptOrderId: "order_rzp_bad_sig",
            callbackParameters: new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["tenantCode"] = "TenantA",
                ["razorpay_order_id"] = "order_rzp_bad_sig",
                ["razorpay_payment_id"] = "pay_rzp_bad_sig",
                ["razorpay_signature"] = "bad-signature"
            }));

        result.IsFailure.Should().BeTrue();
        result.Error.Code.Should().Be("Validation");
        result.Error.Description.Should().Contain("signature verification failed");
    }

    [Fact]
    public async Task HandleAsync_RazorpayProviderOrderIdCallback_WithoutPayinLog_ShouldResolveTransactionViaStoredOrderId()
    {
        var transaction = BuildStubCardTransaction(billingCustomerId: 42, isThreeDSecureEnabled: false);
        transaction.TransactionId = "order_rzp_456";
        transaction.TransactionCustomerId = "razorpay-cust-jane";
        transaction.AttemptOrderId = "attempt-rzp-456";
        transaction.TransactionStatus = "charge_pending";
        transaction.ThreeDSecureStage = "not_applicable";

        SetupConfirmPaymentDbSets(existingTransaction: transaction, existingPayinLog: null);

        MockPaymentGateway
            .Setup(g => g.GetChargeAsync("pay_rzp_456", transaction.TransactionCustomerId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PaymentGatewayChargeResult(
                Id: "pay_rzp_456",
                Status: "completed",
                Amount: 100m,
                CreatedAt: UtcNow,
                Authorization: null,
                ErrorMessage: null,
                RedirectUrl: null));

        var handler = CreateConfirmPaymentHandler(providerType: PaymentProviderTypes.Razorpay);

        var result = await handler.HandleAsync(BuildConfirmPaymentCommand(
            paymentId: "pay_rzp_456",
            attemptOrderId: "order_rzp_456"));

        result.IsSuccess.Should().BeTrue();
        result.Value!.CustomerOrderId.Should().Be(transaction.CustomerOrderId);
        result.Value.Status.Should().Be("completed");
    }

    [Fact]
    public async Task HandleAsync_RazorpayCallbackErrorWithoutStatus_ShouldTreatCallbackAsFailed()
    {
        var transaction = BuildStubCardTransaction(billingCustomerId: 42, isThreeDSecureEnabled: false);
        transaction.TransactionId = "order_rzp_declined_001";
        transaction.TransactionCustomerId = "razorpay-cust-jane";
        transaction.AttemptOrderId = "attempt-rzp-declined-001";
        transaction.TransactionStatus = "charge_pending";
        transaction.ThreeDSecureStage = "pending_confirmation";

        SetupConfirmPaymentDbSets(existingTransaction: transaction, existingPayinLog: null);

        MockPaymentGateway
            .Setup(g => g.GetChargeAsync("pay_rzp_declined_001", transaction.TransactionCustomerId, It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("Razorpay lookup unavailable for declined callback test."));

        var handler = CreateConfirmPaymentHandler(providerType: PaymentProviderTypes.Razorpay);

        var result = await handler.HandleAsync(BuildConfirmPaymentCommand(
            paymentId: "pay_rzp_declined_001",
            attemptOrderId: "order_rzp_declined_001",
            errorMessage: "International cards are not supported. Please contact our support team for help",
            callbackParameters: new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["tenantCode"] = "TenantA",
                ["razorpay_order_id"] = "order_rzp_declined_001",
                ["razorpay_payment_id"] = "pay_rzp_declined_001",
                ["error_message"] = "International cards are not supported. Please contact our support team for help"
            }));

        result.IsSuccess.Should().BeTrue();
        result.Value!.Status.Should().Be("failed");
        result.Value.IsFailure.Should().BeTrue();
        result.Value.IsPending.Should().BeFalse();
        result.Value.StatusMessage.Should().Be("Payment failed based on the latest local record.");
        result.Value.StatusMessage.Should().NotContain("OpenPay");
        result.Value.ErrorMessage.Should().Be("International cards are not supported. Please contact our support team for help");
        transaction.TransactionStatus.Should().Be("failed");
    }

    [Fact]
    public async Task HandleAsync_LongCallbackError_ShouldTruncatePersistedTransactionStatusHistoryNotes()
    {
        var transaction = BuildStubCardTransaction(billingCustomerId: 42, isThreeDSecureEnabled: false);
        transaction.TransactionId = "order_rzp_declined_002";
        transaction.TransactionCustomerId = "razorpay-cust-john";
        transaction.AttemptOrderId = "attempt-rzp-declined-002";
        transaction.TransactionStatus = "charge_pending";
        transaction.ThreeDSecureStage = "pending_confirmation";

        SetupConfirmPaymentDbSets(existingTransaction: transaction, existingPayinLog: null);

        var longErrorMessage = new string('X', 400);

        MockPaymentGateway
            .Setup(g => g.GetChargeAsync("pay_rzp_declined_002", transaction.TransactionCustomerId, It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("Razorpay lookup unavailable for truncation test."));

        var handler = CreateConfirmPaymentHandler(providerType: PaymentProviderTypes.Razorpay);

        var result = await handler.HandleAsync(BuildConfirmPaymentCommand(
            paymentId: "pay_rzp_declined_002",
            attemptOrderId: "order_rzp_declined_002",
            errorMessage: longErrorMessage,
            callbackParameters: new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["tenantCode"] = "TenantA",
                ["razorpay_order_id"] = "order_rzp_declined_002",
                ["razorpay_payment_id"] = "pay_rzp_declined_002",
                ["error_message"] = longErrorMessage
            }));

        result.IsSuccess.Should().BeTrue();
        result.Value!.Status.Should().Be("failed");
        CapturedTsh.Should().ContainSingle();
        CapturedTsh.Single().Notes.Should().NotBeNull();
        CapturedTsh.Single().Notes!.Length.Should().BeLessThanOrEqualTo(255);
    }

    // ------------------------------------------------------------------ TSH state-machine tests

    [Fact]
    public async Task HandleAsync_WithCallbackPayload_ShouldWriteTwoTransactionStatusHistoryRows()
    {
        // Arrange — pass a callback status to trigger the browser-callback TSH row
        var transaction = BuildStubCardTransaction(billingCustomerId: 42);
        SetupConfirmPaymentDbSets(existingTransaction: transaction);
        MockOpenPayAdapter
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new Charge { Id = "charge-001", Status = "completed", Amount = 100m });

        var handler = CreateConfirmPaymentHandler();
        var command = BuildConfirmPaymentCommand(callbackStatus: "completed"); // triggers callbackPayloadReceived

        // Act
        var result = await handler.HandleAsync(command);

        // Assert — 2 rows: one "callback_received" + one final resolved status (fix for DB query 3)
        result.IsSuccess.Should().BeTrue();
        CapturedTsh.Should().HaveCount(2,
            because: "a browser callback triggers one callbackReceived TSH row plus one resolved-status TSH row");
    }

    [Fact]
    public async Task HandleAsync_WithRemoteStatusOnly_ShouldWriteOneTransactionStatusHistoryRow()
    {
        // Arrange — no callback payload; only remote status fetch from OpenPay
        var transaction = BuildStubCardTransaction(billingCustomerId: 42);
        SetupConfirmPaymentDbSets(existingTransaction: transaction);
        MockOpenPayAdapter
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new Charge { Id = "charge-001", Status = "completed", Amount = 100m });

        var handler = CreateConfirmPaymentHandler();
        var command = BuildConfirmPaymentCommand(callbackStatus: null, callbackParameters: null); // no browser payload

        // Act
        var result = await handler.HandleAsync(command);

        // Assert — only the resolved-status row (no callback_received row)
        result.IsSuccess.Should().BeTrue();
        CapturedTsh.Should().HaveCount(1,
            because: "without a browser callback only the resolved-status TSH row is written");
    }

    [Fact]
    public async Task HandleAsync_RepeatedThreeDSCallback_ShouldNotWriteDuplicateAuditRows()
    {
        // Arrange — the second reconciliation should see the rows written by the first one.
        var transaction = BuildStubCardTransaction(billingCustomerId: 42);
        var payinLog = BuildStubPayinLog(billingCustomerId: 42);
        SetupConfirmPaymentDbSets(existingTransaction: transaction, existingPayinLog: payinLog);
        MockOpenPayAdapter
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new Charge
            {
                Id = "charge-001",
                Status = "completed",
                Amount = 100m,
                Authorization = "auth-ref-001"
            });

        var handler = CreateConfirmPaymentHandler();
        var command = BuildConfirmPaymentCommand(callbackStatus: "completed");

        // Act — first pass records the callback audit trail.
        var firstResult = await handler.HandleAsync(command);
        CapturedTsh.Should().HaveCount(2);
        CapturedPayinLogDetails.Should().HaveCount(1);

        CapturedTsh.Clear();
        CapturedPayinLogDetails.Clear();

        var secondResult = await handler.HandleAsync(command);

        // Assert — a repeated confirm-status call is idempotent.
        firstResult.IsSuccess.Should().BeTrue();
        secondResult.IsSuccess.Should().BeTrue();
        secondResult.Value!.CallbackRecorded.Should().BeTrue();
        CapturedTsh.Should().BeEmpty(
            because: "callback_received and completed were already written during the first reconciliation");
        CapturedPayinLogDetails.Should().BeEmpty(
            because: "the final reconciliation detail row must not be duplicated on refresh or retry");
    }

    [Fact]
    public async Task HandleAsync_DirectNon3DSStatusLookup_ShouldNotWriteCallbackAuditRows()
    {
        // Arrange — non-3DS charges are already final after ProcessPayment and direct status lookups must stay read-only.
        var transaction = BuildStubCardTransaction(billingCustomerId: 42, isThreeDSecureEnabled: false);
        transaction.TransactionStatus = "completed";
        transaction.ThreeDSecureStage = "not_applicable";
        transaction.TransactionReferenceId = "auth-ref-001";

        var payinLog = BuildStubPayinLog(billingCustomerId: 42, isThreeDSecureEnabled: false);
        payinLog.Result = 1;
        payinLog.OpenPayAuthorizationId = "auth-ref-001";

        var existingHistories = new[]
        {
            new TransactionStatusHistory
            {
                Id = 1,
                TransactionId = transaction.Id,
                AttemptOrderId = transaction.AttemptOrderId,
                Status = "completed",
                ThreeDSecureStage = "tokenization_completed",
                IsThreeDSecureEnabled = false,
                CreatedBy = transaction.BillingCustomerId,
                CreatedDate = UtcNow
            },
            new TransactionStatusHistory
            {
                Id = 2,
                TransactionId = transaction.Id,
                AttemptOrderId = transaction.AttemptOrderId,
                Status = "completed",
                ThreeDSecureStage = "not_applicable",
                IsThreeDSecureEnabled = false,
                TransactionReferenceId = "auth-ref-001",
                CreatedBy = transaction.BillingCustomerId,
                CreatedDate = UtcNow
            }
        };

        SetupConfirmPaymentDbSets(
            existingTransaction: transaction,
            existingPayinLog: payinLog,
            existingTransactionStatusHistories: existingHistories);

        MockOpenPayAdapter
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new Charge
            {
                Id = "charge-001",
                Status = "completed",
                Amount = 100m,
                Authorization = "auth-ref-001"
            });

        var handler = CreateConfirmPaymentHandler();
        var callbackParameters = new Dictionary<string, string>(capacity: 2, comparer: StringComparer.Ordinal)
        {
            ["source"] = "direct",
            ["status"] = "completed"
        };

        var command = BuildConfirmPaymentCommand(
            callbackStatus: "completed",
            callbackParameters: callbackParameters);

        // Act
        var result = await handler.HandleAsync(command);

        // Assert
        result.IsSuccess.Should().BeTrue();
        result.Value!.CallbackRecorded.Should().BeFalse();
        result.Value.ThreeDSecureStage.Should().Be("not_applicable");
        CapturedTsh.Should().BeEmpty(
            because: "direct summary-page lookups for non-3DS payments must not append callback or final-status history rows");
        CapturedPayinLogDetails.Should().BeEmpty(
            because: "the not_applicable PayinLogDetails row already exists from the original charge creation");
    }

    [Fact]
    public async Task HandleAsync_ShouldUpdatePaymentAttemptToSucceededAndAppendHistory()
    {
        var transaction = BuildStubCardTransaction(billingCustomerId: 42);
        var paymentAttempt = new PaymentAttempt
        {
            Id = 9,
            TenantId = 1,
            CustomerOrderId = transaction.CustomerOrderId,
            AttemptOrderId = transaction.AttemptOrderId!,
            AttemptNumber = 1,
            PaymentTraceId = transaction.PaymentTraceId!,
            PaymentProviderName = "OpenPay",
            ProviderChargeId = transaction.TransactionId,
            Status = PaymentAttemptStatus.ProviderAccepted,
        };

        SetupConfirmPaymentDbSets(existingTransaction: transaction, existingPaymentAttempt: paymentAttempt);
        MockOpenPayAdapter
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new Charge
            {
                Id = "charge-001",
                Status = "completed",
                Amount = 100m,
                Authorization = "auth-ref-001"
            });

        var handler = CreateConfirmPaymentHandler();

        var result = await handler.HandleAsync(BuildConfirmPaymentCommand(callbackStatus: "completed"));

        result.IsSuccess.Should().BeTrue();
        paymentAttempt.Status.Should().Be(PaymentAttemptStatus.Succeeded);
        paymentAttempt.ProviderStatus.Should().Be("completed");
        paymentAttempt.ProviderReferenceId.Should().Be("auth-ref-001");
        CapturedPaymentAttemptHistories.Should().ContainSingle();
        CapturedPaymentAttemptHistories.Single().Status.Should().Be(PaymentAttemptStatus.Succeeded);
    }

    [Fact]
    public async Task HandleAsync_RepeatedCallback_ShouldNotDuplicatePaymentAttemptHistory()
    {
        var transaction = BuildStubCardTransaction(billingCustomerId: 42);
        var paymentAttempt = new PaymentAttempt
        {
            Id = 9,
            TenantId = 1,
            CustomerOrderId = transaction.CustomerOrderId,
            AttemptOrderId = transaction.AttemptOrderId!,
            AttemptNumber = 1,
            PaymentTraceId = transaction.PaymentTraceId!,
            PaymentProviderName = "OpenPay",
            ProviderChargeId = transaction.TransactionId,
            Status = PaymentAttemptStatus.ProviderAccepted,
        };
        var existingAttemptHistories = new[]
        {
            new PaymentAttemptHistory
            {
                Id = 1,
                PaymentAttemptId = paymentAttempt.Id,
                AttemptOrderId = paymentAttempt.AttemptOrderId,
                Status = PaymentAttemptStatus.Succeeded,
                PaymentTraceId = paymentAttempt.PaymentTraceId,
                ProviderStatus = "completed",
                TenantId = 1,
                CreatedDate = UtcNow,
            }
        };

        SetupConfirmPaymentDbSets(
            existingTransaction: transaction,
            existingPaymentAttempt: paymentAttempt,
            existingPaymentAttemptHistories: existingAttemptHistories);
        MockOpenPayAdapter
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new Charge
            {
                Id = "charge-001",
                Status = "completed",
                Amount = 100m,
                Authorization = "auth-ref-001"
            });

        var handler = CreateConfirmPaymentHandler();

        var result = await handler.HandleAsync(BuildConfirmPaymentCommand(callbackStatus: "completed"));

        result.IsSuccess.Should().BeTrue();
        CapturedPaymentAttemptHistories.Should().BeEmpty();
    }

    // ------------------------------------------------------------------ Fix 1 regression guard

    [Fact]
    public async Task HandleAsync_TransactionStatusHistory_ShouldUsesBillingCustomerIdForCreatedBy()
    {
        // Arrange — card transaction has BillingCustomerId = 42
        const int expectedBillingCustomerId = 42;
        var transaction = BuildStubCardTransaction(billingCustomerId: expectedBillingCustomerId);
        SetupConfirmPaymentDbSets(existingTransaction: transaction);
        MockOpenPayAdapter
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new Charge { Id = "charge-001", Status = "completed", Amount = 100m });

        var handler = CreateConfirmPaymentHandler();

        // Act
        await handler.HandleAsync(BuildConfirmPaymentCommand(callbackStatus: "completed"));

        // Assert — CreatedBy on all TSH rows must equal BillingCustomerId (fix 1 renamed from CustomerId)
        CapturedTsh.Should().NotBeEmpty();
        CapturedTsh.Should().AllSatisfy(tsh =>
            tsh.CreatedBy.Should().Be(expectedBillingCustomerId,
                because: "TSH.CreatedBy maps to transaction.BillingCustomerId, not the old transaction.CustomerId"));
    }

    // ------------------------------------------------------------------ Fix 4 regression guard

    [Fact]
    public async Task HandleAsync_RemoteChargeCreationDate_ShouldBeNormalisedToUtcInReturnDto()
    {
        // Arrange — OpenPay returns a DateTimeKind.Unspecified date (CDMx local time)
        var openPayLocalTime = new DateTime(2024, 3, 1, 4, 0, 0, DateTimeKind.Unspecified);
        var transaction = BuildStubCardTransaction();
        SetupConfirmPaymentDbSets(existingTransaction: transaction);
        MockOpenPayAdapter
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new Charge
            {
                Id = "charge-001",
                Status = "completed",
                Amount = 100m,
                CreationDate = openPayLocalTime
            });

        var handler = CreateConfirmPaymentHandler();

        // Act
        var result = await handler.HandleAsync(BuildConfirmPaymentCommand());

        // Assert — NormalizeToUtc must convert and tag the date as Utc before returning
        result.IsSuccess.Should().BeTrue();
        result.Value!.TransactionDate.Should().NotBeNull();
        result.Value.TransactionDate!.Value.Kind.Should().Be(DateTimeKind.Utc,
            because: "NormalizeToUtc() must tag the returned TransactionDate as UTC (fix 4)");
    }
}
