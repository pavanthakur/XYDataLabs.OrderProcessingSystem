using System.Data;
using System.Diagnostics;
using System.Globalization;
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
        var lastLoggedSnapshot = new ProbeResult
        {
            InventoryInboxCount = -1,
            NotificationsInboxCount = -1,
            InventoryEffectCount = -1,
            NotificationEffectCount = -1,
            P95Seconds = -1
        };

        while (DateTimeOffset.UtcNow < deadline)
        {
            latest = await ReadResultAsync(options, runId).ConfigureAwait(false);
            if (latest.InventoryInboxCount != lastLoggedSnapshot.InventoryInboxCount
                || latest.NotificationsInboxCount != lastLoggedSnapshot.NotificationsInboxCount
                || latest.InventoryEffectCount != lastLoggedSnapshot.InventoryEffectCount
                || latest.NotificationEffectCount != lastLoggedSnapshot.NotificationEffectCount
                || Math.Abs(latest.P95Seconds - lastLoggedSnapshot.P95Seconds) > double.Epsilon)
            {
                await Console.Out.WriteLineAsync(
                    $"Observed {runId}: inbox={latest.InventoryInboxCount}/{latest.NotificationsInboxCount}, " +
                    $"effects={latest.InventoryEffectCount}/{latest.NotificationEffectCount}, p95={latest.P95Seconds:0.###}s")
                    .ConfigureAwait(false);
                lastLoggedSnapshot = latest;
            }

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

    private static async Task<ProbeResult> ReadResultAsync(ProbeOptions options, string runId)
        => options.SqlReadMode.Equals("docker-compose", StringComparison.OrdinalIgnoreCase)
            ? await ReadResultViaDockerComposeAsync(options, runId).ConfigureAwait(false)
            : await ReadResultViaSqlConnectionAsync(options.SqlConnectionString, runId).ConfigureAwait(false);

    private static async Task<ProbeResult> ReadResultViaSqlConnectionAsync(string connectionString, string runId)
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
              ), 0) AS NotificationEffectCount,
              COALESCE((
                SELECT TOP (1)
                  CONVERT(decimal(18,3), PERCENTILE_CONT(0.95) WITHIN GROUP (
                    ORDER BY DATEDIFF_BIG(MILLISECOND, [EnqueuedUtc], [ProcessedUtc])
                  ) OVER ())
                FROM [operations].[ConsumerInboxMessages] WITH (READUNCOMMITTED)
                WHERE [CorrelationId] = @runId
              ), 0) AS P95Milliseconds;
            """;

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync().ConfigureAwait(false);
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add(new SqlParameter("@runId", SqlDbType.NVarChar, 128) { Value = runId });

        await using var reader = await command.ExecuteReaderAsync().ConfigureAwait(false);
        var inventoryInbox = 0;
        var notificationsInbox = 0;
        var inventoryEffects = 0;
        var notificationEffects = 0;
        var p95Milliseconds = 0d;
        if (await reader.ReadAsync().ConfigureAwait(false))
        {
            inventoryInbox = await reader.IsDBNullAsync(0).ConfigureAwait(false)
                ? 0
                : Convert.ToInt32(reader.GetValue(0));
            notificationsInbox = await reader.IsDBNullAsync(1).ConfigureAwait(false)
                ? 0
                : Convert.ToInt32(reader.GetValue(1));
            inventoryEffects = await reader.IsDBNullAsync(2).ConfigureAwait(false)
                ? 0
                : Convert.ToInt32(reader.GetValue(2));
            notificationEffects = await reader.IsDBNullAsync(3).ConfigureAwait(false)
                ? 0
                : Convert.ToInt32(reader.GetValue(3));
            p95Milliseconds = await reader.IsDBNullAsync(4).ConfigureAwait(false)
                ? 0d
                : Convert.ToDouble(reader.GetValue(4), CultureInfo.InvariantCulture);
        }

        return new ProbeResult
        {
            InventoryInboxCount = inventoryInbox,
            NotificationsInboxCount = notificationsInbox,
            InventoryEffectCount = inventoryEffects,
            NotificationEffectCount = notificationEffects,
            P95Seconds = p95Milliseconds / 1000d
        };
    }

    private static async Task<ProbeResult> ReadResultViaDockerComposeAsync(
        ProbeOptions options,
        string runId)
    {
        var databaseName = new SqlConnectionStringBuilder(options.SqlConnectionString).InitialCatalog;
        var escapedRunId = runId.Replace("'", "''", StringComparison.Ordinal);
        var normalizedQuery = $"""
            SET NOCOUNT ON;
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
            SET LOCK_TIMEOUT 5000;
            DECLARE @runId nvarchar(128) = N'{escapedRunId}';
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
              ), 0) AS NotificationEffectCount,
              COALESCE((
                SELECT TOP (1)
                  CONVERT(decimal(18,3), PERCENTILE_CONT(0.95) WITHIN GROUP (
                    ORDER BY DATEDIFF_BIG(MILLISECOND, [EnqueuedUtc], [ProcessedUtc])
                  ) OVER ())
                FROM [operations].[ConsumerInboxMessages] WITH (READUNCOMMITTED)
                WHERE [CorrelationId] = @runId
              ), 0) AS P95Milliseconds;
            """;

        var shellCommand = $"""
            if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then SQLCMD=/opt/mssql-tools18/bin/sqlcmd; else SQLCMD=/opt/mssql-tools/bin/sqlcmd; fi; "$SQLCMD" -C -S localhost -U sa -P "$SA_PASSWORD" -d "{databaseName.Replace("\"", "\\\"", StringComparison.Ordinal)}" -h -1 -W -s "|" -Q "SET NOCOUNT ON; {normalizedQuery.Replace("\"", "\\\"", StringComparison.Ordinal)}"
            """.Trim();

        var output = await RunDockerComposeCommandAsync(shellCommand).ConfigureAwait(false);
        var lines = output
            .Select(line => line.Trim())
            .Where(line => !string.IsNullOrWhiteSpace(line)
                && !line.StartsWith("(", StringComparison.Ordinal)
                && !line.Contains("rows affected", StringComparison.OrdinalIgnoreCase))
            .ToArray();

        var row = lines.LastOrDefault(line => line.Contains('|', StringComparison.Ordinal));
        if (string.IsNullOrWhiteSpace(row))
        {
            return new ProbeResult { RunId = runId };
        }

        var columns = row.Split('|', StringSplitOptions.TrimEntries);
        if (columns.Length < 5)
        {
            throw new InvalidOperationException(
                $"Unexpected SQL output while reading durable effects for {runId}: {row}");
        }

        return new ProbeResult
        {
            RunId = runId,
            InventoryInboxCount = int.Parse(columns[0], CultureInfo.InvariantCulture),
            NotificationsInboxCount = int.Parse(columns[1], CultureInfo.InvariantCulture),
            InventoryEffectCount = int.Parse(columns[2], CultureInfo.InvariantCulture),
            NotificationEffectCount = int.Parse(columns[3], CultureInfo.InvariantCulture),
            P95Seconds = double.Parse(columns[4], CultureInfo.InvariantCulture) / 1000d
        };
    }

    private static async Task<IReadOnlyList<string>> RunDockerComposeCommandAsync(string shellCommand)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "docker",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        psi.ArgumentList.Add("compose");
        psi.ArgumentList.Add("--env-file");
        psi.ArgumentList.Add(Path.Combine(Directory.GetCurrentDirectory(), "Resources", "Docker", ".env.local.example"));
        psi.ArgumentList.Add("--env-file");
        psi.ArgumentList.Add(Path.Combine(Directory.GetCurrentDirectory(), "Resources", "Docker", ".env.local"));
        psi.ArgumentList.Add("-f");
        psi.ArgumentList.Add(Path.Combine(Directory.GetCurrentDirectory(), "compose", "docker-compose.phase10.yml"));
        psi.ArgumentList.Add("--profile");
        psi.ArgumentList.Add("data");
        psi.ArgumentList.Add("--profile");
        psi.ArgumentList.Add("identity");
        psi.ArgumentList.Add("--profile");
        psi.ArgumentList.Add("storage");
        psi.ArgumentList.Add("--profile");
        psi.ArgumentList.Add("messaging");
        psi.ArgumentList.Add("--profile");
        psi.ArgumentList.Add("apps");
        psi.ArgumentList.Add("--profile");
        psi.ArgumentList.Add("functions");
        psi.ArgumentList.Add("exec");
        psi.ArgumentList.Add("-T");
        psi.ArgumentList.Add("sql-server");
        psi.ArgumentList.Add("/bin/sh");
        psi.ArgumentList.Add("-lc");
        psi.ArgumentList.Add(shellCommand);

        using var process = Process.Start(psi)
            ?? throw new InvalidOperationException("Failed to start docker compose exec for SQL probe.");

        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync().ConfigureAwait(false);
        var stdout = await stdoutTask.ConfigureAwait(false);
        var stderr = await stderrTask.ConfigureAwait(false);
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(
                $"docker compose exec sql-server failed with exit code {process.ExitCode}. {stderr}".Trim());
        }

        return stdout
            .Split(new[] { "\r\n", "\n" }, StringSplitOptions.None)
            .Select(line => line.Trim())
            .Where(line => !string.IsNullOrWhiteSpace(line))
            .ToArray();
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
    string SqlReadMode,
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
            Required(values, "servicebus-connection-string", "PHASE10_NFR_SERVICEBUS_CONNECTION_STRING"),
            Required(values, "sql-connection-string", "PHASE10_NFR_SQL_CONNECTION_STRING"),
            Get(values, "sql-read-mode", Environment.GetEnvironmentVariable("PHASE10_NFR_SQL_READ_MODE") ?? "docker-compose"),
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

    private static string Required(
        IReadOnlyDictionary<string, string> values,
        string key,
        string? environmentVariable = null)
        => values.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value)
            ? value
            : !string.IsNullOrWhiteSpace(environmentVariable)
                && !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(environmentVariable))
                    ? Environment.GetEnvironmentVariable(environmentVariable)!
            : throw new ArgumentException($"Missing required argument --{key}.", nameof(values));

    private static string Get(IReadOnlyDictionary<string, string> values, string key, string fallback)
        => values.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value)
            ? value
            : fallback;
}
