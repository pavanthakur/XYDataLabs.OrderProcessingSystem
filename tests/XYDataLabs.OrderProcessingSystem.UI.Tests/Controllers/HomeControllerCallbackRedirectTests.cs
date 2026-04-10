using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.UI.Controllers;

namespace XYDataLabs.OrderProcessingSystem.UI.Tests.Controllers;

public sealed class HomeControllerCallbackRedirectTests
{
    [Fact]
    public void Index_RedirectsToConfiguredFrontendPaymentRoute()
    {
        using var controller = CreateController(
            new Dictionary<string, string?>(StringComparer.Ordinal)
            {
                ["Frontend:WebBaseUrl"] = "http://localhost:5173"
            },
            out var logger);

        controller.ControllerContext.HttpContext.Request.QueryString = new QueryString("?tenantCode=TenantA");

        var result = controller.Index();

        result.Should().BeOfType<RedirectResult>()
            .Which.Url.Should().Be("http://localhost:5173/payments/new?tenantCode=TenantA");
        logger.Entries.Should().ContainSingle(entry =>
            entry.Level == LogLevel.Information
            && entry.Message.Contains("Legacy UI payment entry requested", StringComparison.Ordinal)
            && entry.Message.Contains("http://localhost:5173/payments/new?tenantCode=TenantA", StringComparison.Ordinal));
    }

    [Fact]
    public void Index_FallsBackToCurrentRequestHost_WhenFrontendBaseUrlMissing()
    {
        using var controller = CreateController(new Dictionary<string, string?>(StringComparer.Ordinal), out _);
        controller.ControllerContext.HttpContext.Request.Scheme = "https";
        controller.ControllerContext.HttpContext.Request.Host = new HostString("legacy-ui.example.com");

        var result = controller.Index();

        result.Should().BeOfType<RedirectResult>()
            .Which.Url.Should().Be("https://legacy-ui.example.com/payments/new");
    }

    [Fact]
    public void PaymentCallback_RedirectsToConfiguredFrontendBaseUrl()
    {
        using var controller = CreateController(
            new Dictionary<string, string?>(StringComparer.Ordinal)
            {
                ["Frontend:WebBaseUrl"] = "http://localhost:5173"
            },
            out var logger);

        controller.ControllerContext.HttpContext.Request.QueryString = new QueryString("?id=pay_123&tenantCode=TenantA");

        var result = controller.PaymentCallback();

        result.Should().BeOfType<RedirectResult>()
            .Which.Url.Should().Be("http://localhost:5173/payments/callback?id=pay_123&tenantCode=TenantA");
        logger.Entries.Should().ContainSingle(entry =>
            entry.Level == LogLevel.Information
            && entry.Message.Contains("Legacy UI payment callback received", StringComparison.Ordinal)
            && entry.Message.Contains("http://localhost:5173/payments/callback?id=pay_123&tenantCode=TenantA", StringComparison.Ordinal));
    }

    [Fact]
    public void PaymentCallback_FallsBackToCurrentRequestHost_WhenFrontendBaseUrlMissing()
    {
        using var controller = CreateController(new Dictionary<string, string?>(StringComparer.Ordinal), out _);
        controller.ControllerContext.HttpContext.Request.Scheme = "https";
        controller.ControllerContext.HttpContext.Request.Host = new HostString("legacy-ui.example.com");
        controller.ControllerContext.HttpContext.Request.QueryString = new QueryString("?id=pay_456&status=completed");

        var result = controller.PaymentCallback();

        result.Should().BeOfType<RedirectResult>()
            .Which.Url.Should().Be("https://legacy-ui.example.com/payments/callback?id=pay_456&status=completed");
    }

    private static HomeController CreateController(
        IDictionary<string, string?> configurationValues,
        out TestLogger<HomeController> logger)
    {
        logger = new TestLogger<HomeController>();
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(configurationValues)
            .Build();

        var controller = new HomeController(
            configuration,
            logger);

        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext()
        };

        return controller;
    }

    internal sealed class TestLogger<T> : ILogger<T>
    {
        public List<LogEntry> Entries { get; } = [];

        IDisposable ILogger.BeginScope<TState>(TState state)
        {
            return new NullScope();
        }

        bool ILogger.IsEnabled(LogLevel logLevel) => true;

        void ILogger.Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            Entries.Add(new LogEntry(logLevel, formatter(state, exception)));
        }

        internal sealed record LogEntry(LogLevel Level, string Message);

        private sealed class NullScope : IDisposable
        {
            public void Dispose()
            {
            }
        }
    }
}