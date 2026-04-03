using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;
using XYDataLabs.OrderProcessingSystem.UI.Controllers;
using XYDataLabs.OrderProcessingSystem.UI.Models;

namespace XYDataLabs.OrderProcessingSystem.UI.Tests.Controllers;

public class HomeControllerTelemetryTests
{
    [Fact]
    public void LogPaymentClientEvent_ReturnsBadRequest_WhenRequestIsMissing()
    {
        using var controller = CreateController(out _);

        var result = controller.LogPaymentClientEvent(null);

        Assert.IsType<BadRequestResult>(result);
    }

    [Fact]
    public void LogPaymentClientEvent_ReturnsValidationProblem_WhenModelStateIsInvalid()
    {
        using var controller = CreateController(out _);
        controller.ModelState.AddModelError(nameof(PaymentClientEventRequest.EventName), "Required");

        var result = controller.LogPaymentClientEvent(new PaymentClientEventRequest
        {
            EventName = "ui_payment_submit_started"
        });

        var objectResult = Assert.IsType<ObjectResult>(result);
        var problem = Assert.IsType<ValidationProblemDetails>(objectResult.Value);
        Assert.True(problem.Errors.ContainsKey(nameof(PaymentClientEventRequest.EventName)));
    }

    [Theory]
    [InlineData(null, LogLevel.Information)]
    [InlineData("warning", LogLevel.Warning)]
    [InlineData("error", LogLevel.Error)]
    public void LogPaymentClientEvent_ReturnsNoContent_AndLogsExpectedSeverity(string? severity, LogLevel expectedLevel)
    {
        using var controller = CreateController(out var logger);

        var result = controller.LogPaymentClientEvent(new PaymentClientEventRequest
        {
            EventName = "ui_payment_submit_started",
            Severity = severity,
            TenantCode = "TenantA",
            ClientFlowId = "flow-123",
            CustomerOrderId = "OR-1-2ndApr-A",
            AttemptOrderId = "OR-1-2ndApr-A-ATTEMPT",
            PaymentId = "payment-123",
            PaymentStatus = "pending",
            StatusCategory = "started",
            HttpStatus = StatusCodes.Status202Accepted,
            PagePath = "/",
            ClientTimestampUtc = "2026-04-02T12:34:56Z"
        });

        Assert.IsType<NoContentResult>(result);

        var entry = Assert.Single(logger.Entries);
        Assert.Equal(expectedLevel, entry.Level);
        Assert.Contains("UI payment event ui_payment_submit_started", entry.Message, StringComparison.Ordinal);
        Assert.Contains("TenantA", entry.Message, StringComparison.Ordinal);
        Assert.Contains("flow-123", entry.Message, StringComparison.Ordinal);
    }

    private static HomeController CreateController(out TestLogger<HomeController> logger)
    {
        logger = new TestLogger<HomeController>();

        var controller = new HomeController(
            logger,
            Options.Create(new TenantConfigurationOptions()));

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