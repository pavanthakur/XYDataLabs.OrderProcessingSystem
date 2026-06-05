using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.Features.Webhooks;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Webhooks;

/// <summary>
/// Handles payment.captured events from any provider.
/// Transitions the matching PaymentAttempt to Succeeded via optimistic concurrency (RowVersion).
/// Idempotent: if Status is already Succeeded, exits cleanly.
/// </summary>
internal sealed class PaymentCapturedHandler : IWebhookEventHandler
{
    public string EventType => "payment.captured";

    private readonly IAppDbContext _context;
    private readonly ILogger<PaymentCapturedHandler> _logger;
    private static readonly JsonSerializerOptions JsonOpts = new(JsonSerializerDefaults.Web);

    public PaymentCapturedHandler(IAppDbContext context, ILogger<PaymentCapturedHandler> logger)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(logger);
        _context = context;
        _logger = logger;
    }

    public async Task HandleAsync(string providerName, string rawPayload, int tenantId, CancellationToken cancellationToken)
    {
        // Extract the provider reference id from the payload.
        // Providers use different field names — check common ones.
        string? providerReferenceId = null;
        try
        {
            using var doc = JsonDocument.Parse(rawPayload);
            var root = doc.RootElement;
            providerReferenceId =
                TryGetString(root, "payment_id") ??
                TryGetString(root, "id") ??
                TryGetString(root, "transaction_id");
        }
        catch (JsonException ex)
        {
            _logger.LogError(ex,
                "Failed to parse payment.captured payload. Provider={Provider} TenantId={TenantId}",
                providerName, tenantId);
            return;
        }

        if (string.IsNullOrWhiteSpace(providerReferenceId))
        {
            _logger.LogWarning(
                "payment.captured payload has no recognisable provider reference id. Provider={Provider} TenantId={TenantId}",
                providerName, tenantId);
            return;
        }

        var attempt = await _context.PaymentAttempts
            .FirstOrDefaultAsync(
                a => a.TenantId == tenantId && a.ProviderReferenceId == providerReferenceId,
                cancellationToken);

        if (attempt is null)
        {
            _logger.LogWarning(
                "No PaymentAttempt found for payment.captured. Provider={Provider} ProviderReferenceId={RefId} TenantId={TenantId}",
                providerName, providerReferenceId, tenantId);
            return;
        }

        // Idempotency: already succeeded — nothing to do.
        if (attempt.Status == PaymentAttemptStatus.Succeeded)
        {
            _logger.LogInformation(
                "payment.captured: PaymentAttempt {AttemptId} already Succeeded — skipping. TenantId={TenantId}",
                attempt.Id, tenantId);
            return;
        }

        // MarkAsSucceeded sets Status + ProviderStatus and raises PaymentAttemptSucceededDomainEvent.
        // DbContext.SaveChangesAsync harvests the domain event and writes an OutboxMessage atomically (Outbox bridge).
        // RowVersion on PaymentAttempt provides optimistic concurrency (DW-002).
        // DbUpdateConcurrencyException is caught by the worker and the message retried.
        attempt.MarkAsSucceeded(providerName);
        await _context.SaveChangesAsync(cancellationToken);

        _logger.LogInformation(
            "payment.captured: PaymentAttempt {AttemptId} transitioned to Succeeded. Provider={Provider} TenantId={TenantId}",
            attempt.Id, providerName, tenantId);
    }

    private static string? TryGetString(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var prop) && prop.ValueKind == JsonValueKind.String
            ? prop.GetString()
            : null;
}
