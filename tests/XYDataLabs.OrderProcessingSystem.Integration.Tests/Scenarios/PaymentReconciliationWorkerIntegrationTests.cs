using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Openpay.Entities.Request;
using XYDataLabs.OpenPayAdapter;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

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
            services => services.AddScoped<IOpenPayAdapterService, SuccessfulOpenPayAdapterStub>());
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

    private sealed class SuccessfulOpenPayAdapterStub : IOpenPayAdapterService
    {
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
}