using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class TenantIsolationTests : IAsyncLifetime
{
    private readonly SqlServerFixture _fixture;
    private IntegrationTestWebAppFactory _factory = null!;

    public TenantIsolationTests(SqlServerFixture fixture)
    {
        _fixture = fixture;
    }

    public Task InitializeAsync()
    {
        _factory = new IntegrationTestWebAppFactory(_fixture.ConnectionString);
        _ = _factory.CreateClient();
        return Task.CompletedTask;
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
    }

    [Fact]
    public async Task TenantScoped_DbContext_Should_Isolate_TenantOwned_Entities()
    {
        var tenantA = await IntegrationTestData.CreateTenantAsync(_factory);
        var tenantB = await IntegrationTestData.CreateTenantAsync(_factory);
        var tenantASeed = await IntegrationTestData.SeedTenantIsolationAsync(_factory, tenantA.TenantId, "tenant-a");
        var tenantBSeed = await IntegrationTestData.SeedTenantIsolationAsync(_factory, tenantB.TenantId, "tenant-b");

        var tenantAView = await _factory.ExecuteTenantDbContextAsync(tenantA.ToTenantContext(), async dbContext => new
        {
            CustomerEmails = await dbContext.Customers.OrderBy(item => item.CustomerId).Select(item => item.Email).ToListAsync(),
            ProductNames = await dbContext.Products.OrderBy(item => item.ProductId).Select(item => item.Name).ToListAsync(),
            OrderIds = await dbContext.Orders.OrderBy(item => item.OrderId).Select(item => item.OrderId.Value).ToListAsync(),
            OrderProducts = await dbContext.OrderProducts
                .OrderBy(item => item.OrderId)
                .Select(item => $"{item.OrderId.Value}:{item.ProductId.Value}")
                .ToListAsync(),
            PaymentProviderNames = await dbContext.PaymentProviders.OrderBy(item => item.Id).Select(item => item.Name).ToListAsync(),
            PaymentMethodTokens = await dbContext.PaymentMethods.OrderBy(item => item.Id).Select(item => item.Token).ToListAsync()
        });

        tenantAView.CustomerEmails.Should().ContainSingle().Which.Should().Be(tenantASeed.CustomerEmail);
        tenantAView.ProductNames.Should().ContainSingle().Which.Should().Be(tenantASeed.ProductName);
        tenantAView.OrderIds.Should().ContainSingle().Which.Should().Be(tenantASeed.OrderId);
        tenantAView.OrderProducts.Should().ContainSingle().Which.Should().Be($"{tenantASeed.OrderId}:{tenantASeed.ProductId}");
        tenantAView.PaymentProviderNames.Should().ContainSingle().Which.Should().Be(tenantASeed.PaymentProviderName);
        tenantAView.PaymentMethodTokens.Should().ContainSingle().Which.Should().Be(tenantASeed.PaymentMethodToken);

        tenantAView.CustomerEmails.Should().NotContain(tenantBSeed.CustomerEmail);
        tenantAView.ProductNames.Should().NotContain(tenantBSeed.ProductName);
        tenantAView.OrderIds.Should().NotContain(tenantBSeed.OrderId);
        tenantAView.OrderProducts.Should().NotContain($"{tenantBSeed.OrderId}:{tenantBSeed.ProductId}");
        tenantAView.PaymentProviderNames.Should().NotContain(tenantBSeed.PaymentProviderName);
        tenantAView.PaymentMethodTokens.Should().NotContain(tenantBSeed.PaymentMethodToken);
    }
}