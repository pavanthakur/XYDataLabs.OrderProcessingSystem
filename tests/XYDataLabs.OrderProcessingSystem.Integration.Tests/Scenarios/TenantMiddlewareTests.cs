using System.Net;
using System.Text.Json;
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
    public async Task RuntimeConfiguration_ReturnsDbTenants_AndHonorsSelectedTenantHeader()
    {
        var tenantA = await IntegrationTestData.CreateTenantAsync(_factory);
        var tenantB = await IntegrationTestData.CreateTenantAsync(_factory);

        using var bootstrapClient = _factory.CreateClient();
        using var headerSelectedClient = _factory.CreateTenantClient(tenantB.TenantCode);

        var bootstrapResponse = await bootstrapClient.GetAsync("/api/v1/info/runtime-configuration");
        var headerSelectedResponse = await headerSelectedClient.GetAsync("/api/v1/info/runtime-configuration");

        bootstrapResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        headerSelectedResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        using var bootstrapDocument = JsonDocument.Parse(await bootstrapResponse.Content.ReadAsStringAsync());
        using var headerSelectedDocument = JsonDocument.Parse(await headerSelectedResponse.Content.ReadAsStringAsync());

        var bootstrapRoot = bootstrapDocument.RootElement;
        var headerSelectedRoot = headerSelectedDocument.RootElement;

        bootstrapRoot.GetProperty("tenantHeaderName").GetString().Should().Be(IntegrationTestWebAppFactory.TenantHeaderName);
        bootstrapRoot.GetProperty("configuredActiveTenantCode").GetString().Should().NotBeNullOrWhiteSpace();

        var availableTenants = bootstrapRoot.GetProperty("availableTenants").EnumerateArray().ToList();
        availableTenants.Should().HaveCountGreaterOrEqualTo(2);
        availableTenants.Select(tenant => tenant.GetProperty("tenantCode").GetString())
            .Should().Contain([tenantA.TenantCode, tenantB.TenantCode]);

        headerSelectedRoot.GetProperty("availableTenants").EnumerateArray()
            .Select(tenant => tenant.GetProperty("tenantCode").GetString())
            .Should().Contain([tenantA.TenantCode, tenantB.TenantCode]);

        headerSelectedRoot.GetProperty("activeTenantCode").GetString().Should().Be(tenantB.TenantCode);
        bootstrapRoot.GetProperty("activeTenantCode").GetString().Should().NotBeNullOrWhiteSpace();
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