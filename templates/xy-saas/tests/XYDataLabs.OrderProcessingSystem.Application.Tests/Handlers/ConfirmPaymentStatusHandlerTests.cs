using FluentAssertions;
using Moq;
using XYDataLabs.OrderProcessingSystem.Application.Tests.TestBase;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.PaymentGateway;

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
        MockPaymentGateway
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new PaymentGatewayCharge { Id = "charge-001", Status = "completed" });

        var handler = CreateConfirmPaymentHandler();

        // Act
        var result = await handler.HandleAsync(BuildConfirmPaymentCommand(paymentId: "charge-001"));

        // Assert
        result.IsFailure.Should().BeTrue();
        result.Error.Code.Should().Be("NotFound");
    }

    // ------------------------------------------------------------------ TSH state-machine tests

    [Fact]
    public async Task HandleAsync_WithCallbackPayload_ShouldWriteTwoTransactionStatusHistoryRows()
    {
        // Arrange — pass a callback status to trigger the browser-callback TSH row
        var transaction = BuildStubCardTransaction(billingCustomerId: 42);
        SetupConfirmPaymentDbSets(existingTransaction: transaction);
        MockPaymentGateway
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new PaymentGatewayCharge { Id = "charge-001", Status = "completed", Amount = 100m });

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
        // Arrange — no callback payload; only remote status fetch from the payment provider
        var transaction = BuildStubCardTransaction(billingCustomerId: 42);
        SetupConfirmPaymentDbSets(existingTransaction: transaction);
        MockPaymentGateway
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new PaymentGatewayCharge { Id = "charge-001", Status = "completed", Amount = 100m });

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
        MockPaymentGateway
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new PaymentGatewayCharge
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
        payinLog.ProviderAuthorizationId = "auth-ref-001";

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

        MockPaymentGateway
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new PaymentGatewayCharge
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
            PaymentProviderName = "DefaultGateway",
            ProviderChargeId = transaction.TransactionId,
            Status = PaymentAttemptStatus.ProviderAccepted,
        };

        SetupConfirmPaymentDbSets(existingTransaction: transaction, existingPaymentAttempt: paymentAttempt);
        MockPaymentGateway
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new PaymentGatewayCharge
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
            PaymentProviderName = "DefaultGateway",
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
        MockPaymentGateway
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new PaymentGatewayCharge
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
        MockPaymentGateway
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new PaymentGatewayCharge { Id = "charge-001", Status = "completed", Amount = 100m });

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
        // Arrange — the provider returns a DateTimeKind.Unspecified date.
        var providerLocalTime = new DateTime(2024, 3, 1, 4, 0, 0, DateTimeKind.Unspecified);
        var transaction = BuildStubCardTransaction();
        SetupConfirmPaymentDbSets(existingTransaction: transaction);
        MockPaymentGateway
            .Setup(s => s.GetChargeAsync(It.IsAny<string>(), It.IsAny<string?>()))
            .ReturnsAsync(new PaymentGatewayCharge
            {
                Id = "charge-001",
                Status = "completed",
                Amount = 100m,
                CreationDate = providerLocalTime
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
