using Azure.Messaging.ServiceBus;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using System.Text.Json;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

public sealed class ReplayDrillBrokerAdapterTests
{
    private readonly Guid _run = Guid.NewGuid();
    private readonly Guid _quarantine = Guid.NewGuid();
    private readonly Guid _request = Guid.NewGuid();
    private ReplayDrillTarget Target => LoadTarget();

    [Fact]
    public async Task FaultFollowsSuccessfulSendAndDoesNotFireTwice()
    {
        var target = Target;
        await using var sender = new RecordingSender(target.FullyQualifiedNamespace, target.BusinessTopic);
        var publisher = new ReplayDrillPublisher(target, sender, failAfterAcceptedSend: true);
        var firstTransportId = Guid.NewGuid().ToString("D");
        var message = new ServiceBusMessage { MessageId = firstTransportId };
        var envelopeId = Guid.NewGuid().ToString("D");
        message.ApplicationProperties["QuarantineId"] = _quarantine.ToString("D");
        message.ApplicationProperties["ReplayRequestId"] = _request.ToString("D");
        message.ApplicationProperties["EnvelopeMessageId"] = envelopeId;

        sender.Fail = true;
        await Assert.ThrowsAsync<InvalidOperationException>(() => publisher.PublishAsync(message, CancellationToken.None));
        Assert.Empty(sender.Accepted);
        sender.Fail = false;
        var fault = await Assert.ThrowsAsync<ReplayDrillBoundaryException>(() => publisher.PublishAsync(message, CancellationToken.None));
        Assert.Equal("send-accepted-before-checkpoint", fault.Message);
        Assert.Single(sender.Accepted);
        await publisher.PublishAsync(message, CancellationToken.None);
        Assert.Equal(2, sender.Accepted.Count);
        Assert.Equal(firstTransportId, sender.Accepted[0]);
        Assert.NotEqual(sender.Accepted[0], sender.Accepted[1]);
        Assert.Equal(new[] { envelopeId, envelopeId }, publisher.PublishedEnvelopeMessageIds);
        Assert.Equal(sender.Accepted, publisher.PublishedTransportMessageIds);
    }

    [Fact]
    public async Task RejectsForeignTargetsAndFixturesWithoutSending()
    {
        var target = Target;
        await using var foreignSender = new RecordingSender("other-dev.servicebus.windows.net", target.BusinessTopic);
        Assert.Throws<InvalidOperationException>(() => new ReplayDrillPublisher(target, foreignSender, true));
        await using var sender = new RecordingSender(target.FullyQualifiedNamespace, target.BusinessTopic);
        var publisher = new ReplayDrillPublisher(target, sender, true);
        var missingEnvelope = new ServiceBusMessage();
        missingEnvelope.ApplicationProperties["QuarantineId"] = _quarantine.ToString("D");
        missingEnvelope.ApplicationProperties["ReplayRequestId"] = _request.ToString("D");
        await Assert.ThrowsAsync<InvalidOperationException>(() => publisher.PublishAsync(missingEnvelope, CancellationToken.None));
        Assert.Empty(sender.Accepted);
    }

    [Fact]
    public async Task TargetRejectsNonDevAndDoesNotSynthesizeRunSpecificNamespaces()
    {
        var target = Target;
        var staging = new ReplayDrillTarget("stg", target.FullyQualifiedNamespace, target.BusinessTopic, target.NormalRequestQueue, target.RequestQueue, _run, _quarantine, _request);
        await using var sender = new RecordingSender(target.FullyQualifiedNamespace, target.BusinessTopic);

        Assert.Throws<InvalidOperationException>(() => new ReplayDrillPublisher(staging, sender, true));
        Assert.DoesNotContain(_run.ToString("N"), target.FullyQualifiedNamespace, StringComparison.OrdinalIgnoreCase);
        Assert.EndsWith(".servicebus.windows.net", target.FullyQualifiedNamespace, StringComparison.OrdinalIgnoreCase);
        var sharedQueue = new ReplayDrillTarget("dev", target.FullyQualifiedNamespace, target.BusinessTopic, target.NormalRequestQueue, target.NormalRequestQueue, _run, _quarantine, _request);
        Assert.Throws<InvalidOperationException>(() => sharedQueue.ValidateEndpoint(target.FullyQualifiedNamespace, target.RequestQueue, target.RequestQueue));
    }

    [Fact]
    public async Task TargetBuildsServiceBusClientFromConfiguredFqdnAndCredential()
    {
        var target = Target;
        await using var client = target.CreateClient(new NoNetworkCredential());
        await using var sender = target.CreateBusinessTopicSender(client);
        await using var receiver = target.CreateRequestReceiver(client);

        Assert.Equal(target.FullyQualifiedNamespace, client.FullyQualifiedNamespace);
        Assert.Equal(target.BusinessTopic, sender.EntityPath);
        Assert.Equal(target.RequestQueue, receiver.EntityPath);
        Assert.Equal(ServiceBusReceiveMode.PeekLock, receiver.ReceiveMode);
    }

    [Fact]
    public void PublisherRequestScopeTargetsOnlyTheApprovedReplayId()
    {
        var targetId = Guid.NewGuid();
        var requests = new[]
        {
            new DlqReplayRequest { Id = Guid.NewGuid() },
            new DlqReplayRequest { Id = targetId },
            new DlqReplayRequest { Id = Guid.NewGuid() }
        }.AsQueryable();

        var scoped = DlqReplayRequestPublisher.ScopePendingRequests(requests, targetId).ToArray();
        var normal = DlqReplayRequestPublisher.ScopePendingRequests(requests, null).ToArray();

        Assert.Single(scoped);
        Assert.Equal(targetId, scoped[0].Id);
        Assert.Equal(3, normal.Length);
        Assert.Throws<ArgumentException>(() => DlqReplayRequestPublisher.ScopePendingRequests(requests, Guid.Empty));
    }

    [Fact]
    public void DedicatedDatabaseReferenceMustMatchExpectedAzureSqlServer()
    {
        var connectionString = "Server=tcp:orderprocessing-sql-dev.database.windows.net,1433;Initial Catalog=TenantC_Dev;Encrypt=True;";
        Assert.Equal("TenantC_Dev", AzureReplayDrillAcceptanceTests.ResolveDedicatedDatabaseName(connectionString, "orderprocessing-sql-dev"));
        Assert.Throws<InvalidOperationException>(() => AzureReplayDrillAcceptanceTests.ResolveDedicatedDatabaseName(connectionString, "orderprocessing-sql-prod"));
        Assert.Throws<InvalidOperationException>(() => AzureReplayDrillAcceptanceTests.ResolveDedicatedDatabaseName(
            "Server=tcp:orderprocessing-sql-dev.database.windows.net,1433;Initial Catalog=Tenant C;", "orderprocessing-sql-dev"));
        Assert.Throws<InvalidOperationException>(() => AzureReplayDrillAcceptanceTests.ResolveDedicatedDatabaseName("not-a-connection-string", "orderprocessing-sql-dev"));
    }

    [Fact]
    public void ReplayPassEvidenceMatchesTheGuardedRestoreContract()
    {
        var requestId = Guid.NewGuid();
        var evidence = AzureReplayDrillAcceptanceTests.CreateRestoreEvidence("approved-dev-subscription", requestId, 0);

        Assert.Equal("PASS", evidence.Status);
        Assert.Equal("dev", evidence.Environment);
        Assert.Equal("approved-dev-subscription", evidence.SubscriptionId);
        Assert.Equal(requestId, evidence.ReplayRequestId);
        Assert.True(evidence.PublisherCheckpointed);
        Assert.Equal(0, evidence.PendingReplayRequestCount);
        Assert.Throws<InvalidOperationException>(() => AzureReplayDrillAcceptanceTests.CreateRestoreEvidence("approved-dev-subscription", requestId, 1));
    }

    [Fact]
    public void ReplayEvidencePathMustStayInsideTestResults()
    {
        var repositoryRoot = Path.Combine(Path.GetTempPath(), "phase10-replay-path-" + Guid.NewGuid().ToString("N"));
        var testResults = Path.Combine(repositoryRoot, "TestResults");
        Directory.CreateDirectory(testResults);
        try
        {
            var accepted = Path.Combine(testResults, "Phase10", "evidence.json");
            Assert.Equal(Path.GetFullPath(accepted), AzureReplayDrillAcceptanceTests.ResolveEvidencePathUnderTestResults(repositoryRoot, accepted));
            Assert.Throws<InvalidOperationException>(() => AzureReplayDrillAcceptanceTests.ResolveEvidencePathUnderTestResults(
                repositoryRoot, Path.Combine(repositoryRoot, "outside.json")));
            Assert.Throws<InvalidOperationException>(() => AzureReplayDrillAcceptanceTests.ResolveEvidencePathUnderTestResults(
                repositoryRoot, testResults));
        }
        finally
        {
            Directory.Delete(repositoryRoot, recursive: true);
        }
    }

    [Fact]
    public async Task SettlementFaultAbandonsOnceThenCompletesNextDelivery()
    {
        var target = Target;
        await using var receiver = new RecordingReceiver(target.FullyQualifiedNamespace, target.RequestQueue);
        var fault = new ReplayDrillSettlementFault();
        var properties = new Dictionary<string, object>
        {
            ["QuarantineId"] = _quarantine.ToString("D"),
            ["ReplayRequestId"] = _request.ToString("D")
        };
        var first = ServiceBusModelFactory.ServiceBusReceivedMessage(properties: properties, deliveryCount: 1);
        var second = ServiceBusModelFactory.ServiceBusReceivedMessage(properties: properties, deliveryCount: 2);
        var boundary = await Assert.ThrowsAsync<ReplayDrillBoundaryException>(() =>
            new ReplayDrillSettlement(target, receiver, first, fault).CompleteAsync(CancellationToken.None));
        Assert.Equal("checkpoint-before-settlement", boundary.Message);
        Assert.Same(first, receiver.Abandoned);
        Assert.Null(receiver.Completed);
        await new ReplayDrillSettlement(target, receiver, second, fault).CompleteAsync(CancellationToken.None);
        Assert.Same(second, receiver.Completed);
    }

    private ReplayDrillTarget LoadTarget()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "automation", "config", "runtime-targets.json")))
        {
            directory = directory.Parent;
        }

        if (directory is null)
        {
            throw new InvalidOperationException("Replay drill tests require the repository runtime-target catalog.");
        }

        var catalogPath = Path.Combine(directory.FullName, "automation", "config", "runtime-targets.json");
        using var catalog = JsonDocument.Parse(File.ReadAllText(catalogPath));
        var target = catalog.RootElement.GetProperty("targets").EnumerateArray()
            .Single(item => item.GetProperty("key").GetString() == "azure-dev");

        return new ReplayDrillTarget(
            target.GetProperty("environment").GetString()!,
            target.GetProperty("azureServiceBusFullyQualifiedNamespace").GetString()!,
            target.GetProperty("azureOrderEventsTopicName").GetString()!,
            target.GetProperty("azureReplayRequestQueueName").GetString()!,
            target.GetProperty("azureReplayDrillRequestQueueName").GetString()!,
            _run,
            _quarantine,
            _request);
    }

    private sealed class RecordingSender(string endpoint, string entityPath) : ServiceBusSender
    {
        public override string FullyQualifiedNamespace => endpoint;
        public override string EntityPath => entityPath;
        internal bool Fail { get; set; }
        internal List<string> Accepted { get; } = [];
        public override Task SendMessageAsync(ServiceBusMessage message, CancellationToken cancellationToken = default)
        {
            if (Fail) throw new InvalidOperationException("Test send failed without acceptance.");
            Accepted.Add(message.MessageId);
            return Task.CompletedTask;
        }

        public override ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    private sealed class RecordingReceiver(string endpoint, string entityPath) : ServiceBusReceiver
    {
        public override string FullyQualifiedNamespace => endpoint;
        public override string EntityPath => entityPath;
        public override ServiceBusReceiveMode ReceiveMode => ServiceBusReceiveMode.PeekLock;
        internal ServiceBusReceivedMessage? Abandoned { get; private set; }
        internal ServiceBusReceivedMessage? Completed { get; private set; }
        public override Task AbandonMessageAsync(ServiceBusReceivedMessage message,
            IDictionary<string, object>? propertiesToModify = null, CancellationToken cancellationToken = default)
        {
            Abandoned = message;
            return Task.CompletedTask;
        }

        public override Task CompleteMessageAsync(ServiceBusReceivedMessage message, CancellationToken cancellationToken = default)
        {
            Completed = message;
            return Task.CompletedTask;
        }

        public override ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    private sealed class NoNetworkCredential : Azure.Core.TokenCredential
    {
        public override Azure.Core.AccessToken GetToken(Azure.Core.TokenRequestContext requestContext, CancellationToken cancellationToken) =>
            throw new InvalidOperationException("The adapter test must not request an access token.");

        public override ValueTask<Azure.Core.AccessToken> GetTokenAsync(Azure.Core.TokenRequestContext requestContext, CancellationToken cancellationToken) =>
            ValueTask.FromException<Azure.Core.AccessToken>(new InvalidOperationException("The adapter test must not request an access token."));
    }
}
