using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Webhooks.Commands;

/// <summary>
/// Durably records an inbound provider webhook event into the Inbox.
/// The payload has already been HMAC-validated by the controller before this command is dispatched.
/// Returns the persisted InboxMessage.Id for traceability.
/// </summary>
public sealed record RecordWebhookEventCommand(
    string ProviderName,
    string ProviderEventId,
    string EventType,
    string RawPayload,
    int SchemaVersion = 1) : ICommand<Result<int>>;
