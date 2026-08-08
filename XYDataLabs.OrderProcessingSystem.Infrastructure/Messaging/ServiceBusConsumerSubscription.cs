using XYDataLabs.OrderProcessingSystem.Orders.Contracts.Events;
using XYDataLabs.OrderProcessingSystem.Payments.Contracts.Events;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public sealed record ServiceBusConsumerSubscription(
    string ConsumerKind,
    string SubscriptionName,
    IReadOnlyDictionary<string, Type> EventPayloadTypes)
{
    public static ServiceBusConsumerSubscription ForInventory(string subscriptionName)
        => new(
            ConsumerKind: "Inventory",
            SubscriptionName: subscriptionName,
            EventPayloadTypes: new Dictionary<string, Type>(StringComparer.Ordinal)
            {
                [nameof(OrderCreatedV1)] = typeof(OrderCreatedV1)
            });

    public static ServiceBusConsumerSubscription ForNotifications(string subscriptionName)
        => new(
            ConsumerKind: "Notifications",
            SubscriptionName: subscriptionName,
            EventPayloadTypes: new Dictionary<string, Type>(StringComparer.Ordinal)
            {
                [nameof(OrderCreatedV1)] = typeof(OrderCreatedV1)
            });

    public static ServiceBusConsumerSubscription ForOrdersPaymentState(string subscriptionName)
        => new(
            ConsumerKind: "Orders",
            SubscriptionName: subscriptionName,
            EventPayloadTypes: new Dictionary<string, Type>(StringComparer.Ordinal)
            {
                [nameof(PaymentAttemptSucceededV1)] = typeof(PaymentAttemptSucceededV1),
                [nameof(PaymentAttemptFailedV1)] = typeof(PaymentAttemptFailedV1)
            });
}
