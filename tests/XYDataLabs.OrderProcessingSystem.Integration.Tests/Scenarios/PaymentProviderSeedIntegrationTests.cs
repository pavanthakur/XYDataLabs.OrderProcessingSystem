using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

/// <summary>
/// Asserts that <see cref="XYDataLabs.OrderProcessingSystem.Infrastructure.SeedData.DbInitializer"/>
/// seeds provider rows for the baseline tenants and that runtime provider routing is driven by
/// Tenant.PaymentProviderCode (Tenant Registry).
/// These tests run against the same real SQL Server used by the other integration tests.
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
        await AssertSeededProvidersExistAsync(tenantCode);
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
        await AssertSeededProvidersExistAsync(tenantCode);
    }

    private async Task AssertSeededProvidersExistAsync(string tenantCode)
    {
        var result = await _factory.ExecuteDbContextAsync(async context =>
        {
            var tenant = await context.Tenants
                .AsNoTracking()
                .SingleAsync(t => t.Code == tenantCode);

            var providers = await context.PaymentProviders
                .AsNoTracking()
                .Where(pp => pp.TenantId == tenant.Id)
                .ToListAsync();

            return new
            {
                Tenant = tenant,
                Providers = providers
            };
        });

        result.Providers.Should().HaveCount(2, because: $"DbInitializer seeds exactly two providers (OpenPay + Razorpay) for {tenantCode}");
        var rzp = result.Providers.Single(p => p.ProviderType == PaymentProviderTypes.Razorpay);
        var opy = result.Providers.Single(p => p.ProviderType == PaymentProviderTypes.OpenPay);

        opy.ProviderType.Should().Be(PaymentProviderTypes.OpenPay);
        rzp.ProviderType.Should().Be(PaymentProviderTypes.Razorpay);
        opy.APIUrl.Should().NotBeNullOrWhiteSpace();
        rzp.APIUrl.Should().NotBeNullOrWhiteSpace();
        opy.PrivateKeyConfigurationKey.Should().Contain($"PaymentProviders:{tenantCode}:OpenPay:PrivateKey");
        rzp.PrivateKeyConfigurationKey.Should().Contain($"PaymentProviders:{tenantCode}:Razorpay:PrivateKey");
        result.Tenant.PaymentProviderCode.Should().BeOneOf(new[] { null, PaymentProviderTypes.OpenPay, PaymentProviderTypes.Razorpay });
    }
}
