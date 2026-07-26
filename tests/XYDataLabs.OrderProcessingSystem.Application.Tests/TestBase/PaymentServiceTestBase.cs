using System.Collections;
using System.Security.Cryptography;
using System.Text;
using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Moq;
using XYDataLabs.OpenPayAdapter;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;
using XYDataLabs.OrderProcessingSystem.Payments.Features.Commands;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.TestBase;

/// <summary>
/// Shared test infrastructure for ProcessPaymentCommandHandler and ConfirmPaymentStatusCommandHandler.
/// Handles the complex mock wiring needed by these handlers.
/// </summary>
public class PaymentServiceTestBase : OrderProcessingSystemTestBase<ProcessPaymentCommandHandler>
{
    private readonly List<CardTransaction> _capturedCardTransactions = [];
    private readonly List<TransactionStatusHistory> _capturedTsh = [];
    private readonly List<PayinLogDetails> _capturedPayinLogDetails = [];
    private readonly List<PaymentAttempt> _capturedPaymentAttempts = [];
    private readonly List<PaymentAttemptHistory> _capturedPaymentAttemptHistories = [];

    // --- fixed reference time ---
    protected static readonly DateTime UtcNow = new(2024, 3, 1, 10, 0, 0, DateTimeKind.Utc);

    // --- shared mocks ---
    protected readonly Mock<IOpenPayAdapterService> MockOpenPayAdapter = new();
    protected readonly Mock<IPaymentProviderGateway> MockPaymentGateway = new();
    protected readonly Mock<ITenantPaymentProviderResolver> MockPaymentProviderResolver = new();
    protected readonly Mock<ITenantPaymentProviderConfigurationResolver> MockPaymentProviderConfigurationResolver = new();
    protected readonly Mock<ITenantProvider> MockTenantProvider = new();
    protected readonly Mock<TimeProvider> MockTimeProvider = new();

    // --- capture lists filled by SetupPaymentDbSets() ---
    protected IList<CardTransaction> CapturedCardTransactions => _capturedCardTransactions;
    protected IList<TransactionStatusHistory> CapturedTsh => _capturedTsh;
    protected IList<PayinLogDetails> CapturedPayinLogDetails => _capturedPayinLogDetails;
    protected IList<PaymentAttempt> CapturedPaymentAttempts => _capturedPaymentAttempts;
    protected IList<PaymentAttemptHistory> CapturedPaymentAttemptHistories => _capturedPaymentAttemptHistories;

    public PaymentServiceTestBase()
    {
        MockTimeProvider.Setup(t => t.GetUtcNow()).Returns(new DateTimeOffset(UtcNow));
        MockTenantProvider.Setup(t => t.TenantCode).Returns("tenant-a");
        MockTenantProvider.Setup(t => t.TenantId).Returns(1);
        MockOpenPayAdapter.SetupGet(adapter => adapter.ProviderType).Returns(PaymentProviderTypes.OpenPay);
        MockPaymentProviderConfigurationResolver
            .Setup(r => r.ResolveCurrentTenantConfiguration())
            .Returns(new PaymentProviderRuntimeConfiguration(
                PaymentProviderTypes.Razorpay,
                "rzp_test_merchant",
                null,
                "razorpay-test-secret",
                false));
    }

    // ------------------------------------------------------------------ factories

    protected ProcessPaymentCommandHandler CreateProcessPaymentHandler(
        bool use3DSecure = true,
        string providerType = PaymentProviderTypes.OpenPay)
    {
        var paymentProvider = BuildPaymentProvider(use3DSecure, providerType);
        MockPaymentGateway.SetupGet(g => g.ProviderType).Returns(paymentProvider.ProviderType);
        MockPaymentProviderResolver
            .Setup(r => r.ResolveCurrentTenantProvider())
            .Returns(paymentProvider);
        return new ProcessPaymentCommandHandler(
            MockPaymentGateway.Object,
            Options.Create(new PaymentGatewayRequestDefaults
            {
                RedirectUrl = "https://example.com/callback",
                DeviceSessionId = "default-device-session"
            }),
            NullPaymentTelemetryTracker.Instance,
            new Mock<ILogger<ProcessPaymentCommandHandler>>().Object,
            MockDbContext.Object,
            MockPaymentProviderResolver.Object,
            MockTimeProvider.Object,
            MockTenantProvider.Object);
    }

    protected ConfirmPaymentStatusCommandHandler CreateConfirmPaymentHandler(string providerType = PaymentProviderTypes.OpenPay)
    {
        var paymentProvider = BuildPaymentProvider(providerType: providerType);
        MockPaymentProviderResolver
            .Setup(r => r.ResolveCurrentTenantProvider())
            .Returns(paymentProvider);

        if (string.Equals(providerType, PaymentProviderTypes.OpenPay, StringComparison.OrdinalIgnoreCase))
        {
            return new ConfirmPaymentStatusCommandHandler(
                MockDbContext.Object,
                new OpenPayPaymentGateway(MockOpenPayAdapter.Object),
                NullPaymentTelemetryTracker.Instance,
                new Mock<ILogger<ConfirmPaymentStatusCommandHandler>>().Object,
                MockPaymentProviderConfigurationResolver.Object,
                MockPaymentProviderResolver.Object,
                MockTenantProvider.Object,
                MockTimeProvider.Object);
        }

        MockPaymentGateway.SetupGet(g => g.ProviderType).Returns(providerType);

        return new ConfirmPaymentStatusCommandHandler(
            MockDbContext.Object,
            MockPaymentGateway.Object,
            NullPaymentTelemetryTracker.Instance,
            new Mock<ILogger<ConfirmPaymentStatusCommandHandler>>().Object,
            MockPaymentProviderConfigurationResolver.Object,
            MockPaymentProviderResolver.Object,
            MockTenantProvider.Object,
            MockTimeProvider.Object);
    }

    // ------------------------------------------------------------------ DB-set wiring

    /// <summary>
    /// Sets up all DbSets used by ProcessPaymentCommandHandler.
    /// CardTransactions and TransactionStatusHistories are captured for assertion.
    /// </summary>
    protected void SetupPaymentDbSets(
        IEnumerable<BillingCustomer>? existingBillingCustomers = null,
        IEnumerable<PaymentAttempt>? existingPaymentAttempts = null,
        string providerType = PaymentProviderTypes.OpenPay)
    {
        _capturedCardTransactions.Clear();
        _capturedTsh.Clear();
        _capturedPaymentAttempts.Clear();
        _capturedPaymentAttemptHistories.Clear();

        var orderProduct = new Product
        {
            ProductId = 1,
            Name = "Payment test product",
            Price = 100m
        };
        var order = Order.Create(1, [orderProduct]).Value!;
        order.OrderId = 1;
        MockDbContext.Setup(db => db.Orders)
            .Returns(GetMockDbSet(new[] { order }.AsQueryable()).Object);

        // PaymentMethods —FindAsync returns a stable PM (needed by UpdatePaymentMethodByBillingCustomerId)
        var stubPm = new Domain.Entities.PaymentMethod { Id = 0, Token = "pm-token", Status = true, PaymentProviderId = 1 };
        var mockPmSet = new Mock<DbSet<Domain.Entities.PaymentMethod>>();
        mockPmSet
            .Setup(s => s.FindAsync(It.IsAny<object[]>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(stubPm);
        MockDbContext.Setup(db => db.PaymentMethods).Returns(mockPmSet.Object);

        // BillingCustomers — empty list = new customer path; populated = existing customer path
        var billingCustomers = (existingBillingCustomers ?? Enumerable.Empty<BillingCustomer>()).AsQueryable();
        MockDbContext.Setup(db => db.BillingCustomers).Returns(GetMockDbSet(billingCustomers).Object);

        // CardTransactions — capture adds
        var mockCtSet = new Mock<DbSet<CardTransaction>>();
        mockCtSet.Setup(s => s.Add(It.IsAny<CardTransaction>()))
            .Callback<CardTransaction>(ct => _capturedCardTransactions.Add(ct));
        MockDbContext.Setup(db => db.CardTransactions).Returns(mockCtSet.Object);

        var paymentAttempts = (existingPaymentAttempts ?? Enumerable.Empty<PaymentAttempt>()).ToList();
        var mockPaymentAttemptSet = GetMockDbSet(paymentAttempts.AsQueryable());
        mockPaymentAttemptSet
            .Setup(s => s.Add(It.IsAny<PaymentAttempt>()))
            .Callback<PaymentAttempt>(attempt =>
            {
                attempt.Id = paymentAttempts.Count + 1;
                paymentAttempts.Add(attempt);
                _capturedPaymentAttempts.Add(attempt);
            });
        mockPaymentAttemptSet
            .Setup(s => s.Update(It.IsAny<PaymentAttempt>()))
            .Callback<PaymentAttempt>(_ => { });
        MockDbContext.Setup(db => db.PaymentAttempts).Returns(mockPaymentAttemptSet.Object);

        var paymentAttemptHistories = new List<PaymentAttemptHistory>();
        var mockPaymentAttemptHistorySet = new Mock<DbSet<PaymentAttemptHistory>>();
        mockPaymentAttemptHistorySet
            .Setup(s => s.Add(It.IsAny<PaymentAttemptHistory>()))
            .Callback<PaymentAttemptHistory>(history =>
            {
                paymentAttemptHistories.Add(history);
                _capturedPaymentAttemptHistories.Add(history);
            });
        MockDbContext.Setup(db => db.PaymentAttemptHistories).Returns(mockPaymentAttemptHistorySet.Object);

        // TransactionStatusHistories — capture adds
        var mockTshSet = new Mock<DbSet<TransactionStatusHistory>>();
        mockTshSet.Setup(s => s.Add(It.IsAny<TransactionStatusHistory>()))
            .Callback<TransactionStatusHistory>(tsh => _capturedTsh.Add(tsh));
        MockDbContext.Setup(db => db.TransactionStatusHistories).Returns(mockTshSet.Object);

        // No-op mocks for remaining write targets
        MockDbContext.Setup(db => db.PayinLogs).Returns(new Mock<DbSet<PayinLog>>().Object);
        MockDbContext.Setup(db => db.PayinLogDetails).Returns(new Mock<DbSet<PayinLogDetails>>().Object);
        MockDbContext.Setup(db => db.BillingCustomerKeyInfos).Returns(new Mock<DbSet<BillingCustomerKeyInfo>>().Object);

        // PaymentProviders — needed by CreatePaymentMethodAsync to resolve FK-safe PaymentProviderId
        var providers = new List<PaymentProvider>
        {
            new PaymentProvider { Id = 1, Name = providerType, ProviderType = providerType, TenantId = 1, Use3DSecure = true, IsActive = true }
        }.AsQueryable();
        MockDbContext.Setup(db => db.PaymentProviders).Returns(GetMockDbSet(providers).Object);

        MockDbContext.Setup(db => db.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);


    }

    /// <summary>
    /// Sets up DbSets needed by ConfirmPaymentStatusCommandHandler.
    /// </summary>
    protected void SetupConfirmPaymentDbSets(
        CardTransaction? existingTransaction = null,
        PayinLog? existingPayinLog = null,
        IEnumerable<TransactionStatusHistory>? existingTransactionStatusHistories = null,
        PaymentAttempt? existingPaymentAttempt = null,
        IEnumerable<PaymentAttemptHistory>? existingPaymentAttemptHistories = null)
    {
        _capturedTsh.Clear();
        _capturedPayinLogDetails.Clear();
        _capturedPaymentAttempts.Clear();
        _capturedPaymentAttemptHistories.Clear();

        var transactions = existingTransaction is null
            ? Enumerable.Empty<CardTransaction>()
            : new[] { existingTransaction };
        MockDbContext.Setup(db => db.CardTransactions)
            .Returns(GetMockDbSet(transactions.AsQueryable()).Object);

        var payinLogs = existingPayinLog is null
            ? Enumerable.Empty<PayinLog>()
            : new[] { existingPayinLog };
        MockDbContext.Setup(db => db.PayinLogs)
            .Returns(GetMockDbSet(payinLogs.AsQueryable()).Object);

        var paymentAttempts = existingPaymentAttempt is null
            ? Enumerable.Empty<PaymentAttempt>()
            : new[] { existingPaymentAttempt };
        var mockPaymentAttemptSet = GetMockDbSet(paymentAttempts.AsQueryable());
        mockPaymentAttemptSet.Setup(s => s.Update(It.IsAny<PaymentAttempt>()))
            .Callback<PaymentAttempt>(attempt => _capturedPaymentAttempts.Add(attempt));
        MockDbContext.Setup(db => db.PaymentAttempts).Returns(mockPaymentAttemptSet.Object);

        var paymentAttemptHistories = (existingPaymentAttemptHistories ?? Enumerable.Empty<PaymentAttemptHistory>()).ToList();
        var mockPaymentAttemptHistorySet = GetMockDbSet(paymentAttemptHistories.AsQueryable());
        mockPaymentAttemptHistorySet.Setup(s => s.Add(It.IsAny<PaymentAttemptHistory>()))
            .Callback<PaymentAttemptHistory>(history =>
            {
                paymentAttemptHistories.Add(history);
                _capturedPaymentAttemptHistories.Add(history);
            });
        MockDbContext.Setup(db => db.PaymentAttemptHistories).Returns(mockPaymentAttemptHistorySet.Object);

        var transactionStatusHistories = (existingTransactionStatusHistories ?? Enumerable.Empty<TransactionStatusHistory>()).ToList();
        var mockTshSet = GetMockDbSet(transactionStatusHistories.AsQueryable());
        mockTshSet.Setup(s => s.Add(It.IsAny<TransactionStatusHistory>()))
            .Callback<TransactionStatusHistory>(tsh =>
            {
                transactionStatusHistories.Add(tsh);
                _capturedTsh.Add(tsh);
            });
        MockDbContext.Setup(db => db.TransactionStatusHistories).Returns(mockTshSet.Object);

        var payinLogDetails = new List<PayinLogDetails>();
        var mockPayinLogDetailsSet = new Mock<DbSet<PayinLogDetails>>();
        mockPayinLogDetailsSet.Setup(s => s.Add(It.IsAny<PayinLogDetails>()))
            .Callback<PayinLogDetails>(detail =>
            {
                payinLogDetails.Add(detail);
                _capturedPayinLogDetails.Add(detail);
            });
        MockDbContext.Setup(db => db.PayinLogDetails).Returns(mockPayinLogDetailsSet.Object);
        MockDbContext.Setup(db => db.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);
    }

    // ------------------------------------------------------------------ OpenPay wiring

    protected void SetupOpenPayHappyPath(DateTime? cardDate = null, DateTime? chargeDate = null)
    {
        var fakeCustomer = new PaymentGatewayCustomer("openpay-cust-001", "John Doe", "john@example.com");
        var fakeCard = new PaymentGatewayCardToken("card-001", cardDate ?? UtcNow);
        var fakeCharge = new PaymentGatewayChargeResult(
            "charge-001",
            "completed",
            100m,
            chargeDate ?? UtcNow,
            "auth-ref-001",
            null,
            null);

        MockPaymentGateway.Setup(s => s.CreateCustomerAsync(It.IsAny<PaymentGatewayCreateCustomerRequest>(), It.IsAny<CancellationToken>())).ReturnsAsync(fakeCustomer);
        MockPaymentGateway.Setup(s => s.CreateCardTokenAsync(It.IsAny<PaymentGatewayCreateCardTokenRequest>(), It.IsAny<CancellationToken>())).ReturnsAsync(fakeCard);
        MockPaymentGateway.Setup(s => s.CreateChargeAsync(It.IsAny<PaymentGatewayCreateChargeRequest>(), It.IsAny<CancellationToken>())).ReturnsAsync(fakeCharge);
    }

    // ------------------------------------------------------------------ command builders

    protected static ProcessPaymentCommand BuildProcessPaymentCommand(string customerOrderId = "ORDER-001") =>
        new(
            Name: "John Doe",
            Email: "john@example.com",
            DeviceSessionId: "device-session-001",
            CardNumber: "4111111111111111",
            ExpirationYear: "25",
            ExpirationMonth: "12",
            Cvv2: "123",
            CustomerOrderId: customerOrderId,
            ClientCallbackOrigin: null);

    protected static ConfirmPaymentStatusCommand BuildConfirmPaymentCommand(
        string paymentId = "charge-001",
        string? attemptOrderId = "attempt-001",
        string? callbackStatus = null,
        string? errorMessage = null,
        IReadOnlyDictionary<string, string>? callbackParameters = null) =>
        new(
            PaymentId: paymentId,
            AttemptOrderId: attemptOrderId,
            CallbackStatus: callbackStatus,
            ErrorMessage: errorMessage,
            CallbackParameters: callbackParameters);

    protected static CardTransaction BuildStubCardTransaction(int billingCustomerId = 42, bool isThreeDSecureEnabled = true) =>
        new()
        {
            Id = 1,
            BillingCustomerId = billingCustomerId,
            TransactionId = "charge-001",
            TransactionCustomerId = "openpay-cust-001",
            AttemptOrderId = "attempt-001",
            CustomerOrderId = "ORDER-001",
            PaymentTraceId = "trace-001",
            TransactionStatus = "charge_pending",
            IsThreeDSecureEnabled = isThreeDSecureEnabled,
            IsTransactionSuccess = false,
            TransactionDate = UtcNow,
            TransactionReferenceId = "ref-001"
        };

    protected static PayinLog BuildStubPayinLog(int billingCustomerId = 42, bool isThreeDSecureEnabled = true) =>
        new()
        {
            Id = 1,
            AttemptOrderId = "attempt-001",
            OpenPayChargeId = "charge-001",
            PaymentTraceId = "trace-001",
            Result = 0,
            IsThreeDSecureEnabled = isThreeDSecureEnabled,
            ThreeDSecureStage = isThreeDSecureEnabled
                ? "redirect_issued"
                : "not_applicable",
            CreatedBy = billingCustomerId,
            CreatedDate = UtcNow
        };

    protected static string BuildRazorpaySignature(string orderId, string paymentId, string secret = "razorpay-test-secret")
    {
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes($"{orderId}|{paymentId}"));
        return Convert.ToHexString(hash);
    }

    // ------------------------------------------------------------------ AppMasterData helper

    /// <summary>
    /// Builds AppMasterData with a fake payment provider, using a PassThroughQueryable
    /// that safely ignores EF-specific expression nodes (AsNoTracking)
    /// so LINQ to Objects can evaluate the list correctly.
    /// </summary>
    private static PaymentProvider BuildPaymentProvider(bool use3DSecure = true, string providerType = PaymentProviderTypes.OpenPay)
    {
        return new PaymentProvider
        {
            Id = 1,
            Name = providerType,
            ProviderType = providerType,
            TenantId = 1,
            Use3DSecure = use3DSecure,
            IsActive = true
        };
    }
}
