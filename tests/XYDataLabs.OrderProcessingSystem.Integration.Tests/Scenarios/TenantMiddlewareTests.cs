using System.Net;
using System.Text.Json;
using FluentAssertions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
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

    [Theory]
    [InlineData("/health", HttpStatusCode.OK)]
    [InlineData("/health/live", HttpStatusCode.OK)]
    [InlineData("/health/ready", HttpStatusCode.OK)]
    public async Task HealthChecks_WithoutTenantHeader_ReturnExpectedStatus(string path, HttpStatusCode expectedStatus)
    {
        using var client = _factory.CreateClient();

        var response = await client.GetAsync(path);

        response.StatusCode.Should().Be(expectedStatus);
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
    public async Task TenantProtectedEndpoint_WithUnknownTenantCode_ReturnsBadRequest()
    {
        using var client = _factory.CreateTenantClient($"UNKNOWN-{Guid.NewGuid():N}"[..18]);

        var response = await client.GetAsync("/api/v1/Customer/GetAllCustomers");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        body.RootElement.GetProperty("title").GetString().Should().Be("Tenant code is not recognized.");
        body.RootElement.GetProperty("detail").GetString().Should().Contain("is not recognized");
    }

    [Fact]
    public async Task ReadyHealthCheck_WithDegradedReadyDependency_ReturnsServiceUnavailable()
    {
        await using var degradedFactory = new DegradedReadinessIntegrationTestFactory(_fixture.ConnectionString);
        var tenant = await IntegrationTestData.CreateTenantAsync(degradedFactory);
        using var client = degradedFactory.CreateTenantClient(tenant.TenantCode);

        var response = await client.GetAsync("/health/ready");

        response.StatusCode.Should().Be(HttpStatusCode.ServiceUnavailable);
    }

    [Theory]
    [InlineData("Suspended")]
    [InlineData("Decommissioned")]
    public async Task TenantProtectedEndpoint_WithBlockedTenantStatus_ReturnsForbidden(string tenantStatus)
    {
        var tenant = await IntegrationTestData.CreateTenantAsync(_factory, tenantStatus);
        using var client = _factory.CreateTenantClient(tenant.TenantCode);

        var response = await client.GetAsync("/api/v1/Customer/GetAllCustomers");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        body.RootElement.GetProperty("title").GetString().Should().Be("Tenant is not active.");
        body.RootElement.GetProperty("detail").GetString().Should().Contain("is not active");
    }
}

internal sealed class DegradedReadinessIntegrationTestFactory(string connectionString)
    : IntegrationTestWebAppFactory(connectionString)
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        base.ConfigureWebHost(builder);

        builder.ConfigureServices(services =>
        {
            services.AddHealthChecks()
                .AddCheck(
                    "synthetic-degraded-ready-check",
                    () => HealthCheckResult.Degraded("Synthetic degraded dependency for readiness probe verification."),
                    tags: new[] { "ready" });
        });
    }
}