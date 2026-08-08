namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public sealed class ServiceBusOptions
{
    public const string SectionName = "ServiceBus";

    public bool Enabled { get; init; }

    public string ConnectionString { get; init; } = string.Empty;

    public string TopicName { get; init; } = "order-events";

    public string SubscriptionName { get; init; } = "order-created";

    public string PaymentStateSubscriptionName { get; init; } = "orders-payment-state";

    public string DeadLetterTopicName { get; init; } = "order-events-dlq";

    public string DeadLetterSubscriptionName { get; init; } = "dlq-intake";

    public string ReplayRequestQueueName { get; init; } = "dlq-replay-requests";

    public int MaxDeliveryCount { get; init; } = 10;

    public int MaxReplayAttempts { get; init; } = 5;

    public int ReplayBatchSize { get; init; } = 10;

    public int MaxConcurrentMessages { get; init; } = 20;

    public TimeSpan MessageTtl { get; init; } = TimeSpan.FromDays(7);

    public bool ForwardDeadLetteredMessagesToDlqTopic { get; init; } = true;

    public bool ReplayEnabled { get; init; }
}
