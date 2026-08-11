using System.Data;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Microsoft.Data.SqlClient;
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
        var dlqMessageId = Guid.NewGuid().ToString("D");
        var replayMessageId = $"{runId}-replay";

        try
        {
            checks.Add(await PublishValidAsync(
                client,
                options.TopicName,
                fanoutMessageId,
                options.TenantId,
                options.TenantCode,
                runId,
                "fanout"));

            var fanoutEffects = await WaitForEffectsAsync(
                options,
                runId,
                expectedMessagesPerConsumer: 1,
                stageName: "fan-out");
            checks.Add(fanoutEffects.InventoryCheck);
            checks.Add(fanoutEffects.NotificationsCheck);

            checks.Add(await PublishMalformedAsync(
                client,
                options.TopicName,
                dlqMessageId,
                runId));

            checks.Add(await ReceiveExpectedAsync(
                client,
                options.DeadLetterTopicName,
                options.DeadLetterSubscriptionName,
                dlqMessageId,
                "DLQ replay subscription receive"));

            checks.Add(await PublishValidAsync(
                client,
                options.TopicName,
                replayMessageId,
                options.TenantId,
                options.TenantCode,
                runId,
                "replay"));

            var replayEffects = await WaitForEffectsAsync(
                options,
                runId,
                expectedMessagesPerConsumer: 2,
                stageName: "replay");
            checks.Add(replayEffects.InventoryCheck);
            checks.Add(replayEffects.NotificationsCheck);
        }
        catch (Exception ex)
        {
            checks.Add(SmokeCheck.Fail("Unexpected smoke failure", ex.Message));
        }

        var completedUtc = DateTimeOffset.UtcNow;
        WriteMarkdownSummary(options, runId, startedUtc, completedUtc, checks);

        return checks.All(check => check.Passed) ? 0 : 1;
    }

    private static async Task<SmokeCheck> PublishValidAsync(
        ServiceBusClient client,
        string topicName,
        string messageId,
        int tenantId,
        string tenantCode,
        string runId,
        string stage)
    {
        var envelopeMessageId = Guid.NewGuid();
        var orderReferenceId = Guid.NewGuid();
        var payload = new
        {
            customerId = 101,
            orderDate = DateTime.UtcNow,
            totalPrice = 25.50m,
            productCount = 1,
            orderReferenceId,
            currencyCode = "MXN"
        };

        await using var sender = client.CreateSender(topicName);
        var message = new ServiceBusMessage(BinaryData.FromObjectAsJson(payload))
        {
            MessageId = messageId,
            CorrelationId = runId,
            Subject = "OrderCreatedV1",
            ContentType = "application/json",
            SessionId = tenantId.ToString(),
            TimeToLive = TimeSpan.FromDays(7)
        };
        message.ApplicationProperties["TenantId"] = tenantId;
        message.ApplicationProperties["TenantCode"] = tenantCode;
        message.ApplicationProperties["EnvelopeMessageId"] = envelopeMessageId.ToString("D");
        message.ApplicationProperties["EventType"] = "OrderCreatedV1";
        message.ApplicationProperties["CorrelationId"] = runId;
        message.ApplicationProperties["CausationId"] = runId;
        message.ApplicationProperties["SmokeStage"] = stage;
        message.ApplicationProperties["OccurredUtc"] = DateTimeOffset.UtcNow.ToString("O");
        message.ApplicationProperties["SchemaVersion"] = 1;
        message.ApplicationProperties["AttemptCount"] = 0;
        message.ApplicationProperties["FailureCategory"] = string.Empty;

        await sender.SendMessageAsync(message);
        return SmokeCheck.Pass($"Publish {stage}", $"Published `{messageId}` to `{topicName}`.");
    }

    private static async Task<SmokeCheck> PublishMalformedAsync(
        ServiceBusClient client,
        string topicName,
        string messageId,
        string runId)
    {
        await using var sender = client.CreateSender(topicName);
        var message = new ServiceBusMessage(BinaryData.FromObjectAsJson(new
        {
            customerId = 404,
            orderDate = DateTime.UtcNow,
            totalPrice = 0.01m,
            productCount = 1,
            orderReferenceId = Guid.NewGuid(),
            currencyCode = "MXN"
        }))
        {
            MessageId = messageId,
            CorrelationId = runId,
            Subject = "OrderCreatedV1",
            ContentType = "application/json",
            TimeToLive = TimeSpan.FromDays(7)
        };
        message.ApplicationProperties["EnvelopeMessageId"] = Guid.NewGuid().ToString("D");
        message.ApplicationProperties["EventType"] = "OrderCreatedV1";
        message.ApplicationProperties["CorrelationId"] = runId;
        message.ApplicationProperties["CausationId"] = runId;
        message.ApplicationProperties["SmokeStage"] = "dlq-seed";
        message.ApplicationProperties["AttemptCount"] = 0;
        message.ApplicationProperties["FailureCategory"] = string.Empty;

        await sender.SendMessageAsync(message);
        return SmokeCheck.Pass(
            "Publish dlq-seed",
            $"Published malformed `{messageId}` to `{topicName}` so live consumers should dead-letter it.");
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

    private static async Task<EffectCheckResult> WaitForEffectsAsync(
        SmokeOptions options,
        string runId,
        int expectedMessagesPerConsumer,
        string stageName)
    {
        var deadline = DateTimeOffset.UtcNow.AddSeconds(options.SqlTimeoutSeconds);
        DurableEffectSnapshot latest = DurableEffectSnapshot.Empty;

        while (DateTimeOffset.UtcNow < deadline)
        {
            latest = await ReadSnapshotAsync(options, runId).ConfigureAwait(false);
            if (latest.InventoryInboxCount >= expectedMessagesPerConsumer
                && latest.NotificationsInboxCount >= expectedMessagesPerConsumer
                && latest.InventoryEffectCount >= expectedMessagesPerConsumer
                && latest.NotificationEffectCount >= expectedMessagesPerConsumer)
            {
                return new EffectCheckResult(
                    SmokeCheck.Pass(
                        $"Inventory {stageName} processing",
                        $"Observed inventory inbox/effects counts {latest.InventoryInboxCount}/{latest.InventoryEffectCount} for correlation `{runId}` in `{options.SqlDatabaseName}`."),
                    SmokeCheck.Pass(
                        $"Notifications {stageName} processing",
                        $"Observed notifications inbox/effects counts {latest.NotificationsInboxCount}/{latest.NotificationEffectCount} for correlation `{runId}` in `{options.SqlDatabaseName}`."));
            }

            await Task.Delay(TimeSpan.FromSeconds(3)).ConfigureAwait(false);
        }

        return new EffectCheckResult(
            SmokeCheck.Fail(
                $"Inventory {stageName} processing",
                $"Timed out waiting for inventory inbox/effects >= {expectedMessagesPerConsumer}. Observed {latest.InventoryInboxCount}/{latest.InventoryEffectCount} in `{options.SqlDatabaseName}` for correlation `{runId}`."),
            SmokeCheck.Fail(
                $"Notifications {stageName} processing",
                $"Timed out waiting for notifications inbox/effects >= {expectedMessagesPerConsumer}. Observed {latest.NotificationsInboxCount}/{latest.NotificationEffectCount} in `{options.SqlDatabaseName}` for correlation `{runId}`."));
    }

    private static async Task<DurableEffectSnapshot> ReadSnapshotAsync(SmokeOptions options, string runId)
    {
        const string sql = """
            SET NOCOUNT ON;
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
            SET LOCK_TIMEOUT 5000;

            SELECT
              COALESCE((
                SELECT COUNT(*)
                FROM [operations].[ConsumerInboxMessages] WITH (READUNCOMMITTED)
                WHERE [CorrelationId] = @runId AND [ConsumerName] = N'Inventory'
              ), 0) AS InventoryInboxCount,
              COALESCE((
                SELECT COUNT(*)
                FROM [operations].[ConsumerInboxMessages] WITH (READUNCOMMITTED)
                WHERE [CorrelationId] = @runId AND [ConsumerName] = N'Notifications'
              ), 0) AS NotificationsInboxCount,
              COALESCE((
                SELECT COUNT(*)
                FROM [inventory].[InventoryReservations] WITH (READUNCOMMITTED)
                WHERE [CorrelationId] = @runId
              ), 0) AS InventoryEffectCount,
              COALESCE((
                SELECT COUNT(*)
                FROM [notifications].[NotificationDeliveries] WITH (READUNCOMMITTED)
                WHERE [CorrelationId] = @runId
              ), 0) AS NotificationEffectCount;
            """;

        await using var connection = new SqlConnection(options.SqlConnectionString);
        await connection.OpenAsync().ConfigureAwait(false);
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add(new SqlParameter("@runId", SqlDbType.NVarChar, 128) { Value = runId });

        await using var reader = await command.ExecuteReaderAsync().ConfigureAwait(false);
        if (!await reader.ReadAsync().ConfigureAwait(false))
        {
            return DurableEffectSnapshot.Empty;
        }

        return new DurableEffectSnapshot(
            InventoryInboxCount: await reader.IsDBNullAsync(0).ConfigureAwait(false) ? 0 : Convert.ToInt32(reader.GetValue(0)),
            NotificationsInboxCount: await reader.IsDBNullAsync(1).ConfigureAwait(false) ? 0 : Convert.ToInt32(reader.GetValue(1)),
            InventoryEffectCount: await reader.IsDBNullAsync(2).ConfigureAwait(false) ? 0 : Convert.ToInt32(reader.GetValue(2)),
            NotificationEffectCount: await reader.IsDBNullAsync(3).ConfigureAwait(false) ? 0 : Convert.ToInt32(reader.GetValue(3)));
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
        Console.WriteLine($"| Smoke Tenant | `{options.TenantCode}` (`{options.TenantId}`) |");
        Console.WriteLine($"| Verification Database | `{options.SqlDatabaseName}` |");
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
            ? "Transport publish, live consumer durable effects, DLQ forwarding, and replay consume are verified."
            : "Review the failed check details, then inspect Azure SQL durable effects, Service Bus message counts, and application logs before rerunning.");
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
    string SqlConnectionString,
    string SqlDatabaseName,
    int TenantId,
    string TenantCode,
    int SqlTimeoutSeconds,
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
            SqlConnectionString: GetRequired(values, "sql-connection-string", "PHASE10_TRANSPORT_SQL_CONNECTION_STRING"),
            SqlDatabaseName: GetRequired(values, "sql-database"),
            TenantId: int.Parse(GetRequired(values, "tenant-id")),
            TenantCode: GetRequired(values, "tenant-code"),
            SqlTimeoutSeconds: int.Parse(Get(values, "sql-timeout-seconds", "120")),
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

    private static string GetRequired(
        IReadOnlyDictionary<string, string> values,
        string key,
        string environmentVariable)
        => values.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value)
            ? value
            : !string.IsNullOrWhiteSpace(System.Environment.GetEnvironmentVariable(environmentVariable))
                ? System.Environment.GetEnvironmentVariable(environmentVariable)!
                : throw new ArgumentException($"Missing required argument --{key}.", nameof(values));
}

internal sealed record DurableEffectSnapshot(
    int InventoryInboxCount,
    int NotificationsInboxCount,
    int InventoryEffectCount,
    int NotificationEffectCount)
{
    public static DurableEffectSnapshot Empty { get; } = new(0, 0, 0, 0);
}

internal sealed record EffectCheckResult(SmokeCheck InventoryCheck, SmokeCheck NotificationsCheck);
