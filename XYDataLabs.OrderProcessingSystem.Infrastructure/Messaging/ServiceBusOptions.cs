namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public sealed class ServiceBusOptions
{
    public const string SectionName = "ServiceBus";

    public bool Enabled { get; init; }

    public string ConnectionString { get; init; } = string.Empty;

    public string TopicName { get; init; } = "order-events";

    public string SubscriptionName { get; init; } = "order-created";

    public string DeadLetterTopicName { get; init; } = "order-events-dlq";

    public string DeadLetterSubscriptionName { get; init; } = "dlq-replay";

    public int MaxDeliveryCount { get; init; } = 10;

    public int MaxReplayAttempts { get; init; } = 5;

    public int ReplayBatchSize { get; init; } = 10;

    public TimeSpan MessageTtl { get; init; } = TimeSpan.FromDays(7);

    public bool ForwardDeadLetteredMessagesToDlqTopic { get; init; } = true;

    public bool ReplayEnabled { get; init; }
}
