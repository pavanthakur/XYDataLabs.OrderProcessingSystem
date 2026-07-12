using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Gateway.Tests.Infrastructure;

namespace XYDataLabs.OrderProcessingSystem.Gateway.Tests;

[Collection("GatewayBehavior")]
public sealed class GatewayBehaviorTests : IAsyncLifetime
{
    private DownstreamStubServer _ordersStub = null!;
    private DownstreamStubServer _inventoryStub = null!;
    private DownstreamStubServer _notificationsStub = null!;
    private DownstreamStubServer _uiStub = null!;
    private GatewayWebApplicationFactory _factory = null!;

    public async Task InitializeAsync()
    {
        _ordersStub = await DownstreamStubServer.StartAsync();
        _inventoryStub = await DownstreamStubServer.StartAsync();
        _notificationsStub = await DownstreamStubServer.StartAsync();
        _uiStub = await DownstreamStubServer.StartAsync();
        _factory = new GatewayWebApplicationFactory(
            _ordersStub.BaseAddress,
            _inventoryStub.BaseAddress,
            _notificationsStub.BaseAddress,
            _uiStub.BaseAddress);
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
        await _ordersStub.DisposeAsync();
        await _inventoryStub.DisposeAsync();
        await _notificationsStub.DisposeAsync();
        await _uiStub.DisposeAsync();
    }

    [Fact]
    public async Task HealthAlive_ReturnsOk()
    {
        using var client = _factory.CreateClient();

        var response = await client.GetAsync("/health/alive");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task GatewayRoot_WithAzureContainerAppsHost_ReturnsAcceptedHostSummary()
    {
        using var client = _factory.CreateClient();
        using var request = new HttpRequestMessage(HttpMethod.Get, "/");
        request.Headers.Host = "orderprocessing-gate-dev.bluebay-335bed8c.centralindia.azurecontainerapps.io";

        var response = await client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        body.Should().Contain("acceptedHost");
        body.Should().Contain("summary");
        body.Should().Contain("orderprocessing-gate-dev.bluebay-335bed8c.centralindia.azurecontainerapps.io");
    }

    [Fact]
    public async Task Request_WithUnsupportedHost_ReturnsProblemDetailsBadRequest()
    {
        using var client = _factory.CreateClient();
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/ping");
        request.Headers.Host = "evil.localhost";

        var response = await client.SendAsync(request);
        var payload = await response.Content.ReadFromJsonAsync<ProblemDetailsContract>();

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        payload.Should().NotBeNull();
        payload!.Title.Should().Be("Unsupported gateway host.");
        payload.Detail.Should().Contain("evil.localhost");
    }

    [Fact]
    public async Task Request_WithAzureContainerAppsHost_AllowsGatewayRequest()
    {
        using var client = _factory.CreateClient();
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/ping");
        request.Headers.Host = "orderprocessing-gate-dev.bluebay-335bed8c.centralindia.azurecontainerapps.io";

        var response = await client.SendAsync(request);

        response.StatusCode.Should().BeOneOf(HttpStatusCode.OK, HttpStatusCode.BadGateway);
        response.StatusCode.Should().NotBe(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Request_WithInternalGatewayServiceHost_AllowsUiProxyRequest()
    {
        using var client = _factory.CreateClient();
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/ping");
        request.Headers.Host = "orderprocessing-gate-local";

        var response = await client.SendAsync(request);

        response.StatusCode.Should().BeOneOf(HttpStatusCode.OK, HttpStatusCode.BadGateway);
        response.StatusCode.Should().NotBe(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Request_ExceedingConfiguredPayloadLimit_ReturnsPayloadTooLarge()
    {
        using var client = _factory.CreateClient();
        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/ping")
        {
            Content = new ByteArrayContent(new byte[1048577])
        };
        request.Headers.Host = "localhost";

        var response = await client.SendAsync(request);
        var payload = await response.Content.ReadFromJsonAsync<ProblemDetailsContract>();

        response.StatusCode.Should().Be(HttpStatusCode.RequestEntityTooLarge);
        payload.Should().NotBeNull();
        payload!.Title.Should().Be("Request payload too large.");
    }

    [Fact]
    public async Task HostBasedRoute_ProxiesToOrdersCluster_AndPropagatesCorrelationId()
    {
        using var client = _factory.CreateClient();

        var response = await SendWithRetryAsync(client, CreateOrdersRequest);
        var body = await response.Content.ReadAsStringAsync();

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Headers.TryGetValues("X-Correlation-Id", out var correlationHeaderValues).Should().BeTrue();
        var correlationId = correlationHeaderValues!.Single();
        body.Should().NotBeNullOrWhiteSpace();
        body.Should().Contain(correlationId);
    }

    [Fact]
    public async Task HostBasedRoute_ProxiesToUiCluster()
    {
        using var client = _factory.CreateClient();

        var response = await SendWithRetryAsync(client, CreateUiRequest);
        var body = await response.Content.ReadAsStringAsync();

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        body.Should().Contain("/ping");
        body.Should().Contain("GET");
    }

    [Fact]
    public async Task HostBasedRoute_ProxiesToInventoryCluster()
    {
        using var client = _factory.CreateClient();
        var response = await SendWithRetryAsync(client, CreateInventoryRequest);
        var body = await response.Content.ReadAsStringAsync();

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        body.Should().Contain("/ping");
        body.Should().Contain("GET");
    }

    [Fact]
    public async Task HostBasedRoute_ProxiesToNotificationsCluster()
    {
        using var client = _factory.CreateClient();
        var response = await SendWithRetryAsync(client, CreateNotificationsRequest);
        var body = await response.Content.ReadAsStringAsync();

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        body.Should().Contain("/ping");
        body.Should().Contain("GET");
    }

    private sealed record ProblemDetailsContract(string? Title, string? Detail);

    private static async Task<HttpResponseMessage> SendWithRetryAsync(
        HttpClient client,
        Func<HttpRequestMessage> requestFactory)
    {
        HttpResponseMessage? lastResponse = null;

        const int maxAttempts = 5;

        for (var attempt = 0; attempt < maxAttempts; attempt++)
        {
            using var request = requestFactory();
            lastResponse = await client.SendAsync(request);

            if (lastResponse.StatusCode != HttpStatusCode.BadGateway)
            {
                return lastResponse;
            }

            if (attempt < maxAttempts - 1)
            {
                lastResponse.Dispose();
            }

            await Task.Delay(100);
        }

        return lastResponse ?? throw new InvalidOperationException("Request could not be sent.");
    }

    private static HttpRequestMessage CreateUiRequest()
    {
        var request = new HttpRequestMessage(HttpMethod.Get, "/app/ping")
        {
            Version = HttpVersion.Version11
        };

        request.Headers.Host = "ui.localhost";

        return request;
    }

    private static HttpRequestMessage CreateOrdersRequest()
    {
        var request = new HttpRequestMessage(HttpMethod.Get, "/api/ping")
        {
            Version = HttpVersion.Version11
        };

        request.Headers.Host = "orders.localhost";

        return request;
    }

    private static HttpRequestMessage CreateInventoryRequest()
    {
        var request = new HttpRequestMessage(HttpMethod.Get, "/inventory/ping")
        {
            Version = HttpVersion.Version11
        };

        request.Headers.Host = "inventory.localhost";

        return request;
    }

    private static HttpRequestMessage CreateNotificationsRequest()
    {
        var request = new HttpRequestMessage(HttpMethod.Get, "/notifications/ping")
        {
            Version = HttpVersion.Version11
        };

        request.Headers.Host = "notifications.localhost";

        return request;
    }
}

[CollectionDefinition("GatewayBehavior", DisableParallelization = true)]
public sealed class GatewayBehaviorCollection;
