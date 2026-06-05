using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

/// <summary>
/// Asserts that <see cref="XYDataLabs.OrderProcessingSystem.Infrastructure.SeedData.DbInitializer"/>
/// seeds provider rows with IsActive=false for all baseline tenants.
/// Phase 8.6: active provider is now authoritative from Tenant.PaymentProviderCode (Tenant Registry).
/// DbInitializer seeds both providers as inactive — routing is not determined at startup seeding time.
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
    [InlineData("TenantA")]
    [InlineData("TenantB")]
    public async Task AfterStartup_BaselineTenant_BothProvidersSeededAsInactive(string tenantCode)
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
            $"DbInitializer seeds exactly two providers (OpenPay + Razorpay) for {tenantCode}");
        var rzp = providers.Single(p => p.ProviderType == PaymentProviderTypes.Razorpay);
        var opy = providers.Single(p => p.ProviderType == PaymentProviderTypes.OpenPay);
        opy.Use3DSecure.Should().BeTrue($"OpenPay seeds with 3DS enabled ({tenantCode})");
        rzp.Use3DSecure.Should().BeFalse(
            $"{tenantCode} Razorpay uses hosted provider_checkout; S2S/direct_card_form is disabled for all tenants");
        providers.Should().OnlyContain(
            provider => !provider.IsActive,
            $"Phase 8.6: all seeded provider rows must be IsActive=false — routing authority is Tenant Registry ({tenantCode})");
    }

    [Fact]
    public async Task AfterStartup_TenantA_BothProvidersInactive()
    {
        await AssertBothProvidersInactive("TenantA");
    }

    [Fact]
    public async Task AfterStartup_TenantB_BothProvidersInactive()
    {
        await AssertBothProvidersInactive("TenantB");
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private async Task AssertBothProvidersInactive(string tenantCode)
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
        var rzp = providers.Single(p => p.ProviderType == PaymentProviderTypes.Razorpay);
        var opy = providers.Single(p => p.ProviderType == PaymentProviderTypes.OpenPay);
        opy.Use3DSecure.Should().BeTrue(because: $"OpenPay seeds with 3DS enabled ({tenantCode})");
        rzp.Use3DSecure.Should().BeFalse(
            because: $"{tenantCode} Razorpay uses hosted provider_checkout; S2S/direct_card_form is disabled for all tenants");
        providers.Should().OnlyContain(
            provider => !provider.IsActive,
            because: $"Phase 8.6: routing authority is Tenant Registry — all seeded rows must be inactive ({tenantCode})");
    }
}
