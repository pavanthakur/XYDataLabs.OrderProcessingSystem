using System.Text.Json;
using Azure.Messaging.ServiceBus;
using System.Diagnostics.CodeAnalysis;

namespace XYDataLabs.OrderProcessingSystem.Tools.Phase10.TransportSmoke;

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        var options = SmokeOptions.FromArgs(args);
        var runId = options.RunId ?? $"phase10-transport-{options.Environment}-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}";
        var startedUtc = DateTimeOffset.UtcNow;
        var checks = new List<SmokeCheck>();

        await using var client = new ServiceBusClient(options.ConnectionString);

        var fanoutMessageId = $"{runId}-fanout";
        var dlqMessageId = $"{runId}-dlq";
        var replayMessageId = $"{runId}-replay";

        try
        {
            checks.Add(await PublishAsync(
                client,
                options.TopicName,
                fanoutMessageId,
                runId,
                "OrderCreatedV1",
                "fanout"));

            checks.Add(await ReceiveExpectedAsync(
                client,
                options.TopicName,
                options.InventorySubscriptionName,
                fanoutMessageId,
                "Inventory fan-out consume"));

            checks.Add(await ReceiveExpectedAsync(
                client,
                options.TopicName,
                options.NotificationsSubscriptionName,
                fanoutMessageId,
                "Notifications fan-out consume"));

            checks.Add(await PublishAsync(
                client,
                options.TopicName,
                dlqMessageId,
                runId,
                "OrderCreatedV1",
                "dlq-seed"));

            checks.Add(await DeadLetterExpectedAsync(
                client,
                options.TopicName,
                options.InventorySubscriptionName,
                dlqMessageId,
                "Inventory controlled dead-letter"));

            checks.Add(await ReceiveExpectedAsync(
                client,
                options.TopicName,
                options.NotificationsSubscriptionName,
                dlqMessageId,
                "Notifications cleanup for DLQ seed"));

            checks.Add(await ReceiveExpectedAsync(
                client,
                options.DeadLetterTopicName,
                options.DeadLetterSubscriptionName,
                dlqMessageId,
                "DLQ replay subscription receive"));

            checks.Add(await PublishAsync(
                client,
                options.TopicName,
                replayMessageId,
                runId,
                "OrderCreatedV1",
                "replay"));

            checks.Add(await ReceiveExpectedAsync(
                client,
                options.TopicName,
                options.InventorySubscriptionName,
                replayMessageId,
                "Inventory replay consume"));

            checks.Add(await ReceiveExpectedAsync(
                client,
                options.TopicName,
                options.NotificationsSubscriptionName,
                replayMessageId,
                "Notifications replay consume"));
        }
        catch (Exception ex)
        {
            checks.Add(SmokeCheck.Fail("Unexpected smoke failure", ex.Message));
        }

        var completedUtc = DateTimeOffset.UtcNow;
        WriteMarkdownSummary(options, runId, startedUtc, completedUtc, checks);

        return checks.All(check => check.Passed) ? 0 : 1;
    }

    private static async Task<SmokeCheck> PublishAsync(
        ServiceBusClient client,
        string topicName,
        string messageId,
        string runId,
        string eventType,
        string stage)
    {
        var payload = new
        {
            messageId,
            eventType,
            occurredUtc = DateTimeOffset.UtcNow,
            correlationId = runId,
            tenantCode = "TenantA",
            payload = new
            {
                orderId = messageId,
                customerId = 101,
                totalAmount = 25.50m,
                smokeStage = stage
            }
        };

        await using var sender = client.CreateSender(topicName);
        var message = new ServiceBusMessage(BinaryData.FromObjectAsJson(payload))
        {
            MessageId = messageId,
            CorrelationId = runId,
            Subject = eventType,
            ContentType = "application/json"
        };
        message.ApplicationProperties["eventType"] = eventType;
        message.ApplicationProperties["tenantCode"] = "TenantA";
        message.ApplicationProperties["correlationId"] = runId;
        message.ApplicationProperties["smokeStage"] = stage;

        await sender.SendMessageAsync(message);
        return SmokeCheck.Pass($"Publish {stage}", $"Published `{messageId}` to `{topicName}`.");
    }

    private static async Task<SmokeCheck> ReceiveExpectedAsync(
        ServiceBusClient client,
        string topicName,
        string subscriptionName,
        string expectedMessageId,
        string checkName)
    {
        await using var receiver = client.CreateReceiver(topicName, subscriptionName, new ServiceBusReceiverOptions
        {
            ReceiveMode = ServiceBusReceiveMode.PeekLock
        });

        var deadline = DateTimeOffset.UtcNow.AddSeconds(75);
        var inspected = 0;

        while (DateTimeOffset.UtcNow < deadline)
        {
            var messages = await receiver.ReceiveMessagesAsync(maxMessages: 10, maxWaitTime: TimeSpan.FromSeconds(5));
            if (messages.Count == 0)
            {
                continue;
            }

            foreach (var message in messages)
            {
                inspected++;
                if (string.Equals(message.MessageId, expectedMessageId, StringComparison.Ordinal))
                {
                    await receiver.CompleteMessageAsync(message);
                    return SmokeCheck.Pass(checkName, $"Received and completed `{expectedMessageId}` from `{topicName}/{subscriptionName}` after inspecting {inspected} message(s).");
                }

                await receiver.AbandonMessageAsync(message);
            }
        }

        return SmokeCheck.Fail(checkName, $"Did not receive `{expectedMessageId}` from `{topicName}/{subscriptionName}` before timeout. Inspected {inspected} message(s).");
    }

    private static async Task<SmokeCheck> DeadLetterExpectedAsync(
        ServiceBusClient client,
        string topicName,
        string subscriptionName,
        string expectedMessageId,
        string checkName)
    {
        await using var receiver = client.CreateReceiver(topicName, subscriptionName, new ServiceBusReceiverOptions
        {
            ReceiveMode = ServiceBusReceiveMode.PeekLock
        });

        var deadline = DateTimeOffset.UtcNow.AddSeconds(75);
        var inspected = 0;

        while (DateTimeOffset.UtcNow < deadline)
        {
            var messages = await receiver.ReceiveMessagesAsync(maxMessages: 10, maxWaitTime: TimeSpan.FromSeconds(5));
            if (messages.Count == 0)
            {
                continue;
            }

            foreach (var message in messages)
            {
                inspected++;
                if (string.Equals(message.MessageId, expectedMessageId, StringComparison.Ordinal))
                {
                    await receiver.DeadLetterMessageAsync(
                        message,
                        "Phase10TransportSmoke",
                        "Controlled smoke dead-letter to verify DLQ forwarding.");
                    return SmokeCheck.Pass(checkName, $"Dead-lettered `{expectedMessageId}` from `{topicName}/{subscriptionName}` after inspecting {inspected} message(s).");
                }

                await receiver.AbandonMessageAsync(message);
            }
        }

        return SmokeCheck.Fail(checkName, $"Did not find `{expectedMessageId}` in `{topicName}/{subscriptionName}` for controlled dead-letter before timeout. Inspected {inspected} message(s).");
    }

    [SuppressMessage("Globalization", "CA1303:Do not pass literals as localized parameters", Justification = "This command-line smoke tool writes fixed Markdown headings to GitHub Actions summaries.")]
    private static void WriteMarkdownSummary(
        SmokeOptions options,
        string runId,
        DateTimeOffset startedUtc,
        DateTimeOffset completedUtc,
        IReadOnlyList<SmokeCheck> checks)
    {
        var passed = checks.Count(check => check.Passed);
        var failed = checks.Count - passed;
        var status = failed == 0 ? "PASS" : "FAIL";

        Console.WriteLine("## Phase 10 Azure Transport Smoke");
        Console.WriteLine();
        Console.WriteLine($"**Status:** {status}");
        Console.WriteLine($"**Run ID:** `{runId}`");
        Console.WriteLine($"**Environment:** `{options.Environment}`");
        Console.WriteLine($"**Started UTC:** `{startedUtc:O}`");
        Console.WriteLine($"**Completed UTC:** `{completedUtc:O}`");
        Console.WriteLine();
        Console.WriteLine("### Topology");
        Console.WriteLine();
        Console.WriteLine("| Item | Value |");
        Console.WriteLine("|---|---|");
        Console.WriteLine($"| Service Bus Namespace | `{options.NamespaceName}` |");
        Console.WriteLine($"| Main Topic | `{options.TopicName}` |");
        Console.WriteLine($"| Inventory Subscription | `{options.InventorySubscriptionName}` |");
        Console.WriteLine($"| Notifications Subscription | `{options.NotificationsSubscriptionName}` |");
        Console.WriteLine($"| DLQ Topic | `{options.DeadLetterTopicName}` |");
        Console.WriteLine($"| Replay Subscription | `{options.DeadLetterSubscriptionName}` |");
        Console.WriteLine();
        Console.WriteLine("### Checks");
        Console.WriteLine();
        Console.WriteLine("| Check | Result | Detail |");
        Console.WriteLine("|---|---|---|");
        foreach (var check in checks)
        {
            var icon = check.Passed ? "PASS" : "FAIL";
            Console.WriteLine($"| {Escape(check.Name)} | {icon} | {Escape(check.Detail)} |");
        }

        Console.WriteLine();
        Console.WriteLine("### Next Operator Action");
        Console.WriteLine();
        Console.WriteLine(failed == 0
            ? "Transport publish, fan-out consume, controlled DLQ forwarding, and replay publish/consume are verified."
            : "Review the failed check details, then inspect Service Bus message counts and application logs before rerunning.");
    }

    private static string Escape(string value) => value.Replace("|", "\\|", StringComparison.Ordinal).ReplaceLineEndings(" ");
}

internal sealed record SmokeCheck(string Name, bool Passed, string Detail)
{
    public static SmokeCheck Pass(string name, string detail) => new(name, true, detail);

    public static SmokeCheck Fail(string name, string detail) => new(name, false, detail);
}

internal sealed record SmokeOptions(
    string Environment,
    string NamespaceName,
    string TopicName,
    string InventorySubscriptionName,
    string NotificationsSubscriptionName,
    string DeadLetterTopicName,
    string DeadLetterSubscriptionName,
    string ConnectionString,
    string? RunId)
{
    public static SmokeOptions FromArgs(string[] args)
    {
        var values = ParseArgs(args);
        var environment = Get(values, "environment", "dev");
        var suffix = string.Equals(environment, "staging", StringComparison.OrdinalIgnoreCase) ? "stg" : environment;

        return new SmokeOptions(
            Environment: environment,
            NamespaceName: Get(values, "namespace", $"sb-orderprocessing-{suffix}"),
            TopicName: Get(values, "topic", $"order-events-{suffix}"),
            InventorySubscriptionName: Get(values, "inventory-subscription", $"inventory-order-created-{suffix}"),
            NotificationsSubscriptionName: Get(values, "notifications-subscription", $"notifications-order-created-{suffix}"),
            DeadLetterTopicName: Get(values, "dead-letter-topic", "order-events-dlq"),
            DeadLetterSubscriptionName: Get(values, "dead-letter-subscription", $"dlq-replay-{suffix}"),
            ConnectionString: GetRequired(values, "connection-string"),
            RunId: values.TryGetValue("run-id", out var runId) ? runId : null);
    }

    private static Dictionary<string, string> ParseArgs(string[] args)
    {
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var index = 0;
        while (index < args.Length)
        {
            var arg = args[index];
            if (!arg.StartsWith("--", StringComparison.Ordinal))
            {
                index++;
                continue;
            }

            var key = arg[2..];
            if (index + 1 >= args.Length || args[index + 1].StartsWith("--", StringComparison.Ordinal))
            {
                values[key] = "true";
                index++;
                continue;
            }

            values[key] = args[index + 1];
            index += 2;
        }

        return values;
    }

    private static string Get(IReadOnlyDictionary<string, string> values, string key, string defaultValue)
        => values.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value) ? value : defaultValue;

    private static string GetRequired(IReadOnlyDictionary<string, string> values, string key)
        => values.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value)
            ? value
            : throw new ArgumentException($"Missing required argument --{key}.", nameof(values));
}
