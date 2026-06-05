using Asp.Versioning;
using Microsoft.AspNetCore.Mvc;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.Features.Webhooks.Commands;

namespace XYDataLabs.OrderProcessingSystem.API.Controllers;

/// <summary>
/// Receives provider webhook events. Each supported provider posts to /api/v1/webhook/{providerName}.
/// Security contract: HMAC signature is validated against the raw body before any business processing.
/// The event is durably persisted to the Inbox and processed asynchronously — 202 is returned immediately.
/// </summary>
[ApiVersion("1.0")]
[ApiController]
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

    /// <summary>
    /// Receives and durably records a provider webhook event.
    /// POST /api/v1/webhook/{providerName}
    /// </summary>
    [HttpPost("{providerName}")]
    [Consumes("application/json")]
    public async Task<IActionResult> ReceiveAsync(string providerName, CancellationToken cancellationToken)
    {
        if (!SupportedProviders.Contains(providerName))
        {
            _logger.LogWarning("Webhook received for unsupported provider {ProviderName}", providerName);
            return BadRequest(new { error = $"Unsupported provider: {providerName}" });
        }

        // Buffer the request body so it can be read for HMAC validation and then again for recording.
        Request.EnableBuffering();

        string rawPayload;
        using (var reader = new StreamReader(Request.Body, leaveOpen: true))
        {
            rawPayload = await reader.ReadToEndAsync(cancellationToken);
        }

        // Reset stream position for any downstream middleware that may read the body again.
        Request.Body.Position = 0;

        // Validate HMAC signature BEFORE any business deserialization.
        // Header name is provider-specific; the validator resolves the correct header per provider.
        var signatureHeader = Request.Headers["X-Webhook-Signature"].FirstOrDefault()
                           ?? Request.Headers["X-Razorpay-Signature"].FirstOrDefault()
                           ?? Request.Headers["X-OpenPay-Signature"].FirstOrDefault();

        if (!_signatureValidator.Validate(providerName, rawPayload, signatureHeader))
        {
            // Log provider and timestamp but never the payload — it may contain PII.
            _logger.LogWarning(
                "Webhook signature validation failed. Provider={ProviderName} RequestId={RequestId}",
                providerName, HttpContext.TraceIdentifier);
            return Unauthorized(new { error = "Webhook signature validation failed." });
        }

        // Extract provider event identity from headers; fall back to a generated value.
        // The provider event ID is used for inbox deduplication.
        var providerEventId = Request.Headers["X-Provider-Event-Id"].FirstOrDefault()
                           ?? Request.Headers["X-Razorpay-Event-Id"].FirstOrDefault()
                           ?? Guid.NewGuid().ToString();

        var eventType = Request.Headers["X-Provider-Event-Type"].FirstOrDefault() ?? "unknown";

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
                providerName, result.Error);
            return StatusCode(StatusCodes.Status500InternalServerError, new { error = "Failed to record event." });
        }

        _logger.LogInformation(
            "Webhook event accepted. Provider={ProviderName} InboxMessageId={InboxMessageId}",
            providerName, result.Value);

        return Accepted(new { inboxMessageId = result.Value });
    }
}
