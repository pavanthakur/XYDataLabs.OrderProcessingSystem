using System.Net;
using System.Net.Sockets;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Hosting;

namespace XYDataLabs.OrderProcessingSystem.Gateway.Tests.Infrastructure;

internal sealed class DownstreamStubServer : IAsyncDisposable
{
    private readonly WebApplication _app;

    private DownstreamStubServer(WebApplication app, Uri baseAddress)
    {
        _app = app;
        BaseAddress = baseAddress;
    }

    public Uri BaseAddress { get; }

    public static async Task<DownstreamStubServer> StartAsync()
    {
        var port = GetFreeTcpPort();
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.UseUrls($"http://127.0.0.1:{port}");

        var app = builder.Build();
        app.MapMethods("/api/ping", ["GET", "POST"], (HttpContext context) =>
        {
            return Results.Json(new
            {
                path = context.Request.Path.Value,
                method = context.Request.Method,
                correlationId = context.Request.Headers["X-Correlation-Id"].ToString()
            });
        });
        app.MapGet("/", () => Results.Ok(new { service = "downstream-stub" }));

        await app.StartAsync();

        return new DownstreamStubServer(app, new Uri($"http://127.0.0.1:{port}/"));
    }

    public async ValueTask DisposeAsync()
    {
        await _app.StopAsync();
        await _app.DisposeAsync();
    }

    private static int GetFreeTcpPort()
    {
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        return ((IPEndPoint)listener.LocalEndpoint).Port;
    }
}