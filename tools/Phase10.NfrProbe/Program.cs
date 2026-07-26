using System.Data;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Microsoft.Data.SqlClient;

namespace XYDataLabs.OrderProcessingSystem.Tools.Phase10.NfrProbe;

internal static class Program
{
    private const int MaximumPayloadBytes = 256 * 1024;

    private static async Task<int> Main(string[] args)
    {
        var options = ProbeOptions.FromArgs(args);
        var runId = options.RunId ?? $"phase10-nfr-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}";
        var startedUtc = DateTimeOffset.UtcNow;
        var messageIds = Enumerable.Range(1, options.MessageCount)
            .Select(_ => Guid.NewGuid())
            .ToArray();

        try
        {
            await PublishBurstAsync(options, runId, messageIds).ConfigureAwait(false);
            var result = await WaitForEffectsAsync(options, runId).ConfigureAwait(false);
            result = result with
            {
                RunId = runId,
                StartedUtc = startedUtc,
                CompletedUtc = DateTimeOffset.UtcNow,
                ExpectedMessages = options.MessageCount
            };

            var passed = result.InventoryInboxCount == options.MessageCount
                && result.NotificationsInboxCount == options.MessageCount
                && result.InventoryEffectCount == options.MessageCount
                && result.NotificationEffectCount == options.MessageCount
                && result.P95Seconds <= options.MaximumP95Seconds;

            result = result with { Status = passed ? "passed" : "failed" };
            await WriteResultAsync(options.ResultPath, result).ConfigureAwait(false);
            return passed ? 0 : 1;
        }
        catch (Exception ex)
        {
            await WriteResultAsync(options.ResultPath, new ProbeResult
            {
                Status = "failed",
                RunId = runId,
                StartedUtc = startedUtc,
                CompletedUtc = DateTimeOffset.UtcNow,
                ExpectedMessages = options.MessageCount,
                Error = ex.ToString()
            }).ConfigureAwait(false);
            await Console.Error.WriteLineAsync(ex.ToString()).ConfigureAwait(false);
            return 1;
        }
    }

    private static async Task PublishBurstAsync(
        ProbeOptions options,
        string runId,
        IReadOnlyCollection<Guid> messageIds)
    {
        await using var client = new ServiceBusClient(options.ServiceBusConnectionString);
        await using var sender = client.CreateSender(options.TopicName);
        using var batch = await sender.CreateMessageBatchAsync().ConfigureAwait(false);

        foreach (var messageId in messageIds)
        {
            var orderReferenceId = Guid.NewGuid();
            var payload = BinaryData.FromObjectAsJson(new
            {
                customerId = 101,
                orderDate = DateTime.UtcNow,
                totalPrice = 100.00m,
                productCount = 1,
                orderReferenceId
            });
            if (payload.ToMemory().Length > MaximumPayloadBytes)
            {
                throw new InvalidOperationException(
                    $"Probe payload exceeded {MaximumPayloadBytes} bytes.");
            }

            var message = new ServiceBusMessage(payload)
            {
                MessageId = messageId.ToString(),
                CorrelationId = runId,
                Subject = "OrderCreatedV1",
                ContentType = "application/json",
                TimeToLive = TimeSpan.FromDays(7)
            };
            message.ApplicationProperties["TenantId"] = options.TenantId;
            message.ApplicationProperties["TenantCode"] = options.TenantCode;
            message.ApplicationProperties["EnvelopeMessageId"] = messageId.ToString();
            message.ApplicationProperties["EventType"] = "OrderCreatedV1";
            message.ApplicationProperties["CorrelationId"] = runId;
            message.ApplicationProperties["CausationId"] = runId;

            if (!batch.TryAddMessage(message))
            {
                await sender.SendMessagesAsync(batch).ConfigureAwait(false);
                batch.Dispose();
                throw new InvalidOperationException(
                    "The configured burst does not fit in one broker batch. Reduce the payload or add chunked batch support.");
            }
        }

        await sender.SendMessagesAsync(batch).ConfigureAwait(false);
        Console.WriteLine($"Published {messageIds.Count} OrderCreatedV1 messages for {runId}.");
    }

    private static async Task<ProbeResult> WaitForEffectsAsync(
        ProbeOptions options,
        string runId)
    {
        var deadline = DateTimeOffset.UtcNow.AddSeconds(options.TimeoutSeconds);
        ProbeResult latest = new() { RunId = runId };

        while (DateTimeOffset.UtcNow < deadline)
        {
            latest = await ReadResultAsync(options.SqlConnectionString, runId).ConfigureAwait(false);
            if (latest.InventoryInboxCount >= options.MessageCount
                && latest.NotificationsInboxCount >= options.MessageCount
                && latest.InventoryEffectCount >= options.MessageCount
                && latest.NotificationEffectCount >= options.MessageCount)
            {
                return latest;
            }

            await Task.Delay(TimeSpan.FromSeconds(2)).ConfigureAwait(false);
        }

        return latest with
        {
            Error = $"Timed out after {options.TimeoutSeconds} seconds waiting for all durable effects."
        };
    }

    private static async Task<ProbeResult> ReadResultAsync(string connectionString, string runId)
    {
        const string sql = """
            SELECT
              SUM(CASE WHEN [ConsumerName] = N'Inventory' THEN 1 ELSE 0 END) AS InventoryInboxCount,
              SUM(CASE WHEN [ConsumerName] = N'Notifications' THEN 1 ELSE 0 END) AS NotificationsInboxCount
            FROM [operations].[ConsumerInboxMessages]
            WHERE [CorrelationId] = @runId;

            SELECT TOP (1)
              PERCENTILE_CONT(0.95) WITHIN GROUP (
                ORDER BY DATEDIFF_BIG(MILLISECOND, [EnqueuedUtc], [ProcessedUtc])
              ) OVER () AS P95Milliseconds
            FROM [operations].[ConsumerInboxMessages]
            WHERE [CorrelationId] = @runId;

            SELECT COUNT(*) FROM [inventory].[InventoryReservations] WHERE [CorrelationId] = @runId;
            SELECT COUNT(*) FROM [notifications].[NotificationDeliveries] WHERE [CorrelationId] = @runId;
            """;

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync().ConfigureAwait(false);
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add(new SqlParameter("@runId", SqlDbType.NVarChar, 128) { Value = runId });

        await using var reader = await command.ExecuteReaderAsync().ConfigureAwait(false);
        var inventoryInbox = 0;
        var notificationsInbox = 0;
        var p95Milliseconds = 0d;
        if (await reader.ReadAsync().ConfigureAwait(false))
        {
            inventoryInbox = await reader.IsDBNullAsync(0).ConfigureAwait(false)
                ? 0
                : Convert.ToInt32(reader.GetValue(0));
            notificationsInbox = await reader.IsDBNullAsync(1).ConfigureAwait(false)
                ? 0
                : Convert.ToInt32(reader.GetValue(1));
        }

        await reader.NextResultAsync().ConfigureAwait(false);
        if (await reader.ReadAsync().ConfigureAwait(false))
        {
            p95Milliseconds = await reader.IsDBNullAsync(0).ConfigureAwait(false)
                ? 0d
                : Convert.ToDouble(reader.GetValue(0));
        }

        await reader.NextResultAsync().ConfigureAwait(false);
        var inventoryEffects = await reader.ReadAsync().ConfigureAwait(false)
            ? reader.GetInt32(0)
            : 0;
        await reader.NextResultAsync().ConfigureAwait(false);
        var notificationEffects = await reader.ReadAsync().ConfigureAwait(false)
            ? reader.GetInt32(0)
            : 0;

        return new ProbeResult
        {
            InventoryInboxCount = inventoryInbox,
            NotificationsInboxCount = notificationsInbox,
            InventoryEffectCount = inventoryEffects,
            NotificationEffectCount = notificationEffects,
            P95Seconds = p95Milliseconds / 1000d
        };
    }

    private static async Task WriteResultAsync(string path, ProbeResult result)
    {
        var directory = Path.GetDirectoryName(Path.GetFullPath(path));
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        await File.WriteAllTextAsync(
            path,
            JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }))
            .ConfigureAwait(false);
    }
}

internal sealed record ProbeResult
{
    public string Status { get; init; } = "running";
    public string? RunId { get; init; }
    public DateTimeOffset StartedUtc { get; init; }
    public DateTimeOffset CompletedUtc { get; init; }
    public int ExpectedMessages { get; init; }
    public int InventoryInboxCount { get; init; }
    public int NotificationsInboxCount { get; init; }
    public int InventoryEffectCount { get; init; }
    public int NotificationEffectCount { get; init; }
    public double P95Seconds { get; init; }
    public string? Error { get; init; }
}

internal sealed record ProbeOptions(
    string ServiceBusConnectionString,
    string SqlConnectionString,
    string TopicName,
    int TenantId,
    string TenantCode,
    int MessageCount,
    int TimeoutSeconds,
    double MaximumP95Seconds,
    string ResultPath,
    string? RunId)
{
    public static ProbeOptions FromArgs(string[] args)
    {
        var values = Parse(args);
        return new ProbeOptions(
            Required(values, "servicebus-connection-string"),
            Required(values, "sql-connection-string"),
            Get(values, "topic", "order-events"),
            int.Parse(Get(values, "tenant-id", "1")),
            Get(values, "tenant-code", "TenantA"),
            int.Parse(Get(values, "message-count", "100")),
            int.Parse(Get(values, "timeout-seconds", "180")),
            double.Parse(Get(values, "maximum-p95-seconds", "30")),
            Required(values, "result-path"),
            values.GetValueOrDefault("run-id"));
    }

    private static Dictionary<string, string> Parse(string[] args)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var index = 0;
        while (index < args.Length)
        {
            if (!args[index].StartsWith("--", StringComparison.Ordinal))
            {
                index++;
                continue;
            }

            var key = args[index][2..];
            index++;
            if (index >= args.Length)
            {
                throw new ArgumentException($"Missing value for --{key}.", nameof(args));
            }

            result[key] = args[index];
            index++;
        }

        return result;
    }

    private static string Required(IReadOnlyDictionary<string, string> values, string key)
        => values.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value)
            ? value
            : throw new ArgumentException($"Missing required argument --{key}.", nameof(values));

    private static string Get(IReadOnlyDictionary<string, string> values, string key, string fallback)
        => values.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value)
            ? value
            : fallback;
}
