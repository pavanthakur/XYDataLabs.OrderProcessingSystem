using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Moq;
using XYDataLabs.OrderProcessingSystem.Application.Tests.TestBase;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.PaymentGateway;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.Handlers;

/// <summary>
/// Unit tests for ProcessPaymentCommandHandler targeting the 5 issues found in post-payment
/// DB analysis (commits ff59d64). Each test is a regression guard for one of those fixes.
/// </summary>
public class ProcessPaymentHandlerTests : PaymentServiceTestBase
{
    // ------------------------------------------------------------------ Fix 1 regression guard

    [Fact]
    public async Task HandleAsync_NewCustomer_BothCardTransactionsShouldSetBillingCustomerId()
    {
        // Arrange
        SetupPaymentDbSets();
        SetupPaymentGatewayHappyPath();
        var handler = CreateProcessPaymentHandler();

        // Act
        await handler.HandleAsync(BuildProcessPaymentCommand());

        // Assert — both the tokenization CT and the charge CT must carry BillingCustomerId (not 0)
        // With the mock, BillingCustomer.Id = 0 (no real DB auto-increment), so we verify
        // the property EXISTS and is consistently identical across both records.
        CapturedCardTransactions.Should().HaveCount(2, "ProcessPayment creates one tokenization CT and one charge CT");

        var tokenizationCt = CapturedCardTransactions.First();
        var chargeCt = CapturedCardTransactions.Last();

        // Both CTs must link to the same billing customer (regression for Fix 1 rename)
        tokenizationCt.BillingCustomerId.Should().Be(chargeCt.BillingCustomerId,
            because: "both CardTransactions for the same payment must reference the same BillingCustomer");

        // BillingCustomerId must NOT be confused with CustomerId — property must exist on the entity
        typeof(Domain.Entities.CardTransaction)
            .GetProperty("BillingCustomerId").Should().NotBeNull(
                because: "the FK was renamed from CustomerId to BillingCustomerId in fix 1");
        typeof(Domain.Entities.CardTransaction)
            .GetProperty("CustomerId").Should().BeNull(
                because: "old CustomerId property must not exist after the rename in fix 1");
    }

    // ------------------------------------------------------------------ Fix 4 regression guard

    [Fact]
    public async Task HandleAsync_CreationDatesFromProvider_ShouldBeStoredAsUtcOnBothCardTransactions()
    {
        // Arrange — simulate the provider returning DateTimeKind.Unspecified timestamps.
        var providerLocalTime = new DateTime(2024, 3, 1, 4, 0, 0, DateTimeKind.Unspecified);
        SetupPaymentDbSets();
        SetupPaymentGatewayHappyPath(cardDate: providerLocalTime, chargeDate: providerLocalTime);
        var handler = CreateProcessPaymentHandler();

        // Act
        await handler.HandleAsync(BuildProcessPaymentCommand());

        // Assert — NormalizeToUtc must convert to UTC before persisting
        CapturedCardTransactions.Should().HaveCount(2);
        foreach (var ct in CapturedCardTransactions)
        {
            ct.TransactionDate.Should().NotBeNull();
            ct.TransactionDate!.Value.Kind.Should().Be(DateTimeKind.Utc,
                because: "NormalizeToUtc() must tag all stored TransactionDate values as UTC (fix 4)");
        }
    }

    // ------------------------------------------------------------------ Existing customer path

    [Fact]
    public async Task HandleAsync_ExistingBillingCustomer_ShouldNotCallProviderCreateCustomer()
    {
        // Arrange — seed a billing customer matching the command's name/email
        var existingCustomer = new BillingCustomer
        {
            Id = 5,
            Name = "John Doe",
            Email = "john@example.com",
            APICustomerId = "provider-cust-existing"
        };
        SetupPaymentDbSets(existingBillingCustomers: [existingCustomer]);
        SetupPaymentGatewayHappyPath();
        var handler = CreateProcessPaymentHandler();

        // Act
        await handler.HandleAsync(BuildProcessPaymentCommand());

        // Assert — CreateCustomerAsync must NOT be called when the customer is already in DB
        MockPaymentGateway.Verify(
            s => s.CreateCustomerAsync(It.IsAny<PaymentGatewayCustomer>()),
            Times.Never,
            "CreateCustomerAsync in the payment provider must be skipped for repeat customers");

        // CreateCardTokenAsync and CreateChargeAsync should still run
        MockPaymentGateway.Verify(s => s.CreateCardTokenAsync(It.IsAny<PaymentGatewayCardTokenRequest>()), Times.Once);
        MockPaymentGateway.Verify(s => s.CreateChargeAsync(It.IsAny<PaymentGatewayChargeRequest>()), Times.Once);
    }

    [Fact]
    public async Task HandleAsync_ShouldCreatePaymentAttemptAndAppendLifecycleHistory()
    {
        SetupPaymentDbSets();
        SetupPaymentGatewayHappyPath();
        var handler = CreateProcessPaymentHandler();

        await handler.HandleAsync(BuildProcessPaymentCommand());

        CapturedPaymentAttempts.Should().ContainSingle();
        var paymentAttempt = CapturedPaymentAttempts.Single();
        paymentAttempt.CustomerOrderId.Should().Be("ORDER-001");
        paymentAttempt.AttemptOrderId.Should().Be("ORDER-001-1");
        paymentAttempt.AttemptNumber.Should().Be(1);
        paymentAttempt.PaymentTraceId.Should().NotBeNullOrWhiteSpace();
        paymentAttempt.ProviderChargeId.Should().Be("charge-001");
        paymentAttempt.ProviderReferenceId.Should().Be("auth-ref-001");
        paymentAttempt.Status.Should().Be(PaymentAttemptStatus.Succeeded);

        CapturedPaymentAttemptHistories.Should().HaveCount(2);
        CapturedPaymentAttemptHistories.Select(history => history.Status)
            .Should().ContainInOrder(PaymentAttemptStatus.PendingProviderCall, PaymentAttemptStatus.Succeeded);
    }

    [Fact]
    public async Task HandleAsync_ShouldGenerateNextDeterministicAttemptOrderIdForExistingCustomerOrder()
    {
        SetupPaymentDbSets(existingPaymentAttempts:
        [
            new PaymentAttempt
            {
                Id = 7,
                TenantId = 1,
                CustomerOrderId = "ORDER-001",
                AttemptOrderId = "ORDER-001-1",
                AttemptNumber = 1,
                PaymentTraceId = "trace-existing",
                PaymentProviderName = "DefaultGateway",
                Status = PaymentAttemptStatus.Succeeded,
            }
        ]);
        SetupPaymentGatewayHappyPath();
        var handler = CreateProcessPaymentHandler();

        await handler.HandleAsync(BuildProcessPaymentCommand());

        CapturedPaymentAttempts.Should().ContainSingle();
        var paymentAttempt = CapturedPaymentAttempts.Single();
        paymentAttempt.AttemptNumber.Should().Be(2);
        paymentAttempt.AttemptOrderId.Should().Be("ORDER-001-2");
        CapturedCardTransactions.Select(transaction => transaction.AttemptOrderId)
            .Should().OnlyContain(attemptOrderId => attemptOrderId == "ORDER-001-2");
    }

    // ------------------------------------------------------------------ Fix 3 regression guard

    [Fact]
    public async Task HandleAsync_3DSecureOff_ShouldSetNotApplicableStageOnChargeCardTransaction()
    {
        // Arrange — tenant with Use3DSecure = false on its PaymentProvider
        SetupPaymentDbSets();
        SetupPaymentGatewayHappyPath();
        var handler = CreateProcessPaymentHandler(use3DSecure: false);

        // Act
        await handler.HandleAsync(BuildProcessPaymentCommand());

        // Assert — charge CT (second) must reflect 3DS OFF
        CapturedCardTransactions.Should().HaveCount(2);
        var chargeCt = CapturedCardTransactions.Last();
        chargeCt.IsThreeDSecureEnabled.Should().BeFalse(
            because: "the tenant's PaymentProvider has Use3DSecure = false");
        chargeCt.ThreeDSecureStage.Should().Be("not_applicable",
            because: "when 3DS is disabled for the tenant, the stage must be not_applicable");
    }

    // ------------------------------------------------------------------ Fix 3 regression guard (orphan deactivation)

    // ------------------------------------------------------------------ Fix 6 regression guard

    [Fact]
    public async Task HandleAsync_3DSecureOff_ShouldPopulateTransactionReferenceIdOnChargeCardTransaction()
    {
        // Arrange — 3DS disabled; charge returns immediately as completed with Authorization populated
        SetupPaymentDbSets();
        SetupPaymentGatewayHappyPath();
        var handler = CreateProcessPaymentHandler(use3DSecure: false);

        // Act
        await handler.HandleAsync(BuildProcessPaymentCommand());

        // Assert — charge CT must carry TransactionReferenceId from charge.Authorization at creation time.
        // For 3DS=0 there is no subsequent ConfirmPaymentStatus call, so the CT row is the only
        // opportunity to persist the reference ID returned by the payment provider.
        CapturedCardTransactions.Should().HaveCount(2);
        var chargeCt = CapturedCardTransactions.Last();
        chargeCt.TransactionReferenceId.Should().Be("auth-ref-001",
            because: "for non-3DS payments the Authorization from the charge response must be " +
                     "written to CardTransactions.TransactionReferenceId at charge creation time");
    }

    [Fact]
    public async Task HandleAsync_WhenProviderChargeFails_ShouldDeactivateOrphanedPaymentMethod()
    {
        // Arrange — fail at charge creation (after PaymentMethod has been persisted)
        SetupPaymentDbSets();

        // Customer creation succeeds so paymentMethod variable is set before the exception
        MockPaymentGateway
            .Setup(s => s.CreateCustomerAsync(It.IsAny<PaymentGatewayCustomer>()))
            .ThrowsAsync(new Exception("Payment provider unavailable"));

        // Capture Update calls on PaymentMethods
        Domain.Entities.PaymentMethod? deactivatedPm = null;
        var mockPmSet = new Mock<DbSet<Domain.Entities.PaymentMethod>>();
        mockPmSet
            .Setup(s => s.FindAsync(It.IsAny<object[]>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new Domain.Entities.PaymentMethod { Id = 0, Status = true });
        mockPmSet
            .Setup(s => s.Update(It.IsAny<Domain.Entities.PaymentMethod>()))
            .Callback<Domain.Entities.PaymentMethod>(pm => deactivatedPm = pm);
        MockDbContext.Setup(db => db.PaymentMethods).Returns(mockPmSet.Object);

        var handler = CreateProcessPaymentHandler();

        // Act — expect the handler to re-throw wrapped in InvalidOperationException
        var act = () => handler.HandleAsync(BuildProcessPaymentCommand());
        await act.Should().ThrowAsync<InvalidOperationException>(
            because: "the handler re-throws payment failures as InvalidOperationException");

        // Assert — orphaned PM must be deactivated (fix 3)
        deactivatedPm.Should().NotBeNull(
            because: "the catch block must call Update on the PaymentMethod");
        deactivatedPm!.Status.Should().BeFalse(
            because: "PaymentMethod.Status must be set to false on failure to prevent orphaned active tokens");

        MockDbContext.Verify(
            db => db.SaveChangesAsync(CancellationToken.None),
            Times.AtLeastOnce,
            "deactivation SaveChangesAsync must use CancellationToken.None so it is not cancelled");
    }
}
