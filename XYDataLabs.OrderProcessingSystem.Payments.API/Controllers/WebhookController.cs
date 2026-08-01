using System.Text.Json;
using Asp.Versioning;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.Features.Webhooks.Commands;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

namespace XYDataLabs.OrderProcessingSystem.Payments.API.Controllers;

[ApiVersion("1.0")]
[ApiController]
[AllowAnonymous]
[Route("api/v{version:apiVersion}/webhook")]
public sealed class WebhookController : ControllerBase
{
    private static readonly HashSet<string> SupportedProviders =
        new(StringComparer.OrdinalIgnoreCase) { "Razorpay", "OpenPay" };

    private readonly IDispatcher _dispatcher;
    private readonly IWebhookSignatureValidator _signatureValidator;
    private readonly ILogger<WebhookController> _logger;

    public WebhookController(
        IDispatcher dispatcher,
        IWebhookSignatureValidator signatureValidator,
        ILogger<WebhookController> logger)
    {
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentNullException.ThrowIfNull(signatureValidator);
        ArgumentNullException.ThrowIfNull(logger);

        _dispatcher = dispatcher;
        _signatureValidator = signatureValidator;
        _logger = logger;
    }

    [HttpPost("{providerName}")]
    [Consumes("application/json")]
    public async Task<IActionResult> ReceiveAsync(string providerName, CancellationToken cancellationToken)
    {
        if (!SupportedProviders.Contains(providerName))
        {
            _logger.LogWarning("Webhook received for unsupported provider {ProviderName}", providerName);
            return BadRequest(new { error = $"Unsupported provider: {providerName}" });
        }

        Request.EnableBuffering();

        string rawPayload;
        using (var reader = new StreamReader(Request.Body, leaveOpen: true))
        {
            rawPayload = await reader.ReadToEndAsync(cancellationToken);
        }

        Request.Body.Position = 0;

        var signatureHeader = providerName.Equals("Razorpay", StringComparison.OrdinalIgnoreCase)
            ? Request.Headers["X-Razorpay-Signature"].FirstOrDefault()
              ?? Request.Headers["X-Webhook-Signature"].FirstOrDefault()
            : Request.Headers["X-OpenPay-Signature"].FirstOrDefault()
              ?? Request.Headers["X-Webhook-Signature"].FirstOrDefault();

        if (!_signatureValidator.Validate(providerName, rawPayload, signatureHeader))
        {
            BusinessMetrics.RecordWebhookHmacFailure(providerName);
            _logger.LogWarning(
                "Webhook signature validation failed. Provider={ProviderName} RequestId={RequestId}",
                providerName,
                HttpContext.TraceIdentifier);
            return Unauthorized(new { error = "Webhook signature validation failed." });
        }

        var providerEventId = Request.Headers["X-Provider-Event-Id"].FirstOrDefault()
                              ?? Request.Headers["X-Razorpay-Event-Id"].FirstOrDefault()
                              ?? Guid.NewGuid().ToString();

        var eventType = Request.Headers["X-Provider-Event-Type"].FirstOrDefault()
                        ?? ExtractEventTypeFromPayload(rawPayload)
                        ?? "unknown";

        var command = new RecordWebhookEventCommand(
            ProviderName: providerName,
            ProviderEventId: providerEventId,
            EventType: eventType,
            RawPayload: rawPayload);

        var result = await _dispatcher.SendAsync(command, cancellationToken);

        if (!result.IsSuccess)
        {
            _logger.LogError(
                "Failed to record webhook event to Inbox. Provider={ProviderName} Error={Error}",
                providerName,
                result.Error);
            return StatusCode(StatusCodes.Status500InternalServerError, new { error = "Failed to record event." });
        }

        _logger.LogInformation(
            "Webhook event accepted. Provider={ProviderName} InboxMessageId={InboxMessageId}",
            providerName,
            result.Value);

        return Accepted(new { inboxMessageId = result.Value });
    }

    private static string? ExtractEventTypeFromPayload(string rawPayload)
    {
        if (string.IsNullOrWhiteSpace(rawPayload))
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(rawPayload);
            var root = document.RootElement;

            if (root.ValueKind != JsonValueKind.Object)
            {
                return null;
            }

            return TryGetNonEmptyString(root, "event")
                   ?? TryGetNonEmptyString(root, "type");
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string? TryGetNonEmptyString(JsonElement root, string propertyName)
    {
        return root.TryGetProperty(propertyName, out var property)
               && property.ValueKind == JsonValueKind.String
               && !string.IsNullOrWhiteSpace(property.GetString())
            ? property.GetString()
            : null;
    }
}
