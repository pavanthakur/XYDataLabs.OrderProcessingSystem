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
        ReplayCandidateResult? replayCandidate = null;

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

            checks.Add(await WaitForQuarantineRecordAsync(options, dlqMessageId));

            if (options.PrepareReplayCandidate)
            {
                replayCandidate = await PrepareReplayCandidateAsync(client, options);
                checks.Add(replayCandidate.Passed
                    ? SmokeCheck.Pass(
                        "Prepared transient Functions replay candidate",
                        $"Candidate `{replayCandidate.Evidence.QuarantineId}` is quarantined for tenant `{replayCandidate.Evidence.TenantCode}` and ready for the separately approved operator replay gate.")
                    : SmokeCheck.Fail(
                        "Prepared transient Functions replay candidate",
                        $"Candidate intake was not verified (source `{replayCandidate.Evidence.SourceMessageId}`, correlation `{replayCandidate.Evidence.CorrelationId}`, status `{replayCandidate.Evidence.Status}`). Do not republish automatically; reconcile this candidate first."));
                await WriteReplayCandidateAsync(options, replayCandidate.Evidence).ConfigureAwait(false);
            }

            checks.Add(await PublishValidAsync(
                client,
                options.TopicName,
                replayMessageId,
                options.TenantId,
                options.TenantCode,
                runId,
                "second-fanout"));

            var secondMessageEffects = await WaitForEffectsAsync(
                options,
                runId,
                expectedMessagesPerConsumer: 2,
                stageName: "second-message");
            checks.Add(secondMessageEffects.InventoryCheck);
            checks.Add(secondMessageEffects.NotificationsCheck);
        }
        catch (Exception ex)
        {
            checks.Add(SmokeCheck.Fail("Unexpected smoke failure", ex.Message));
        }

        var completedUtc = DateTimeOffset.UtcNow;
        WriteMarkdownSummary(options, runId, startedUtc, completedUtc, checks, replayCandidate?.Evidence);
        if (!string.IsNullOrWhiteSpace(options.SummaryJsonPath))
        {
            await WriteStructuredSummaryAsync(options, runId, startedUtc, completedUtc, checks).ConfigureAwait(false);
        }

        return checks.All(check => check.Passed) ? 0 : 1;
    }

    private static async Task WriteStructuredSummaryAsync(
        SmokeOptions options,
        string runId,
        DateTimeOffset startedUtc,
        DateTimeOffset completedUtc,
        IReadOnlyList<SmokeCheck> checks)
    {
        var outputPath = Path.GetFullPath(options.SummaryJsonPath!);
        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        var sourceRevision = System.Environment.GetEnvironmentVariable("GITHUB_SHA");
        if (sourceRevision is not null && !System.Text.RegularExpressions.Regex.IsMatch(sourceRevision, "^(?:[0-9a-f]{40}|[0-9a-f]{64})$", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
        {
            sourceRevision = null;
        }

        var summary = new
        {
            schema = "phase10-azure-transport-smoke-v1",
            status = checks.All(check => check.Passed) ? "passed" : "failed",
            environment = options.Environment,
            runId,
            sourceRevision,
            workflowRunId = System.Environment.GetEnvironmentVariable("GITHUB_RUN_ID"),
            workflowRunAttempt = System.Environment.GetEnvironmentVariable("GITHUB_RUN_ATTEMPT"),
            tenantCode = options.TenantCode,
            startedUtc,
            completedUtc,
            checks = checks.Select(check => new { name = check.Name, status = check.Passed ? "passed" : "failed" }).ToArray()
        };

        await using var stream = new FileStream(outputPath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        await JsonSerializer.SerializeAsync(stream, summary, new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        }).ConfigureAwait(false);
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

    private static async Task<SmokeCheck> WaitForQuarantineRecordAsync(
        SmokeOptions options,
        string sourceMessageId)
    {
        const string sql = """
            SET NOCOUNT ON;
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
            SET LOCK_TIMEOUT 5000;

            SELECT TOP (1) [SourceMessageId]
            FROM [operations].[DlqQuarantineRecords] WITH (READUNCOMMITTED)
            WHERE [SourceMessageId] = @sourceMessageId;
            """;

        var deadline = DateTimeOffset.UtcNow.AddSeconds(options.SqlTimeoutSeconds);
        while (DateTimeOffset.UtcNow < deadline)
        {
            await using var connection = new SqlConnection(options.OperationsSqlConnectionString);
            await connection.OpenAsync().ConfigureAwait(false);
            await using var command = new SqlCommand(sql, connection);
            command.Parameters.Add(new SqlParameter("@sourceMessageId", SqlDbType.NVarChar, 128) { Value = sourceMessageId });
            var result = await command.ExecuteScalarAsync().ConfigureAwait(false);
            if (result is string persistedMessageId)
            {
                return SmokeCheck.Pass(
                    "Deployed Functions quarantine intake",
                    $"Observed source message `{persistedMessageId}` persisted by the Functions intake trigger in `{options.OperationsDatabaseName}`.");
            }

            await Task.Delay(TimeSpan.FromSeconds(3)).ConfigureAwait(false);
        }

        return SmokeCheck.Fail(
            "Deployed Functions quarantine intake",
            $"No quarantine record for source message `{sourceMessageId}` appeared in `{options.OperationsDatabaseName}` before the configured timeout.");
    }

    private static async Task<ReplayCandidateResult> PrepareReplayCandidateAsync(
        ServiceBusClient client,
        SmokeOptions options)
    {
        var sourceMessageId = Guid.NewGuid().ToString("D");
        var envelopeMessageId = Guid.NewGuid();
        var orderReferenceId = Guid.NewGuid();
        var correlationId = $"phase10-replay-{Guid.NewGuid():N}";
        var payload = new
        {
            customerId = 101,
            orderDate = DateTime.UtcNow,
            totalPrice = 1.00m,
            productCount = 1,
            orderReferenceId,
            currencyCode = "MXN"
        };

        try
        {
            await using (var sender = client.CreateSender(options.DeadLetterTopicName))
            {
                var message = new ServiceBusMessage(BinaryData.FromObjectAsJson(payload))
                {
                    MessageId = sourceMessageId,
                    CorrelationId = correlationId,
                    Subject = "OrderCreatedV1",
                    ContentType = "application/json",
                    SessionId = options.TenantId.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    TimeToLive = TimeSpan.FromDays(7)
                };
                message.ApplicationProperties["TenantId"] = options.TenantId;
                message.ApplicationProperties["TenantCode"] = options.TenantCode;
                message.ApplicationProperties["EnvelopeMessageId"] = envelopeMessageId.ToString("D");
                message.ApplicationProperties["EventType"] = "OrderCreatedV1";
                message.ApplicationProperties["CorrelationId"] = correlationId;
                message.ApplicationProperties["CausationId"] = correlationId;
                message.ApplicationProperties["OccurredUtc"] = DateTimeOffset.UtcNow.ToString("O");
                message.ApplicationProperties["SchemaVersion"] = 1;
                message.ApplicationProperties["AttemptCount"] = 0;
                message.ApplicationProperties["FailureCategory"] = "transient-dependency";
                await sender.SendMessageAsync(message).ConfigureAwait(false);
            }
        }
        catch (Exception error)
        {
            return new ReplayCandidateResult(
                CreateReplayCandidate("publish-outcome-unknown", null, null, error.GetType().Name),
                Passed: false);
        }

        const string sql = """
            SET NOCOUNT ON;
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
            SET LOCK_TIMEOUT 5000;

            SELECT [Id], [TenantId], [CorrelationId], [FailureReason], [State], [ReplayAttemptCount], [CreatedUtc]
            FROM [operations].[DlqQuarantineRecords] WITH (READUNCOMMITTED)
            WHERE [SourceMessageId] = @sourceMessageId;
            """;

        try
        {
            var deadline = DateTimeOffset.UtcNow.AddSeconds(options.SqlTimeoutSeconds);
            while (DateTimeOffset.UtcNow < deadline)
            {
                await using var connection = new SqlConnection(options.OperationsSqlConnectionString);
                await connection.OpenAsync().ConfigureAwait(false);
                await using var command = new SqlCommand(sql, connection);
                command.Parameters.Add(new SqlParameter("@sourceMessageId", SqlDbType.NVarChar, 128) { Value = sourceMessageId });
                await using var reader = await command.ExecuteReaderAsync().ConfigureAwait(false);
                if (await reader.ReadAsync().ConfigureAwait(false))
                {
                    var quarantineId = reader.GetGuid(0);
                    var tenantId = reader.GetInt32(1);
                    var persistedCorrelation = reader.GetString(2);
                    var failureReason = reader.GetString(3);
                    var state = reader.GetString(4);
                    var replayAttemptCount = reader.GetInt32(5);
                    var createdUtc = reader.GetDateTime(6);
                    if (await reader.ReadAsync().ConfigureAwait(false))
                    {
                        throw new InvalidOperationException("Replay candidate source message resolved to multiple quarantine records.");
                    }
                    if (tenantId != options.TenantId
                        || !string.Equals(persistedCorrelation, correlationId, StringComparison.Ordinal)
                        || !string.Equals(failureReason, "quarantined-transient-dependency", StringComparison.OrdinalIgnoreCase)
                        || !string.Equals(state, "Quarantined", StringComparison.OrdinalIgnoreCase)
                        || replayAttemptCount != 0)
                    {
                        throw new InvalidOperationException("Functions quarantine evidence does not match the uniquely identified transient replay candidate.");
                    }

                    return new ReplayCandidateResult(
                        CreateReplayCandidate("ready-for-separately-approved-replay", quarantineId.ToString("D"), failureReason, null, createdUtc),
                        Passed: true);
                }

                await Task.Delay(TimeSpan.FromSeconds(2)).ConfigureAwait(false);
            }
        }
        catch (Exception error)
        {
            return new ReplayCandidateResult(
                CreateReplayCandidate("intake-verification-failed", null, null, error.GetType().Name),
                Passed: false);
        }

        return new ReplayCandidateResult(
            CreateReplayCandidate("intake-not-confirmed", null, null, nameof(TimeoutException)),
            Passed: false);

        ReplayCandidateEvidence CreateReplayCandidate(
            string status,
            string? quarantineId,
            string? failureReason,
            string? failureType,
            DateTime? createdUtc = null)
            => new(
                Schema: "phase10-azure-dlq-replay-candidate-v1",
                Status: status,
                Environment: options.Environment,
                TenantCode: options.TenantCode,
                TenantId: options.TenantId,
                BusinessDatabase: options.SqlDatabaseName,
                OperationsDatabase: options.OperationsDatabaseName,
                QuarantineId: quarantineId,
                SourceMessageId: sourceMessageId,
                CorrelationId: correlationId,
                FailureReason: failureReason,
                FailureType: failureType,
                CreatedUtc: createdUtc.HasValue ? new DateTimeOffset(DateTime.SpecifyKind(createdUtc.Value, DateTimeKind.Utc)) : DateTimeOffset.UtcNow);
    }

    private static async Task WriteReplayCandidateAsync(SmokeOptions options, ReplayCandidateEvidence candidate)
    {
        var outputPath = Path.GetFullPath(options.ReplayCandidateJsonPath!);
        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        var evidence = new
        {
            schema = candidate.Schema,
            status = candidate.Status,
            environment = candidate.Environment,
            tenantCode = candidate.TenantCode,
            tenantId = candidate.TenantId,
            businessDatabase = candidate.BusinessDatabase,
            operationsDatabase = candidate.OperationsDatabase,
            quarantineId = candidate.QuarantineId,
            sourceMessageId = candidate.SourceMessageId,
            correlationId = candidate.CorrelationId,
            failureReason = candidate.FailureReason,
            failureType = candidate.FailureType,
            createdUtc = candidate.CreatedUtc
        };
        await using var stream = new FileStream(outputPath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        await JsonSerializer.SerializeAsync(stream, evidence, new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        }).ConfigureAwait(false);
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
        IReadOnlyList<SmokeCheck> checks,
        ReplayCandidateEvidence? replayCandidate)
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
        Console.WriteLine($"| Functions Intake Subscription | `{options.DeadLetterSubscriptionName}` |");
        Console.WriteLine($"| Smoke Tenant | `{options.TenantCode}` (`{options.TenantId}`) |");
        Console.WriteLine($"| Verification Database | `{options.SqlDatabaseName}` |");
        Console.WriteLine($"| Operations Database | `{options.OperationsDatabaseName}` |");
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
            ? replayCandidate is { Status: "ready-for-separately-approved-replay" }
                ? $"Transport and Functions intake checks passed. Replay candidate `{replayCandidate.QuarantineId}` is recorded separately; it still requires the explicitly approved operator replay and downstream-effect gate."
                : "Transport publish, live consumer durable effects, broker DLQ forwarding, and deployed Functions quarantine intake are verified. This run does not prove approved Functions replay; that remains a separate acceptance gate."
            : "Review the failed check details, then inspect Azure SQL durable effects, Service Bus message counts, and application logs before rerunning.");
    }

    private static string Escape(string value) => value.Replace("|", "\\|", StringComparison.Ordinal).ReplaceLineEndings(" ");
}

internal sealed record SmokeCheck(string Name, bool Passed, string Detail)
{
    public static SmokeCheck Pass(string name, string detail) => new(name, true, detail);

    public static SmokeCheck Fail(string name, string detail) => new(name, false, detail);
}

internal sealed record ReplayCandidateEvidence(
    string Schema,
    string Status,
    string Environment,
    string TenantCode,
    int TenantId,
    string BusinessDatabase,
    string OperationsDatabase,
    string? QuarantineId,
    string SourceMessageId,
    string CorrelationId,
    string? FailureReason,
    string? FailureType,
    DateTimeOffset CreatedUtc);

internal sealed record ReplayCandidateResult(ReplayCandidateEvidence Evidence, bool Passed);

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
    string OperationsSqlConnectionString,
    string SqlDatabaseName,
    string OperationsDatabaseName,
    int TenantId,
    string TenantCode,
    int SqlTimeoutSeconds,
    string? RunId,
    string? SummaryJsonPath,
    bool PrepareReplayCandidate,
    string? ReplayCandidateJsonPath)
{
    public static SmokeOptions FromArgs(string[] args)
    {
        var values = ParseArgs(args);
        var environment = Get(values, "environment", "dev");
        var prepareReplayCandidate = values.ContainsKey("prepare-replay-candidate");
        if (prepareReplayCandidate && !string.Equals(environment, "dev", StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("Replay-candidate preparation is restricted to Azure dev.", nameof(args));
        }
        var replayCandidateJsonPath = values.TryGetValue("replay-candidate-json", out var replayPath) ? replayPath : null;
        if (prepareReplayCandidate != !string.IsNullOrWhiteSpace(replayCandidateJsonPath))
        {
            throw new ArgumentException("Replay candidate preparation requires --replay-candidate-json, and that path is not accepted unless --prepare-replay-candidate is selected.", nameof(args));
        }
        var suffix = string.Equals(environment, "staging", StringComparison.OrdinalIgnoreCase) ? "stg" : environment;
        var operationsSqlConnectionString = values.TryGetValue("operations-sql-connection-string", out var operationsConnectionString)
            ? operationsConnectionString
            : System.Environment.GetEnvironmentVariable("PHASE10_TRANSPORT_OPERATIONS_SQL_CONNECTION_STRING")
                ?? GetRequired(values, "sql-connection-string", "PHASE10_TRANSPORT_SQL_CONNECTION_STRING");

        return new SmokeOptions(
            Environment: environment,
            NamespaceName: Get(values, "namespace", $"sb-orderprocessing-{suffix}"),
            TopicName: Get(values, "topic", $"order-events-{suffix}"),
            InventorySubscriptionName: Get(values, "inventory-subscription", $"inventory-order-created-{suffix}"),
            NotificationsSubscriptionName: Get(values, "notifications-subscription", $"notifications-order-created-{suffix}"),
            DeadLetterTopicName: Get(values, "dead-letter-topic", "order-events-dlq"),
            DeadLetterSubscriptionName: Get(values, "dead-letter-subscription", $"dlq-replay-{suffix}"),
            ConnectionString: GetRequired(values, "connection-string", "PHASE10_TRANSPORT_SERVICEBUS_CONNECTION_STRING"),
            SqlConnectionString: GetRequired(values, "sql-connection-string", "PHASE10_TRANSPORT_SQL_CONNECTION_STRING"),
            OperationsSqlConnectionString: operationsSqlConnectionString,
            SqlDatabaseName: GetRequired(values, "sql-database"),
            OperationsDatabaseName: Get(values, "operations-database", GetRequired(values, "sql-database")),
            TenantId: int.Parse(GetRequired(values, "tenant-id")),
            TenantCode: GetRequired(values, "tenant-code"),
            SqlTimeoutSeconds: int.Parse(Get(values, "sql-timeout-seconds", "120")),
            RunId: values.TryGetValue("run-id", out var runId) ? runId : null,
            SummaryJsonPath: values.TryGetValue("summary-json", out var summaryJsonPath) ? summaryJsonPath : null,
            PrepareReplayCandidate: prepareReplayCandidate,
            ReplayCandidateJsonPath: replayCandidateJsonPath);
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
