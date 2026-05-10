using System.Collections;
using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Moq;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.Features.Payments.Commands;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.PaymentGateway;
using XYDataLabs.OrderProcessingSystem.PaymentGateway.Configuration;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

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
    protected readonly Mock<IPaymentGatewayService> MockPaymentGateway = new();
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
    }

    // ------------------------------------------------------------------ factories

    protected ProcessPaymentCommandHandler CreateProcessPaymentHandler(bool use3DSecure = true)
    {
        var appMasterData = BuildAppMasterData(use3DSecure);
        return new ProcessPaymentCommandHandler(
            MockPaymentGateway.Object,
            Options.Create(new PaymentGatewayOptions
            {
                ProviderName = "DefaultGateway",
                RedirectUrl = "https://example.com/callback",
                DeviceSessionId = "default-device-session"
            }),
            new Mock<ILogger<ProcessPaymentCommandHandler>>().Object,
            MockDbContext.Object,
            appMasterData,
            MockTimeProvider.Object,
            MockTenantProvider.Object);
    }

    protected ConfirmPaymentStatusCommandHandler CreateConfirmPaymentHandler()
    {
        return new ConfirmPaymentStatusCommandHandler(
            MockDbContext.Object,
            MockPaymentGateway.Object,
            new Mock<ILogger<ConfirmPaymentStatusCommandHandler>>().Object,
            MockTimeProvider.Object);
    }

    // ------------------------------------------------------------------ DB-set wiring

    /// <summary>
    /// Sets up all DbSets used by ProcessPaymentCommandHandler.
    /// CardTransactions and TransactionStatusHistories are captured for assertion.
    /// </summary>
    protected void SetupPaymentDbSets(
        IEnumerable<BillingCustomer>? existingBillingCustomers = null,
        IEnumerable<PaymentAttempt>? existingPaymentAttempts = null)
    {
        _capturedCardTransactions.Clear();
        _capturedTsh.Clear();
        _capturedPaymentAttempts.Clear();
        _capturedPaymentAttemptHistories.Clear();

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
            new PaymentProvider { Id = 1, Name = "DefaultGateway", TenantId = 1, Use3DSecure = true }
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

    // ------------------------------------------------------------------ payment gateway wiring

    protected void SetupPaymentGatewayHappyPath(DateTime? cardDate = null, DateTime? chargeDate = null)
    {
        var fakeCustomer = new PaymentGatewayCustomer { Id = "provider-cust-001", Name = "John Doe", Email = "john@example.com" };
        var fakeCard = new PaymentGatewayCardToken { Id = "card-001", CreationDate = cardDate ?? UtcNow };
        var fakeCharge = new PaymentGatewayCharge
        {
            Id = "charge-001",
            Status = "completed",
            Amount = 100m,
            CreationDate = chargeDate ?? UtcNow,
            Authorization = "auth-ref-001"
        };

        MockPaymentGateway.Setup(s => s.CreateCustomerAsync(It.IsAny<PaymentGatewayCustomer>())).ReturnsAsync(fakeCustomer);
        MockPaymentGateway.Setup(s => s.CreateCardTokenAsync(It.IsAny<PaymentGatewayCardTokenRequest>())).ReturnsAsync(fakeCard);
        MockPaymentGateway.Setup(s => s.CreateChargeAsync(It.IsAny<PaymentGatewayChargeRequest>())).ReturnsAsync(fakeCharge);
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
        IReadOnlyDictionary<string, string>? callbackParameters = null) =>
        new(
            PaymentId: paymentId,
            AttemptOrderId: attemptOrderId,
            CallbackStatus: callbackStatus,
            ErrorMessage: null,
            CallbackParameters: callbackParameters);

    protected static CardTransaction BuildStubCardTransaction(int billingCustomerId = 42, bool isThreeDSecureEnabled = true) =>
        new()
        {
            Id = 1,
            BillingCustomerId = billingCustomerId,
            TransactionId = "charge-001",
            TransactionCustomerId = "provider-cust-001",
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
            ProviderChargeId = "charge-001",
            PaymentTraceId = "trace-001",
            Result = 0,
            IsThreeDSecureEnabled = isThreeDSecureEnabled,
            ThreeDSecureStage = isThreeDSecureEnabled
                ? "redirect_issued"
                : "not_applicable",
            CreatedBy = billingCustomerId,
            CreatedDate = UtcNow
        };

    // ------------------------------------------------------------------ AppMasterData helper

    /// <summary>
    /// Builds AppMasterData with a fake payment provider, using a PassThroughQueryable
    /// that safely ignores EF-specific expression nodes (AsNoTracking)
    /// so LINQ to Objects can evaluate the list correctly.
    /// </summary>
    private AppMasterData BuildAppMasterData(bool use3DSecure = true)
    {
        var provider = new PaymentProvider { Id = 1, Name = "DefaultGateway", TenantId = 1, Use3DSecure = use3DSecure };
        var list = new List<PaymentProvider> { provider };

        var mockProviderSet = new Mock<DbSet<PaymentProvider>>();
        mockProviderSet
            .As<IQueryable<PaymentProvider>>()
            .Setup(m => m.Provider)
            .Returns(new PassThroughQueryProvider<PaymentProvider>(list));
        mockProviderSet
            .As<IQueryable<PaymentProvider>>()
            .Setup(m => m.Expression)
            .Returns(list.AsQueryable().Expression);
        mockProviderSet
            .As<IQueryable<PaymentProvider>>()
            .Setup(m => m.ElementType)
            .Returns(typeof(PaymentProvider));
        mockProviderSet
            .As<IQueryable<PaymentProvider>>()
            .Setup(m => m.GetEnumerator())
            .Returns(() => list.GetEnumerator());

        var appMasterContext = new Mock<XYDataLabs.OrderProcessingSystem.Application.Abstractions.IAppDbContext>();
        appMasterContext.Setup(c => c.PaymentProviders).Returns(mockProviderSet.Object);

        return new AppMasterData(appMasterContext.Object);
    }

    // ------------------------------------------------------------------ nested helpers

    /// <summary>
    /// A query provider that bypasses EF Core-specific expression tree nodes
    /// (AsNoTracking) and always enumerates the backing list.
    /// This is safe for unit-test usage only — it ignores query filter semantics.
    /// </summary>
    private sealed class PassThroughQueryProvider<TEntity>(IEnumerable<TEntity> source) : IQueryProvider
    {
        private readonly IReadOnlyList<TEntity> _list = source.ToList();

        public IQueryable CreateQuery(Expression expression) =>
            new PassThroughQueryable<TEntity>(_list);

        public IQueryable<TElement> CreateQuery<TElement>(Expression expression) =>
            // Called by AsNoTracking(); return a new pass-through queryable
            (IQueryable<TElement>)(object)new PassThroughQueryable<TEntity>(_list);

        public object? Execute(Expression expression) => _list.ToList();

        public TResult Execute<TResult>(Expression expression) =>
            (TResult)(object)_list.ToList();
    }

    private sealed class PassThroughQueryable<TEntity>(IReadOnlyList<TEntity> list)
        : IQueryable<TEntity>
    {
        public Type ElementType => typeof(TEntity);
        public Expression Expression => list.AsQueryable().Expression;
        public IQueryProvider Provider => new PassThroughQueryProvider<TEntity>(list);
        public IEnumerator<TEntity> GetEnumerator() => list.GetEnumerator();
        IEnumerator IEnumerable.GetEnumerator() => list.GetEnumerator();
    }
}
