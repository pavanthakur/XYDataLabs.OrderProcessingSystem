namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public enum ServiceBusConsumerMessageDisposition
{
    Complete,
    DeadLetter,
    Abandon
}

public sealed record ServiceBusConsumerMessageProcessingResult(
    ServiceBusConsumerMessageDisposition Disposition,
    string ConsumerKind,
    string BrokerMessageId,
    Guid? EnvelopeMessageId = null,
    int? TenantId = null,
    string? EventType = null,
    string? CorrelationId = null,
    bool Duplicate = false,
    string? DeadLetterReason = null,
    string? DeadLetterDescription = null);
