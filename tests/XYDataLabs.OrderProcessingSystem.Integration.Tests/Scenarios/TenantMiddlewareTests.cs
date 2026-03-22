using System.Net;
using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class TenantMiddlewareTests : IAsyncLifetime
{
    private readonly SqlServerFixture _fixture;
    private IntegrationTestWebAppFactory _factory = null!;

    public TenantMiddlewareTests(SqlServerFixture fixture)
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
    public async Task HealthCheck_WithoutTenantHeader_ReturnsBadRequest()
    {
        using var client = _factory.CreateClient();

        var response = await client.GetAsync("/health");
        var body = await response.Content.ReadAsStringAsync();

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        body.Should().Contain("Missing required header");
    }

    [Fact]
    public async Task RuntimeConfiguration_WithoutTenantHeader_ReturnsOk()
    {
        using var client = _factory.CreateClient();

        var response = await client.GetAsync("/api/v1/info/runtime-configuration");
        var body = await response.Content.ReadAsStringAsync();

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        body.Should().Contain("activeTenantCode");
        body.Should().Contain("X-Tenant-Code");
    }

    [Fact]
    public async Task HealthCheck_WithUnknownTenantCode_ReturnsBadRequest()
    {
        using var client = _factory.CreateTenantClient($"UNKNOWN-{Guid.NewGuid():N}"[..18]);

        var response = await client.GetAsync("/health");
        var body = await response.Content.ReadAsStringAsync();

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        body.Should().Contain("is not recognized");
    }

    [Theory]
    [InlineData("Suspended")]
    [InlineData("Decommissioned")]
    public async Task HealthCheck_WithBlockedTenantStatus_ReturnsForbidden(string tenantStatus)
    {
        var tenant = await IntegrationTestData.CreateTenantAsync(_factory, tenantStatus);
        using var client = _factory.CreateTenantClient(tenant.TenantCode);

        var response = await client.GetAsync("/health");
        var body = await response.Content.ReadAsStringAsync();

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        body.Should().Contain("is not active");
    }
}