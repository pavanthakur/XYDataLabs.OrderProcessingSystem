using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Gateway.Tests.Infrastructure;

namespace XYDataLabs.OrderProcessingSystem.Gateway.Tests;

public sealed class GatewayBehaviorTests : IAsyncLifetime
{
    private DownstreamStubServer _ordersStub = null!;
    private DownstreamStubServer _uiStub = null!;
    private GatewayWebApplicationFactory _factory = null!;

    public async Task InitializeAsync()
    {
        _ordersStub = await DownstreamStubServer.StartAsync();
        _uiStub = await DownstreamStubServer.StartAsync();
        _factory = new GatewayWebApplicationFactory(_ordersStub.BaseAddress, _uiStub.BaseAddress);
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
        await _ordersStub.DisposeAsync();
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
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/ping");
        request.Headers.Host = "orders.localhost";

        var response = await client.SendAsync(request);
        var payload = await response.Content.ReadFromJsonAsync<DownstreamResponse>();

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Headers.TryGetValues("X-Correlation-Id", out var correlationHeaderValues).Should().BeTrue();
        var correlationId = correlationHeaderValues!.Single();
        payload.Should().NotBeNull();
        payload!.Path.Should().Be("/api/ping");
        payload.CorrelationId.Should().Be(correlationId);
    }

    private sealed record ProblemDetailsContract(string? Title, string? Detail);

    private sealed record DownstreamResponse(string? Path, string? Method, string? CorrelationId);
}