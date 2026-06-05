namespace XYDataLabs.OrderProcessingSystem.Application.Features.Webhooks;

/// <summary>
/// Processes a single Inbox event and applies domain state transitions.
/// Implementations are registered per EventType string and invoked by the InboxProcessorWorker.
/// </summary>
public interface IWebhookEventHandler
{
    /// <summary>The EventType string this handler is responsible for (e.g. "payment.captured").</summary>
    string EventType { get; }

    /// <summary>
    /// Handles the event payload. Called with the raw JSON payload from the InboxMessage.
    /// Must be idempotent — may be called more than once if processing fails mid-way.
    /// </summary>
    Task HandleAsync(string providerName, string rawPayload, int tenantId, CancellationToken cancellationToken);
}
