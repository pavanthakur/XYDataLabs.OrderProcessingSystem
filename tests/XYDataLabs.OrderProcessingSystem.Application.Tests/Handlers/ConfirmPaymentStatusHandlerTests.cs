using FluentAssertions;
using Moq;
using Openpay.Entities;
using XYDataLabs.OrderProcessingSystem.Application.Tests.TestBase;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;

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
        var openPayLocalTime = new DateTime(2024, 3, 1, 4, 0, 0); // no Kind = Unspecified
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
