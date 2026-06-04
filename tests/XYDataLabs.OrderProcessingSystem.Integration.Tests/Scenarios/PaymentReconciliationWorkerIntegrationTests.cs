using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Openpay.Entities.Request;
using XYDataLabs.OpenPayAdapter;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class PaymentReconciliationWorkerIntegrationTests : IAsyncLifetime
{
    private readonly SqlServerFixture _fixture;
    private ServiceOverrideIntegrationTestFactory _factory = null!;

    public PaymentReconciliationWorkerIntegrationTests(SqlServerFixture fixture)
    {
        _fixture = fixture;
    }

    public Task InitializeAsync()
    {
        _factory = new ServiceOverrideIntegrationTestFactory(
            _fixture.ConnectionString,
            services => services.AddScoped<IOpenPayAdapterService, SuccessfulOpenPayAdapterStub>(),
            enableBackgroundWorkers: true,
            dedicatedConnectionString: _fixture.DedicatedDbConnectionString);
        _ = _factory.CreateClient(); // Force host initialization
        return Task.CompletedTask;
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
    }

    [Fact]
    public async Task Worker_Should_Resolve_UnknownNeedsReconciliation_To_Succeeded_When_Provider_Returns_Completed()
    {
        // Arrange
        var tenant = await IntegrationTestData.CreateTenantAsync(_factory);

        // Seed an active OpenPay provider for the dynamically created tenant so that
        // TenantPaymentProviderResolver.ResolveCurrentTenantProvider() can resolve it.
        // Phase 8.6: also update Tenant.PaymentProviderCode so the registry resolves OpenPay.
        await _factory.ExecuteTenantDbContextAsync(tenant.ToTenantContext(), async dbContext =>
        {
            dbContext.PaymentProviders.Add(new PaymentProvider
            {
                Name = "OpenPay",
                APIUrl = "https://sandbox-api.openpay.mx",
                IsProduction = false,
                IsActive = true,
                ProviderType = PaymentProviderTypes.OpenPay,
                Use3DSecure = false,
                TenantId = tenant.TenantId,
                CreatedBy = 1,
                CreatedDate = DateTime.UtcNow
            });

            var tenantRow = await dbContext.Tenants
                .IgnoreQueryFilters()
                .SingleAsync(t => t.Id == tenant.TenantId);
            tenantRow.PaymentProviderCode = PaymentProviderTypes.OpenPay;

            await dbContext.SaveChangesAsync();
            return true;
        });

        var paymentAttempt = new PaymentAttempt
        {
            AttemptOrderId = $"ORD-REC-{Guid.NewGuid():N}",
            CustomerOrderId = "ORD-123",
            PaymentTraceId = Guid.NewGuid().ToString("N"),
            AttemptNumber = 1,
            PaymentProviderName = "OpenPay",
            ProviderChargeId = "tr_invalid_test_charge",
            Status = PaymentAttemptStatus.UnknownNeedsReconciliation,
            ProviderStatus = "in_progress",
            TenantId = tenant.TenantId,
            CreatedDate = DateTime.UtcNow,
            CreatedBy = 0
        };
        
        await _factory.ExecuteTenantDbContextAsync(tenant.ToTenantContext(), async dbContext => {
            dbContext.PaymentAttempts.Add(paymentAttempt);
            await dbContext.SaveChangesAsync();
            return true;
        });

        // Resolve the worker from the host
        using var scope = _factory.Services.CreateScope();
        var hostServices = scope.ServiceProvider.GetServices<Microsoft.Extensions.Hosting.IHostedService>();
        var worker = hostServices.FirstOrDefault(s => s.GetType().Name == "PaymentReconciliationWorker");

        worker.Should().NotBeNull("PaymentReconciliationWorker should be registered.");

        // Use reflection to invoke the private ReconcilePaymentsAsync method to bypass the 60s delay loop
        var methodInfo = worker!.GetType().GetMethod("ReconcilePaymentsAsync", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        methodInfo.Should().NotBeNull();

        // Act
        var task = (Task)methodInfo!.Invoke(worker, new object[] { CancellationToken.None })!;
        await task;

        // Assert
        var updatedAttempt = await _factory.ExecuteTenantDbContextAsync(tenant.ToTenantContext(), async dbContext => {
            return await dbContext.PaymentAttempts.FirstOrDefaultAsync(x => x.AttemptOrderId == paymentAttempt.AttemptOrderId);
        });

        updatedAttempt.Should().NotBeNull();
        updatedAttempt!.Status.Should().Be(PaymentAttemptStatus.Succeeded);
        updatedAttempt.ProviderStatus.Should().Be("completed");
        updatedAttempt.LastErrorMessage.Should().Be("Reconciled successfully via Background Worker");
        updatedAttempt.UpdatedDate.Should().NotBeNull();
    }

    [Fact]
    public async Task Worker_Should_Skip_Razorpay_OrderIds_Until_Callback_Persists_A_PaymentId()
    {
        // Arrange
        var gateway = new TrackingRazorpayGatewayStub();
        await using var razorpayFactory = new ServiceOverrideIntegrationTestFactory(
            _fixture.ConnectionString,
            services =>
            {
                services.RemoveAll<IPaymentProviderGateway>();
                services.AddScoped<IPaymentProviderGateway>(_ => gateway);
            },
            enableBackgroundWorkers: true,
            dedicatedConnectionString: _fixture.DedicatedDbConnectionString);
        _ = razorpayFactory.CreateClient();

        var tenant = await IntegrationTestData.CreateTenantAsync(razorpayFactory);

        await razorpayFactory.ExecuteTenantDbContextAsync(tenant.ToTenantContext(), async dbContext =>
        {
            dbContext.PaymentProviders.Add(new PaymentProvider
            {
                Name = "Razorpay",
                APIUrl = "https://api.razorpay.com",
                IsProduction = false,
                IsActive = true,
                ProviderType = PaymentProviderTypes.Razorpay,
                Use3DSecure = false,
                TenantId = tenant.TenantId,
                CreatedBy = 1,
                CreatedDate = DateTime.UtcNow
            });

            // Phase 8.6: also update Tenant.PaymentProviderCode so the registry resolves Razorpay.
            var tenantRow = await dbContext.Tenants
                .IgnoreQueryFilters()
                .SingleAsync(t => t.Id == tenant.TenantId);
            tenantRow.PaymentProviderCode = PaymentProviderTypes.Razorpay;

            await dbContext.SaveChangesAsync();
            return true;
        });

        var paymentAttempt = new PaymentAttempt
        {
            AttemptOrderId = $"ORD-RZP-REC-{Guid.NewGuid():N}",
            CustomerOrderId = "ORD-RZP-123",
            PaymentTraceId = Guid.NewGuid().ToString("N"),
            AttemptNumber = 1,
            PaymentProviderName = "Razorpay",
            ProviderChargeId = "order_test_pending_123",
            Status = PaymentAttemptStatus.UnknownNeedsReconciliation,
            ProviderStatus = "created",
            TenantId = tenant.TenantId,
            CreatedDate = DateTime.UtcNow,
            CreatedBy = 0
        };

        await razorpayFactory.ExecuteTenantDbContextAsync(tenant.ToTenantContext(), async dbContext =>
        {
            dbContext.PaymentAttempts.Add(paymentAttempt);
            await dbContext.SaveChangesAsync();
            return true;
        });

        using var scope = razorpayFactory.Services.CreateScope();
        var hostServices = scope.ServiceProvider.GetServices<Microsoft.Extensions.Hosting.IHostedService>();
        var worker = hostServices.FirstOrDefault(s => s.GetType().Name == "PaymentReconciliationWorker");

        worker.Should().NotBeNull("PaymentReconciliationWorker should be registered.");

        var methodInfo = worker!.GetType().GetMethod("ReconcilePaymentsAsync", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        methodInfo.Should().NotBeNull();

        // Act
        var task = (Task)methodInfo!.Invoke(worker, new object[] { CancellationToken.None })!;
        await task;

        // Assert
        var updatedAttempt = await razorpayFactory.ExecuteTenantDbContextAsync(tenant.ToTenantContext(), async dbContext =>
        {
            return await dbContext.PaymentAttempts.FirstOrDefaultAsync(x => x.AttemptOrderId == paymentAttempt.AttemptOrderId);
        });

        updatedAttempt.Should().NotBeNull();
        updatedAttempt!.Status.Should().Be(PaymentAttemptStatus.UnknownNeedsReconciliation);
        updatedAttempt.ProviderStatus.Should().Be("created");
        updatedAttempt.LastErrorMessage.Should().Be("Razorpay reconciliation is waiting for the provider payment id from callback/webhook; the current order id cannot be used for charge lookup yet.");
        gateway.GetChargeCallCount.Should().Be(0);
    }

    private sealed class SuccessfulOpenPayAdapterStub : IOpenPayAdapterService
    {
        public string ProviderType => PaymentProviderTypes.OpenPay;

        public Task<Openpay.Entities.Customer> CreateCustomerAsync(Openpay.Entities.Customer customer)
        {
            throw new NotSupportedException();
        }

        public Task<Openpay.Entities.Card> CreateCardTokenAsync(Openpay.Entities.Card card)
        {
            throw new NotSupportedException();
        }

        public Task<Openpay.Entities.Charge> CreateChargeAsync(ChargeRequest request)
        {
            throw new NotSupportedException();
        }

        public Task<Openpay.Entities.Charge> GetChargeAsync(string chargeId, string? customerId = null)
        {
            return Task.FromResult(new Openpay.Entities.Charge
            {
                Id = chargeId,
                Status = "completed",
                Authorization = "reconciled-auth"
            });
        }
    }

    private sealed class TrackingRazorpayGatewayStub : IPaymentProviderGateway
    {
        public string ProviderType => PaymentProviderTypes.Razorpay;

        public int GetChargeCallCount { get; private set; }

        public Task<PaymentGatewayCustomer> CreateCustomerAsync(PaymentGatewayCreateCustomerRequest request, CancellationToken cancellationToken = default)
        {
            throw new NotSupportedException();
        }

        public Task<PaymentGatewayCardToken> CreateCardTokenAsync(PaymentGatewayCreateCardTokenRequest request, CancellationToken cancellationToken = default)
        {
            throw new NotSupportedException();
        }

        public Task<PaymentGatewayChargeResult> CreateChargeAsync(PaymentGatewayCreateChargeRequest request, CancellationToken cancellationToken = default)
        {
            throw new NotSupportedException();
        }

        public Task<PaymentGatewayChargeResult> GetChargeAsync(string chargeId, string? customerId = null, CancellationToken cancellationToken = default)
        {
            GetChargeCallCount += 1;
            return Task.FromResult(new PaymentGatewayChargeResult(
                Id: chargeId,
                Status: "completed",
                Amount: 100,
                CreatedAt: DateTime.UtcNow,
                Authorization: null,
                ErrorMessage: null,
                RedirectUrl: null));
        }
    }
}