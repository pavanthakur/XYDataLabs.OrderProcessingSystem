using Azure.Messaging.ServiceBus;
using Azure.Core;
using XYDataLabs.OrderProcessingSystem.Functions;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

// Test assembly only. The provisioner must independently verify ownership, isolation and RBAC.
internal sealed class ReplayDrillTarget(
    string environment,
    string fullyQualifiedNamespace,
    string businessTopic,
    string normalRequestQueue,
    string requestQueue,
    Guid runId,
    Guid quarantineId,
    Guid requestId)
{
    internal string FullyQualifiedNamespace { get; } = fullyQualifiedNamespace;
    internal string BusinessTopic { get; } = businessTopic;
    internal string NormalRequestQueue { get; } = normalRequestQueue;
    internal string RequestQueue { get; } = requestQueue;
    internal Guid RunId { get; } = runId;
    internal Guid QuarantineId { get; } = quarantineId;
    internal Guid RequestId { get; } = requestId;

    internal ServiceBusClient CreateClient(TokenCredential credential)
    {
        ArgumentNullException.ThrowIfNull(credential);
        ValidateEndpoint(FullyQualifiedNamespace, RequestQueue, RequestQueue);
        return new ServiceBusClient(FullyQualifiedNamespace, credential);
    }

    internal ServiceBusSender CreateBusinessTopicSender(ServiceBusClient client)
    {
        ValidateClient(client);
        return client.CreateSender(BusinessTopic);
    }

    internal ServiceBusReceiver CreateRequestReceiver(ServiceBusClient client)
    {
        ValidateClient(client);
        return client.CreateReceiver(RequestQueue, new ServiceBusReceiverOptions
        {
            ReceiveMode = ServiceBusReceiveMode.PeekLock
        });
    }

    internal void ValidateEndpoint(string actualNamespace, string entity, string expectedEntity)
    {
        if (!string.Equals(environment, "dev", StringComparison.Ordinal) ||
            string.IsNullOrWhiteSpace(FullyQualifiedNamespace) ||
            string.IsNullOrWhiteSpace(BusinessTopic) ||
            string.IsNullOrWhiteSpace(NormalRequestQueue) ||
            string.IsNullOrWhiteSpace(RequestQueue) ||
            string.Equals(NormalRequestQueue, RequestQueue, StringComparison.Ordinal) ||
            RunId == Guid.Empty || QuarantineId == Guid.Empty || RequestId == Guid.Empty ||
            !string.Equals(actualNamespace, FullyQualifiedNamespace, StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(entity, expectedEntity, StringComparison.Ordinal))
        {
            throw new InvalidOperationException("Replay drill refused a non-isolated broker endpoint.");
        }
    }

    internal void ValidateFixture(IReadOnlyDictionary<string, object> properties)
    {
        if (!Matches(properties, "QuarantineId", QuarantineId) || !Matches(properties, "ReplayRequestId", RequestId))
        {
            throw new InvalidOperationException("Replay drill refused a foreign fixture.");
        }
    }

    private static bool Matches(IReadOnlyDictionary<string, object> properties, string key, Guid expected) =>
        properties.TryGetValue(key, out var value) && Guid.TryParse(value as string, out var actual) && actual == expected;

    private void ValidateClient(ServiceBusClient client)
    {
        ArgumentNullException.ThrowIfNull(client);
        ValidateEndpoint(client.FullyQualifiedNamespace, RequestQueue, RequestQueue);
    }
}

internal sealed class ReplayDrillPublisher : IDlqReplayPublisher
{
    private readonly ReplayDrillTarget _target;
    private readonly ServiceBusSender _sender;
    private readonly bool _failAfterAcceptedSend;
    private int _faultInjected;
    private readonly List<string> _publishedTransportMessageIds = [];
    private readonly List<string> _publishedEnvelopeMessageIds = [];

    internal ReplayDrillPublisher(ReplayDrillTarget target, ServiceBusSender sender, bool failAfterAcceptedSend)
    {
        target.ValidateEndpoint(sender.FullyQualifiedNamespace, sender.EntityPath, target.BusinessTopic);
        _target = target;
        _sender = sender;
        _failAfterAcceptedSend = failAfterAcceptedSend;
    }

    internal IReadOnlyList<string> PublishedTransportMessageIds => _publishedTransportMessageIds;
    internal IReadOnlyList<string> PublishedEnvelopeMessageIds => _publishedEnvelopeMessageIds;

    public async Task PublishAsync(ServiceBusMessage message, CancellationToken cancellationToken)
    {
        _target.ValidateFixture(new Dictionary<string, object>(message.ApplicationProperties));
        var envelopeMessageId = message.ApplicationProperties.TryGetValue("EnvelopeMessageId", out var envelopeId)
            ? Convert.ToString(envelopeId)
            : null;
        if (string.IsNullOrWhiteSpace(envelopeMessageId))
        {
            throw new InvalidOperationException("Replay drill requires the stable business EnvelopeMessageId.");
        }

        // The normal topic has broker duplicate detection enabled. Give the
        // second attempt a distinct broker ID so it reaches the real consumers;
        // the stable EnvelopeMessageId remains unchanged and exercises their
        // SQL inbox idempotency rather than broker-side suppression.
        if (_failAfterAcceptedSend && _publishedTransportMessageIds.Count > 0)
        {
            message.MessageId = Guid.NewGuid().ToString("D");
        }

        await _sender.SendMessageAsync(message, cancellationToken);
        _publishedTransportMessageIds.Add(message.MessageId);
        _publishedEnvelopeMessageIds.Add(envelopeMessageId);
        if (_failAfterAcceptedSend && Interlocked.Exchange(ref _faultInjected, 1) == 0)
        {
            throw new ReplayDrillBoundaryException("send-accepted-before-checkpoint");
        }
    }
}

internal sealed class ReplayDrillSettlementFault
{
    private int _injected;

    internal bool TryInject() => Interlocked.Exchange(ref _injected, 1) == 0;
}

internal sealed class ReplayDrillSettlement : IDlqReplayMessageActions
{
    private readonly ServiceBusReceiver _receiver;
    private readonly ServiceBusReceivedMessage _message;
    private readonly ReplayDrillSettlementFault? _fault;

    internal ReplayDrillSettlement(ReplayDrillTarget target, ServiceBusReceiver receiver,
        ServiceBusReceivedMessage message, ReplayDrillSettlementFault? fault = null)
    {
        target.ValidateEndpoint(receiver.FullyQualifiedNamespace, receiver.EntityPath, target.RequestQueue);
        if (receiver.ReceiveMode != ServiceBusReceiveMode.PeekLock)
        {
            throw new InvalidOperationException("Replay drill requires a PeekLock receiver.");
        }

        target.ValidateFixture(message.ApplicationProperties);
        _receiver = receiver;
        _message = message;
        _fault = fault;
    }

    internal bool Completed { get; private set; }

    public Task AbandonAsync(CancellationToken cancellationToken) =>
        _receiver.AbandonMessageAsync(_message, cancellationToken: cancellationToken);

    public Task DeadLetterAsync(string reason, string description, CancellationToken cancellationToken) =>
        _receiver.DeadLetterMessageAsync(_message, reason, description, cancellationToken);

    public async Task CompleteAsync(CancellationToken cancellationToken)
    {
        if (_fault?.TryInject() == true)
        {
            await AbandonAsync(cancellationToken);
            throw new ReplayDrillBoundaryException("checkpoint-before-settlement");
        }

        await _receiver.CompleteMessageAsync(_message, cancellationToken);
        Completed = true;
    }
}

internal sealed class ReplayDrillBoundaryException(string boundary) : Exception(boundary);
