using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.Features.Webhooks;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Webhooks;

/// <summary>
/// Handles payment.failed events from any provider.
/// Transitions the matching PaymentAttempt to Failed via optimistic concurrency (RowVersion).
/// Raises PaymentAttemptFailedDomainEvent — DbContext writes an OutboxMessage atomically (Outbox bridge).
/// Idempotent: if Status is already Failed, exits cleanly.
/// </summary>
internal sealed class PaymentFailedHandler : IWebhookEventHandler
{
    public string EventType => "payment.failed";

    private readonly IAppDbContext _context;
    private readonly ILogger<PaymentFailedHandler> _logger;

    public PaymentFailedHandler(IAppDbContext context, ILogger<PaymentFailedHandler> logger)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(logger);
        _context = context;
        _logger = logger;
    }

    public async Task HandleAsync(string providerName, string rawPayload, int tenantId, CancellationToken cancellationToken)
    {
        string? providerReferenceId = null;
        string? errorReason = null;
        try
        {
            using var doc = JsonDocument.Parse(rawPayload);
            var root = doc.RootElement;
            providerReferenceId =
                TryGetString(root, "payment_id") ??
                TryGetString(root, "id") ??
                TryGetString(root, "transaction_id");
            errorReason =
                TryGetString(root, "description") ??
                TryGetString(root, "error_description") ??
                TryGetString(root, "reason");
        }
        catch (JsonException ex)
        {
            _logger.LogError(ex,
                "Failed to parse payment.failed payload. Provider={Provider} TenantId={TenantId}",
                providerName, tenantId);
            return;
        }

        if (string.IsNullOrWhiteSpace(providerReferenceId))
        {
            _logger.LogWarning(
                "payment.failed payload has no recognisable provider reference id. Provider={Provider} TenantId={TenantId}",
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
                "No PaymentAttempt found for payment.failed. Provider={Provider} ProviderReferenceId={RefId} TenantId={TenantId}",
                providerName, providerReferenceId, tenantId);
            return;
        }

        // Idempotency: already failed — nothing to do.
        if (attempt.Status == PaymentAttemptStatus.Failed)
        {
            _logger.LogInformation(
                "payment.failed: PaymentAttempt {AttemptId} already Failed — skipping. TenantId={TenantId}",
                attempt.Id, tenantId);
            return;
        }

        // MarkAsFailed sets Status + ProviderStatus + LastErrorMessage and raises PaymentAttemptFailedDomainEvent.
        // DbContext.SaveChangesAsync harvests the domain event and writes an OutboxMessage atomically (Outbox bridge).
        // RowVersion on PaymentAttempt provides optimistic concurrency (DW-002).
        // DbUpdateConcurrencyException is caught by the worker and the message retried.
        attempt.MarkAsFailed(providerName, errorReason);
        await _context.SaveChangesAsync(cancellationToken);

        _logger.LogInformation(
            "payment.failed: PaymentAttempt {AttemptId} transitioned to Failed. Provider={Provider} TenantId={TenantId} Reason={Reason}",
            attempt.Id, providerName, tenantId, errorReason);
    }

    private static string? TryGetString(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var prop) && prop.ValueKind == JsonValueKind.String
            ? prop.GetString()
            : null;
}
