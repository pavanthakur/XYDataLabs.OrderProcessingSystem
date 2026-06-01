using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

/// <summary>
/// Asserts that <see cref="XYDataLabs.OrderProcessingSystem.Infrastructure.SeedData.DbInitializer"/>
/// seeds provider rows and applies the generic default only when a baseline tenant has no
/// database-selected active provider when the application starts.
/// These tests run against a real SQL Server via Testcontainers (same DB as other integration tests).
/// </summary>
[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class PaymentProviderSeedIntegrationTests : IAsyncLifetime
{
    private readonly SqlServerFixture _fixture;
    private IntegrationTestWebAppFactory _factory = null!;

    public PaymentProviderSeedIntegrationTests(SqlServerFixture fixture)
    {
        _fixture = fixture;
    }

    public Task InitializeAsync()
    {
        _factory = new IntegrationTestWebAppFactory(_fixture.ConnectionString);
        _ = _factory.CreateClient();   // triggers Program.cs → DbInitializer.Initialize()
        return Task.CompletedTask;
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
    }

    [Theory]
    [InlineData("TenantA", PaymentProviderTypes.Razorpay, PaymentProviderTypes.OpenPay)]
    [InlineData("TenantB", PaymentProviderTypes.Razorpay, PaymentProviderTypes.OpenPay)]
    public async Task AfterStartup_BaselineTenant_HasCorrectProviderActiveState(
        string tenantCode,
        string expectedActiveProviderType,
        string expectedInactiveProviderType)
    {
        var providers = await _factory.ExecuteDbContextAsync(async context =>
        {
            var tenant = await context.Tenants
                .AsNoTracking()
                .SingleAsync(t => t.Code == tenantCode);

            return await context.PaymentProviders
                .AsNoTracking()
                .Where(pp => pp.TenantId == tenant.Id)
                .ToListAsync();
        });

        providers.Should().HaveCount(2,
            $"DbInitializer should seed exactly two providers (OpenPay + Razorpay) for {tenantCode}");

        providers.Single(pp => pp.ProviderType == expectedActiveProviderType)
            .IsActive.Should().BeTrue(
                $"the generic seed default should activate {expectedActiveProviderType} for {tenantCode} when no active provider row exists");

        providers.Single(pp => pp.ProviderType == expectedInactiveProviderType)
            .IsActive.Should().BeFalse(
                $"the non-assigned provider ({expectedInactiveProviderType}) must be inactive for {tenantCode}");
    }

    [Fact]
        public async Task AfterStartup_TenantA_RazorpayIsActive_OpenPayIsInactive()
    {
        await AssertProviderState("TenantA",
            activeType: PaymentProviderTypes.Razorpay,
            inactiveType: PaymentProviderTypes.OpenPay);
    }

    [Fact]
        public async Task AfterStartup_TenantB_RazorpayIsActive_OpenPayIsInactive()
    {
        await AssertProviderState("TenantB",
            activeType: PaymentProviderTypes.Razorpay,
            inactiveType: PaymentProviderTypes.OpenPay);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private async Task AssertProviderState(string tenantCode, string activeType, string inactiveType)
    {
        var providers = await _factory.ExecuteDbContextAsync(async context =>
        {
            var tenant = await context.Tenants
                .AsNoTracking()
                .SingleAsync(t => t.Code == tenantCode);

            return await context.PaymentProviders
                .AsNoTracking()
                .Where(pp => pp.TenantId == tenant.Id)
                .ToListAsync();
        });

        providers.Should().HaveCount(2, because: $"two providers seeded for {tenantCode}");
        providers.Single(pp => pp.ProviderType == activeType).IsActive.Should().BeTrue();
        providers.Single(pp => pp.ProviderType == inactiveType).IsActive.Should().BeFalse();
    }
}
