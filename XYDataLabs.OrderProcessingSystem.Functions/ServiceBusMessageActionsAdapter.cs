using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;

namespace XYDataLabs.OrderProcessingSystem.Functions;

internal sealed class ServiceBusMessageActionsAdapter(
    ServiceBusReceivedMessage message,
    ServiceBusMessageActions messageActions) : IDlqReplayMessageActions, IDlqIntakeMessageActions
{
    public Task AbandonAsync(CancellationToken cancellationToken)
        => messageActions.AbandonMessageAsync(message, cancellationToken: cancellationToken);

    public Task DeadLetterAsync(string reason, string description, CancellationToken cancellationToken)
        => messageActions.DeadLetterMessageAsync(message, null, reason, description, cancellationToken);

    public Task CompleteAsync(CancellationToken cancellationToken)
        => messageActions.CompleteMessageAsync(message, cancellationToken);
}
