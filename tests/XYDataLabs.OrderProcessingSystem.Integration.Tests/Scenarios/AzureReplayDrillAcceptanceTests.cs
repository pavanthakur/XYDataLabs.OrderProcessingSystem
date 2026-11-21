using System.Diagnostics;
using System.Text.Json;
using Azure.Core;
using Azure.Identity;
using Azure.Messaging.ServiceBus;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Functions;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

// This test is skipped during ordinary integration runs. It can run only when an
// operator has explicitly opted in and the scoped drill controller is in `routed` state.
[Collection("AzureReplayDrillSerial")]
public sealed class AzureReplayDrillAcceptanceTests
{
    private const string EnableValue = "I_APPROVE_AZURE_DEV_REPLAY_DRILL";
    private static readonly TimeSpan ReceiveTimeout = TimeSpan.FromSeconds(60);
    private static readonly TimeSpan EffectTimeout = TimeSpan.FromSeconds(120);

    [AzureReplayDrillFact]
    public async Task RunOneSelectedAzureDevReplayFailureScenario()
    {
        var settings = ReplayDrillSettings.Load();
        await VerifySelectedSubscriptionAsync(settings.ExpectedSubscriptionId, settings.RunnerPrincipalObjectId);
        var target = LoadDevTarget();
        settings.ValidateTarget(target);
        ValidateEvidenceFiles(settings, target);
        await VerifyLiveRoutingAsync(settings, target);

        var credential = new AzureCliCredential();
        await using var sql = await OpenSqlAsync(target, target.OperationsDatabaseName, credential);
        var operationsOptions = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>().UseSqlServer(sql).Options;

        await using var operationsContext = new OrderProcessingSystemDbContext(operationsOptions);
        var request = await operationsContext.DlqReplayRequests
            .AsNoTracking()
            .Include(item => item.Quarantine)
            .SingleOrDefaultAsync(item => item.Id == settings.ReplayRequestId)
            ?? throw new InvalidOperationException("Selected approved replay request was not found in the configured operations database.");

        var quarantine = request.Quarantine;
        var tenantId = quarantine.TenantId
            ?? throw new InvalidOperationException("Replay quarantine is missing its tenant identity.");
        if (request.ProcessedUtc is not null || quarantine.State != DlqQuarantineStates.Approved ||
            request.PublishedUtc is null || request.QuarantineId == Guid.Empty)
        {
            throw new InvalidOperationException("Replay request must be published, approved, unprocessed, and linked to a quarantine record.");
        }

        await VerifyTenantAndBusinessDatabaseAsync(sql, target, settings, tenantId, credential);
        var businessIdentity = ReadBusinessIdentity(quarantine);
        var eventMessageId = businessIdentity.MessageId;
        var orderReferenceId = businessIdentity.OrderReferenceId;
        var beforeEffects = await ReadDurableEffectCountsAsync(
            target, settings.BusinessDatabaseName, tenantId, eventMessageId, orderReferenceId, credential);
        beforeEffects.InventoryInbox.Should().Be(0);
        beforeEffects.NotificationInbox.Should().Be(0);
        beforeEffects.InventoryReservations.Should().Be(0);
        beforeEffects.NotificationDeliveries.Should().Be(0, "the selected fixture must be unique and not previously delivered");
        var drillStartedUtc = DateTimeOffset.UtcNow;
        var reportPath = CreatePendingJournal(settings, target, tenantId, request.Id, quarantine.Id);

        var runId = settings.RunId;
        var drillTarget = new ReplayDrillTarget(
            "dev",
            target.ServiceBusFullyQualifiedNamespace,
            target.OrderEventsTopicName,
            target.ReplayRequestQueueName,
            target.ReplayDrillRequestQueueName,
            runId,
            quarantine.Id,
            request.Id);

        await using var serviceBusClient = drillTarget.CreateClient(credential);
        await using var receiver = drillTarget.CreateRequestReceiver(serviceBusClient);
        await using var sender = drillTarget.CreateBusinessTopicSender(serviceBusClient);
        var publisher = new ReplayDrillPublisher(
            drillTarget,
            sender,
            failAfterAcceptedSend: settings.Scenario == ReplayDrillScenario.SendAcceptedBeforeCheckpoint);
        using var provider = BuildFunctionProvider(sql, publisher, drillTarget.BusinessTopic, drillTarget.RequestQueue);
        var function = new DlqReplayFunction(provider, TimeProvider.System, NullLogger<DlqReplayFunction>.Instance);

        var firstDelivery = await ReceiveOwnedRequestAsync(receiver, drillTarget, request.Id, quarantine.Id);
        var firstDeliveryCount = firstDelivery.DeliveryCount;
        var injectedSettlementFault = settings.Scenario == ReplayDrillScenario.ProcessedCheckpoint
            ? new ReplayDrillSettlementFault()
            : null;

        if (settings.Scenario == ReplayDrillScenario.ProcessedCheckpoint)
        {
            var actions = new ReplayDrillSettlement(drillTarget, receiver, firstDelivery, injectedSettlementFault);
            var exception = await Record.ExceptionAsync(() => function.RunCoreAsync(firstDelivery, actions, CancellationToken.None));
            exception.Should().BeOfType<ReplayDrillBoundaryException>()
                .Which.Message.Should().Be("checkpoint-before-settlement");
        }
        else
        {
            var actions = new ReplayDrillSettlement(drillTarget, receiver, firstDelivery);
            var exception = await Record.ExceptionAsync(() => function.RunCoreAsync(firstDelivery, actions, CancellationToken.None));
            exception.Should().BeOfType<ReplayDrillBoundaryException>()
                .Which.Message.Should().Be("send-accepted-before-checkpoint");
            await receiver.AbandonMessageAsync(firstDelivery);
        }

        var redelivery = await ReceiveOwnedRequestAsync(receiver, drillTarget, request.Id, quarantine.Id);
        redelivery.DeliveryCount.Should().BeGreaterThan(firstDeliveryCount);
        var redeliveryActions = new ReplayDrillSettlement(drillTarget, receiver, redelivery);
        await function.RunCoreAsync(redelivery, redeliveryActions, CancellationToken.None);
        redeliveryActions.Completed.Should().BeTrue();

        var publishedIds = publisher.PublishedTransportMessageIds;
        if (settings.Scenario == ReplayDrillScenario.ProcessedCheckpoint)
        {
            publishedIds.Should().ContainSingle();
        }
        else
        {
            publishedIds.Should().HaveCount(2);
            publishedIds[0].Should().NotBe(publishedIds[1], "the second transport ID must bypass broker deduplication so consumers receive it");
            publisher.PublishedEnvelopeMessageIds.Should().Equal(eventMessageId.ToString("D"), eventMessageId.ToString("D"));
        }

        long pendingReplayRequestCount;
        await using (var verifyContext = new OrderProcessingSystemDbContext(operationsOptions))
        {
            var finalRequest = await verifyContext.DlqReplayRequests.AsNoTracking()
                .SingleAsync(item => item.Id == request.Id);
            var finalQuarantine = await verifyContext.DlqQuarantineRecords.AsNoTracking()
                .SingleAsync(item => item.Id == quarantine.Id);
            finalRequest.ProcessedUtc.Should().NotBeNull();
            finalQuarantine.State.Should().Be(DlqQuarantineStates.Replayed);
            pendingReplayRequestCount = await verifyContext.DlqReplayRequests
                .LongCountAsync(item => item.ProcessedUtc == null);
        }
        if (pendingReplayRequestCount != 0)
        {
            throw new InvalidOperationException("Other approved replay requests remain unprocessed; do not restore the normal publisher automatically. Use the documented safe restoration path after review.");
        }

        var afterEffects = await PollForDurableEffectsAsync(
            target, settings, tenantId, eventMessageId, orderReferenceId, credential);
        afterEffects.InventoryInbox.Should().Be(1);
        afterEffects.NotificationInbox.Should().Be(1);
        afterEffects.InventoryReservations.Should().Be(1);
        afterEffects.NotificationDeliveries.Should().Be(1);

        (long InventoryDuplicateTraces, long NotificationDuplicateTraces)? duplicateTraces = null;
        if (settings.Scenario == ReplayDrillScenario.SendAcceptedBeforeCheckpoint)
        {
            publishedIds.Should().HaveCount(2);
            publishedIds[0].Should().NotBe(publishedIds[1], "the test bypasses topic-level duplicate detection to exercise consumer inbox idempotency");
            publisher.PublishedEnvelopeMessageIds.Should().Equal(eventMessageId.ToString("D"), eventMessageId.ToString("D"));
            duplicateTraces = await PollForConsumerDuplicateTracesAsync(target, eventMessageId, drillStartedUtc);
            duplicateTraces.Value.InventoryDuplicateTraces.Should().BeGreaterThan(0);
            duplicateTraces.Value.NotificationDuplicateTraces.Should().BeGreaterThan(0);
        }

        WriteSanitizedReport(reportPath, settings, tenantId, eventMessageId, orderReferenceId, publishedIds.Count, afterEffects, duplicateTraces, pendingReplayRequestCount);
    }

    private static ServiceProvider BuildFunctionProvider(
        SqlConnection operationsConnection,
        IDlqReplayPublisher publisher,
        string topicName,
        string requestQueue)
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton(TimeProvider.System);
        services.AddSingleton<IIntegrationEventTypeResolver>(_ => FunctionEventContracts.CreateResolver());
        services.AddSingleton(publisher);
        services.AddSingleton<IDlqReplayPublisher>(publisher);
        services.AddDbContext<OrderProcessingSystemDbContext>(options => options.UseSqlServer(operationsConnection));
        services.AddSingleton<IOptions<ServiceBusOptions>>(Options.Create(new ServiceBusOptions
        {
            Enabled = true,
            ReplayEnabled = true,
            MaxReplayAttempts = 5,
            TopicName = topicName,
            ReplayRequestQueueName = requestQueue
        }));
        return services.BuildServiceProvider();
    }

    private static async Task<ServiceBusReceivedMessage> ReceiveOwnedRequestAsync(
        ServiceBusReceiver receiver,
        ReplayDrillTarget target,
        Guid requestId,
        Guid quarantineId)
    {
        using var timeout = new CancellationTokenSource(ReceiveTimeout);
        while (!timeout.IsCancellationRequested)
        {
            var message = await receiver.ReceiveMessageAsync(TimeSpan.FromSeconds(5), timeout.Token);
            if (message is null) continue;
            if (message.MessageId != requestId.ToString("D") ||
                !message.ApplicationProperties.TryGetValue("ReplayRequestId", out var actualRequest) ||
                !Guid.TryParse(Convert.ToString(actualRequest), out var parsedRequest) || parsedRequest != requestId ||
                !message.ApplicationProperties.TryGetValue("QuarantineId", out var actualQuarantine) ||
                !Guid.TryParse(Convert.ToString(actualQuarantine), out var parsedQuarantine) || parsedQuarantine != quarantineId)
            {
                await receiver.AbandonMessageAsync(message, cancellationToken: CancellationToken.None);
                throw new InvalidOperationException("Isolated replay queue contained a message not owned by this run; it was abandoned and not processed.");
            }

            target.ValidateFixture(message.ApplicationProperties);
            return message;
        }

        throw new TimeoutException("Approved replay request did not arrive on the isolated queue within 60 seconds.");
    }

    private static async Task<SqlConnection> OpenSqlAsync(ReplayDrillRuntimeTarget target, string database, TokenCredential credential)
    {
        var builder = new SqlConnectionStringBuilder
        {
            DataSource = $"tcp:{target.SqlServerName}.database.windows.net,1433",
            InitialCatalog = database,
            Encrypt = true,
            TrustServerCertificate = false,
            ConnectTimeout = 30,
            ApplicationName = "Phase10-Azure-Dev-Replay-Drill"
        };
        var connection = new SqlConnection(builder.ConnectionString)
        {
            AccessToken = (await credential.GetTokenAsync(
                new TokenRequestContext(["https://database.windows.net/.default"]), CancellationToken.None)).Token
        };
        await connection.OpenAsync();
        var actual = connection.Database;
        if (!string.Equals(actual, database, StringComparison.OrdinalIgnoreCase))
        {
            await connection.DisposeAsync();
            throw new InvalidOperationException("Azure SQL connected to a database other than the explicitly selected target.");
        }

        return connection;
    }

    private static async Task VerifyTenantAndBusinessDatabaseAsync(
        SqlConnection operationsConnection,
        ReplayDrillRuntimeTarget target,
        ReplayDrillSettings settings,
        int expectedTenantId,
        TokenCredential credential)
    {
        await using var command = operationsConnection.CreateCommand();
        command.CommandText = "SELECT Id, Code, TenantTier, Status FROM dbo.Tenants WHERE Id=@id AND Code=@code;";
        command.Parameters.AddWithValue("@id", expectedTenantId);
        command.Parameters.AddWithValue("@code", settings.TenantCode);
        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync()) throw new InvalidOperationException("Tenant registry identity did not match the approved replay fixture.");
        var tenantCode = reader.GetString(reader.GetOrdinal("Code"));
        var tier = reader.GetString(reader.GetOrdinal("TenantTier"));
        var status = reader.GetString(reader.GetOrdinal("Status"));
        if (await reader.ReadAsync() || status != "Active" || tier is not ("SharedPool" or "Dedicated"))
        {
            throw new InvalidOperationException("Replay tenant must be one active, supported tenant registry row.");
        }

        if (tier == "SharedPool" && settings.BusinessDatabaseName != target.OperationsDatabaseName)
        {
            throw new InvalidOperationException("Shared-pool replay verification must use the shared operations/business database.");
        }

        if (tier == "Dedicated" && settings.BusinessDatabaseName == target.OperationsDatabaseName)
        {
            throw new InvalidOperationException("Dedicated tenant replay verification must use its explicitly selected dedicated database.");
        }

        if (tier == "Dedicated")
        {
            var configuredDatabase = await ResolveDedicatedDatabaseNameAsync(
                target, settings.ExpectedSubscriptionId, tenantCode);
            if (!string.Equals(configuredDatabase, settings.BusinessDatabaseName, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("Selected dedicated business database does not match the tenant's configured Key Vault connection reference.");
            }
        }

        await using var businessConnection = await OpenSqlAsync(target, settings.BusinessDatabaseName, credential);
        await using var businessIdentity = businessConnection.CreateCommand();
        businessIdentity.CommandText = "SELECT COUNT_BIG(*) FROM dbo.Tenants WHERE Id=@id AND Code=@code AND TenantTier=@tier AND Status='Active';";
        businessIdentity.Parameters.AddWithValue("@id", expectedTenantId);
        businessIdentity.Parameters.AddWithValue("@code", tenantCode);
        businessIdentity.Parameters.AddWithValue("@tier", tier);
        var matches = Convert.ToInt64(await businessIdentity.ExecuteScalarAsync());
        if (matches != 1) throw new InvalidOperationException("Selected business database does not contain the authoritative tenant identity.");
    }

    private static (Guid MessageId, Guid OrderReferenceId) ReadBusinessIdentity(DlqQuarantineRecord quarantine)
    {
        using var properties = JsonDocument.Parse(quarantine.ApplicationPropertiesJson);
        if (!properties.RootElement.TryGetProperty("EnvelopeMessageId", out var messageIdElement) ||
            !Guid.TryParse(messageIdElement.ToString(), out var messageId) ||
            !properties.RootElement.TryGetProperty("TenantId", out var tenantElement) ||
            !int.TryParse(tenantElement.ToString(), out var tenantId) || tenantId != quarantine.TenantId)
        {
            throw new InvalidOperationException("Replay quarantine metadata must include the stable envelope ID and matching tenant ID.");
        }

        using var payload = JsonDocument.Parse(quarantine.Body);
        if (!payload.RootElement.TryGetProperty("orderReferenceId", out var orderElement) ||
            !Guid.TryParse(orderElement.ToString(), out var orderReferenceId))
        {
            throw new InvalidOperationException("Replay event must carry an explicit order reference for downstream effect correlation.");
        }

        return (messageId, orderReferenceId);
    }

    private static async Task<DurableEffectCounts> ReadDurableEffectCountsAsync(
        ReplayDrillRuntimeTarget target,
        string database,
        int tenantId,
        Guid messageId,
        Guid orderReferenceId,
        TokenCredential credential)
    {
        await using var connection = await OpenSqlAsync(target, database, credential);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT
              (SELECT COUNT_BIG(*) FROM operations.ConsumerInboxMessages WHERE TenantId=@tenantId AND ConsumerName='Inventory' AND MessageId=@messageId AND ProcessedUtc IS NOT NULL) AS InventoryInbox,
              (SELECT COUNT_BIG(*) FROM operations.ConsumerInboxMessages WHERE TenantId=@tenantId AND ConsumerName='Notifications' AND MessageId=@messageId AND ProcessedUtc IS NOT NULL) AS NotificationInbox,
              (SELECT COUNT_BIG(*) FROM inventory.InventoryReservations WHERE TenantId=@tenantId AND OrderReferenceId=@orderReferenceId) AS InventoryReservations,
              (SELECT COUNT_BIG(*) FROM notifications.NotificationDeliveries WHERE TenantId=@tenantId AND OrderReferenceId=@orderReferenceId) AS NotificationDeliveries;
            """;
        command.Parameters.AddWithValue("@tenantId", tenantId);
        command.Parameters.AddWithValue("@messageId", messageId);
        command.Parameters.AddWithValue("@orderReferenceId", orderReferenceId);
        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync()) throw new InvalidOperationException("Could not query replay downstream effects.");
        return new DurableEffectCounts(
            Convert.ToInt64(reader["InventoryInbox"]),
            Convert.ToInt64(reader["NotificationInbox"]),
            Convert.ToInt64(reader["InventoryReservations"]),
            Convert.ToInt64(reader["NotificationDeliveries"]));
    }

    private static async Task<DurableEffectCounts> PollForDurableEffectsAsync(
        ReplayDrillRuntimeTarget target,
        ReplayDrillSettings settings,
        int tenantId,
        Guid messageId,
        Guid orderReferenceId,
        TokenCredential credential)
    {
        var deadline = DateTimeOffset.UtcNow + EffectTimeout;
        while (DateTimeOffset.UtcNow < deadline)
        {
            var counts = await ReadDurableEffectCountsAsync(target, settings.BusinessDatabaseName, tenantId, messageId, orderReferenceId, credential);
            if (counts.IsExactlyOnce) return counts;
            await Task.Delay(TimeSpan.FromSeconds(3));
        }

        throw new TimeoutException("Downstream Inventory and Notifications effects did not become visible in 120 seconds.");
    }

    private static async Task VerifySelectedSubscriptionAsync(string expectedSubscriptionId, string expectedPrincipalObjectId)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo("az")
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            }
        };
        foreach (var argument in new[] { "account", "show", "--query", "{id:id,state:state}", "-o", "json" })
            process.StartInfo.ArgumentList.Add(argument);
        if (!process.Start()) throw new InvalidOperationException("Could not start Azure CLI to verify the signed-in subscription.");
        var outputTask = process.StandardOutput.ReadToEndAsync();
        var errorTask = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        var output = await outputTask;
        _ = await errorTask;
        if (process.ExitCode != 0) throw new InvalidOperationException("Azure CLI account verification failed; no Azure operation was attempted.");
        using var account = JsonDocument.Parse(output);
        if (account.RootElement.GetProperty("id").GetString() != expectedSubscriptionId ||
            account.RootElement.GetProperty("state").GetString() != "Enabled")
        {
            throw new InvalidOperationException("Signed-in Azure CLI subscription does not match the explicitly approved enabled subscription.");
        }

        using var identityProcess = new Process
        {
            StartInfo = new ProcessStartInfo("az")
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            }
        };
        foreach (var argument in new[] { "ad", "signed-in-user", "show", "--query", "id", "-o", "tsv" })
            identityProcess.StartInfo.ArgumentList.Add(argument);
        if (!identityProcess.Start()) throw new InvalidOperationException("Could not verify the Azure CLI operator identity.");
        var identityOutputTask = identityProcess.StandardOutput.ReadToEndAsync();
        var identityErrorTask = identityProcess.StandardError.ReadToEndAsync();
        await identityProcess.WaitForExitAsync();
        var actualObjectId = (await identityOutputTask).Trim();
        _ = await identityErrorTask;
        if (identityProcess.ExitCode != 0 || !string.Equals(actualObjectId, expectedPrincipalObjectId, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Signed-in user does not match the dedicated replay-drill principal verified by preflight.");
    }

    private static ReplayDrillRuntimeTarget LoadDevTarget()
    {
        var root = FindRepositoryRoot();
        using var catalog = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "automation", "config", "runtime-targets.json")));
        var targets = catalog.RootElement.GetProperty("targets").EnumerateArray()
            .Where(item => item.GetProperty("key").GetString() == "azure-dev").ToArray();
        if (targets.Length != 1) throw new InvalidOperationException("Runtime-target catalog must define exactly one azure-dev replay target.");
        var target = targets[0];
        return new ReplayDrillRuntimeTarget(
            root,
            target.GetProperty("azureResourceGroupName").GetString()!,
            target.GetProperty("azureSqlServerName").GetString()!,
            target.GetProperty("azureKeyVaultName").GetString()!,
            target.GetProperty("azureOperationsDatabaseName").GetString()!,
            target.GetProperty("azureServiceBusNamespaceName").GetString()!,
            target.GetProperty("azureServiceBusFullyQualifiedNamespace").GetString()!,
            target.GetProperty("azureOrderEventsTopicName").GetString()!,
            target.GetProperty("azureReplayRequestQueueName").GetString()!,
            target.GetProperty("azureReplayDrillRequestQueueName").GetString()!,
            target.GetProperty("azureApplicationInsightsName").GetString()!,
            target.GetProperty("azureOrdersContainerAppName").GetString()!,
            target.GetProperty("azurePaymentsContainerAppName").GetString()!,
            target.GetProperty("azureInventoryContainerAppName").GetString()!,
            target.GetProperty("azureNotificationsContainerAppName").GetString()!,
            target.GetProperty("azureFunctionAppName").GetString()!);
    }

    private static async Task VerifyLiveRoutingAsync(ReplayDrillSettings settings, ReplayDrillRuntimeTarget target)
    {
        foreach (var app in new[]
        {
            (target.OrdersApp, true), (target.PaymentsApp, false),
            (target.InventoryApp, false), (target.NotificationsApp, false)
        })
        {
            var json = await RunAzureCliJsonAsync(
                "containerapp", "show", "--subscription", settings.ExpectedSubscriptionId,
                "--resource-group", target.ResourceGroup, "--name", app.Item1, "-o", "json");
            using var document = JsonDocument.Parse(json);
            var properties = document.RootElement.GetProperty("properties");
            if (properties.GetProperty("runningStatus").GetString() != "Running")
                throw new InvalidOperationException("Replay publisher is not running; no request will be consumed.");
            var container = properties.GetProperty("template").GetProperty("containers")[0];
            var liveRevision = properties.GetProperty("latestReadyRevisionName").GetString();
            var liveImage = container.GetProperty("image").GetString();
            using var manifest = JsonDocument.Parse(await File.ReadAllTextAsync(settings.ConfigManifestPath));
            var publisherKey = app.Item1 switch
            {
                var name when name == target.OrdersApp => "orders",
                var name when name == target.PaymentsApp => "payments",
                var name when name == target.InventoryApp => "inventory",
                var name when name == target.NotificationsApp => "notifications",
                _ => throw new InvalidOperationException("Unexpected replay publisher target.")
            };
            var saved = manifest.RootElement.GetProperty("originalStates").GetProperty(publisherKey);
            if (string.IsNullOrWhiteSpace(liveRevision) ||
                liveImage != saved.GetProperty("image").GetString() ||
                liveImage is null || !System.Text.RegularExpressions.Regex.IsMatch(liveImage, "@sha256:[a-f0-9]{64}$"))
                throw new InvalidOperationException("Live publisher image drifted from the exact replay recovery snapshot or has no ready revision.");
            var env = container.GetProperty("env").EnumerateArray()
                .Where(item => item.TryGetProperty("name", out _))
                .ToDictionary(item => item.GetProperty("name").GetString()!, item => item.TryGetProperty("value", out var value) ? value.GetString() : null, StringComparer.Ordinal);
            var isOrders = app.Item1 == target.OrdersApp;
            if (env.GetValueOrDefault("ServiceBus__ReplayEnabled") != (isOrders ? "true" : "false") ||
                env.GetValueOrDefault("ServiceBus__ReplayRequestQueueName") != (isOrders ? target.ReplayDrillRequestQueueName : target.ReplayRequestQueueName) ||
                (isOrders && env.GetValueOrDefault("ServiceBus__ReplayRequestId") != settings.ReplayRequestId.ToString("D")) ||
                (!isOrders && !string.IsNullOrEmpty(env.GetValueOrDefault("ServiceBus__ReplayRequestId"))))
                throw new InvalidOperationException("Live replay publisher configuration differs from the single-request isolated drill plan.");
        }

        var functionSettings = await RunAzureCliJsonAsync(
            "functionapp", "config", "appsettings", "list", "--subscription", settings.ExpectedSubscriptionId,
            "--resource-group", target.ResourceGroup, "--name", target.FunctionApp,
            "--query", "[?name=='ServiceBus__ReplayRequestQueueName' || name=='Phase10ReplayRequestQueueName'].{name:name,value:value}", "-o", "json");
        using var functionDocument = JsonDocument.Parse(functionSettings);
        var functionQueues = functionDocument.RootElement.EnumerateArray()
            .Select(item => item.GetProperty("value").GetString()).ToArray();
        if (functionQueues.Length == 0 || functionQueues.Any(queue => queue != target.ReplayRequestQueueName))
            throw new InvalidOperationException("Every configured deployed Function replay trigger key must resolve only to the normal queue.");
    }

    private static async Task<string> RunAzureCliJsonAsync(params string[] arguments)
    {
        using var process = new Process { StartInfo = new ProcessStartInfo("az") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true } };
        foreach (var argument in arguments) process.StartInfo.ArgumentList.Add(argument);
        if (!process.Start()) throw new InvalidOperationException("Could not start Azure CLI for read-only replay target verification.");
        var outputTask = process.StandardOutput.ReadToEndAsync();
        var errorTask = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        var output = await outputTask;
        _ = await errorTask;
        if (process.ExitCode != 0) throw new InvalidOperationException("Read-only Azure target verification failed; no queue message was received.");
        return output;
    }

    private static async Task<string> ResolveDedicatedDatabaseNameAsync(
        ReplayDrillRuntimeTarget target,
        string subscriptionId,
        string tenantCode)
    {
        var secretName = $"DedicatedTenantConnectionStrings--{tenantCode}";
        var rawConnectionString = await RunAzureCliTextAsync(
            "keyvault", "secret", "show",
            "--subscription", subscriptionId,
            "--vault-name", target.KeyVaultName,
            "--name", secretName,
            "--query", "value",
            "--output", "tsv",
            "--only-show-errors");
        return ResolveDedicatedDatabaseName(rawConnectionString, target.SqlServerName);
    }

    internal static string ResolveDedicatedDatabaseName(string connectionString, string expectedSqlServerName)
    {
        if (string.IsNullOrWhiteSpace(connectionString) || string.IsNullOrWhiteSpace(expectedSqlServerName))
            throw new InvalidOperationException("Dedicated tenant database reference is missing.");

        try
        {
            var parsed = new SqlConnectionStringBuilder(connectionString);
            var server = parsed.DataSource.Trim();
            if (server.StartsWith("tcp:", StringComparison.OrdinalIgnoreCase)) server = server[4..];
            server = server.Split(',')[0].Trim().TrimEnd('.');
            var expectedServer = $"{expectedSqlServerName}.database.windows.net";
            if (!string.Equals(server, expectedServer, StringComparison.OrdinalIgnoreCase) ||
                string.IsNullOrWhiteSpace(parsed.InitialCatalog) ||
                !System.Text.RegularExpressions.Regex.IsMatch(parsed.InitialCatalog, "^[A-Za-z0-9_]{1,128}$"))
            {
                throw new InvalidOperationException("Dedicated tenant connection reference does not resolve to the approved Azure SQL server and a valid database name.");
            }

            return parsed.InitialCatalog;
        }
        catch (ArgumentException)
        {
            throw new InvalidOperationException("Dedicated tenant connection reference is malformed.");
        }
    }

    private static async Task<string> RunAzureCliTextAsync(params string[] arguments)
    {
        using var process = new Process { StartInfo = new ProcessStartInfo("az") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true } };
        foreach (var argument in arguments) process.StartInfo.ArgumentList.Add(argument);
        if (!process.Start()) throw new InvalidOperationException("Could not start Azure CLI for a read-only tenant configuration lookup.");
        var outputTask = process.StandardOutput.ReadToEndAsync();
        var errorTask = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        var output = (await outputTask).Trim();
        _ = await errorTask;
        if (process.ExitCode != 0 || string.IsNullOrWhiteSpace(output))
            throw new InvalidOperationException("Could not resolve the selected tenant's dedicated database reference; no queue message was received.");
        return output;
    }

    private static async Task<(long Inventory, long Notifications)> PollForConsumerDuplicateTracesAsync(
        ReplayDrillRuntimeTarget target,
        Guid envelopeMessageId,
        DateTimeOffset sinceUtc)
    {
        var deadline = DateTimeOffset.UtcNow + EffectTimeout;
        while (DateTimeOffset.UtcNow < deadline)
        {
            var inventory = await QueryDuplicateTraceCountAsync(target, "Inventory", envelopeMessageId, sinceUtc);
            var notifications = await QueryDuplicateTraceCountAsync(target, "Notifications", envelopeMessageId, sinceUtc);
            if (inventory > 0 && notifications > 0) return (inventory, notifications);
            await Task.Delay(TimeSpan.FromSeconds(5));
        }

        throw new TimeoutException("Both real consumers must emit duplicate-inbox telemetry within 120 seconds; SQL row counts alone do not prove the duplicate reached them.");
    }

    private static async Task<long> QueryDuplicateTraceCountAsync(
        ReplayDrillRuntimeTarget target,
        string consumer,
        Guid envelopeMessageId,
        DateTimeOffset sinceUtc)
    {
        var safeConsumer = consumer is "Inventory" or "Notifications"
            ? consumer
            : throw new ArgumentOutOfRangeException(nameof(consumer));
        var timestamp = sinceUtc.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ", System.Globalization.CultureInfo.InvariantCulture);
        var query = $"traces | where timestamp >= datetime({timestamp}) | where message contains 'ignored duplicate message' | where message contains '{safeConsumer}' | where message contains '{envelopeMessageId:D}' | summarize duplicateTraceCount=count()";
        var json = await RunAzureCliJsonAsync(
            "monitor", "app-insights", "query",
            "--app", target.ApplicationInsightsName,
            "--resource-group", target.ResourceGroup,
            "--analytics-query", query,
            "--offset", "30m",
            "--only-show-errors",
            "--output", "json");
        using var document = JsonDocument.Parse(json);
        if (!document.RootElement.TryGetProperty("tables", out var tables) || tables.GetArrayLength() != 1)
            throw new InvalidOperationException("Application Insights duplicate-trace query returned an unexpected response; acceptance remains incomplete.");
        var rows = tables[0].GetProperty("rows");
        if (rows.GetArrayLength() == 0) return 0;
        if (rows.GetArrayLength() != 1 || rows[0].GetArrayLength() != 1 || !rows[0][0].TryGetInt64(out var count))
            throw new InvalidOperationException("Application Insights duplicate-trace query returned malformed counts.");
        return count;
    }

    private static void ValidateEvidenceFiles(ReplayDrillSettings settings, ReplayDrillRuntimeTarget target)
    {
        ValidateEvidencePath(target, settings.PreflightReportPath);
        ValidateEvidencePath(target, settings.ConfigManifestPath);
        using var preflight = JsonDocument.Parse(File.ReadAllText(settings.PreflightReportPath));
        var preflightRoot = preflight.RootElement;
        if (preflightRoot.GetProperty("status").GetString() != "PASS" ||
            preflightRoot.GetProperty("subscriptionId").GetString() != settings.ExpectedSubscriptionId ||
            preflightRoot.GetProperty("runnerPrincipalObjectId").GetString() != settings.RunnerPrincipalObjectId ||
            !preflightRoot.GetProperty("subscriptionVerified").GetBoolean())
            throw new InvalidOperationException("A passing, subscription-bound replay preflight report is required.");
        var checkedUtc = preflightRoot.GetProperty("checkedUtc").GetDateTimeOffset();
        var now = DateTimeOffset.UtcNow;
        if (checkedUtc > now.AddMinutes(5) || now - checkedUtc > TimeSpan.FromMinutes(60))
            throw new InvalidOperationException("Replay preflight report is stale; rerun the read-only preflight before the drill.");

        using var manifest = JsonDocument.Parse(File.ReadAllText(settings.ConfigManifestPath));
        var manifestRoot = manifest.RootElement;
        if (manifestRoot.GetProperty("status").GetString() != "routed" ||
            manifestRoot.GetProperty("environment").GetString() != "dev" ||
            manifestRoot.GetProperty("subscriptionId").GetString() != settings.ExpectedSubscriptionId ||
            manifestRoot.GetProperty("replayRequestId").GetString() != settings.ReplayRequestId.ToString("D"))
            throw new InvalidOperationException("Replay config manifest is not the routed, exact-request dev manifest.");
        var routedUtc = manifestRoot.GetProperty("updatedUtc").GetDateTimeOffset();
        if (routedUtc > now.AddMinutes(5) || now - routedUtc > TimeSpan.FromMinutes(60))
            throw new InvalidOperationException("Replay route manifest is stale; repeat the reviewed pause/route verification before the drill.");

        var originalStates = manifestRoot.GetProperty("originalStates");
        foreach (var (publisherKey, appName) in new[]
        {
            ("orders", target.OrdersApp), ("payments", target.PaymentsApp),
            ("inventory", target.InventoryApp), ("notifications", target.NotificationsApp)
        })
        {
            if (!originalStates.TryGetProperty(publisherKey, out var original) ||
                string.IsNullOrWhiteSpace(original.GetProperty("revision").GetString()) ||
                original.GetProperty("image").GetString() is not { } image ||
                !System.Text.RegularExpressions.Regex.IsMatch(image, "@sha256:[a-f0-9]{64}$"))
                throw new InvalidOperationException("Recovery manifest must contain each publisher's immutable image and original revision.");
            var recorded = preflightRoot.GetProperty("applicationRevisions").EnumerateArray()
                .SingleOrDefault(item => item.GetProperty("app").GetString() == appName);
            if (recorded.ValueKind == JsonValueKind.Undefined ||
                recorded.GetProperty("revision").GetString() != original.GetProperty("revision").GetString() ||
                recorded.GetProperty("image").GetString() != image)
                throw new InvalidOperationException("Preflight and recovery manifest do not identify the same publisher images/revisions.");
        }
    }

    private static void ValidateEvidencePath(ReplayDrillRuntimeTarget target, string path)
    {
        var full = ResolveEvidencePathUnderTestResults(target.RepositoryRoot, path);
        if (!File.Exists(full))
            throw new InvalidOperationException("Replay drill evidence must be an existing file under project TestResults.");
    }

    internal static string ResolveEvidencePathUnderTestResults(string repositoryRoot, string path)
    {
        if (string.IsNullOrWhiteSpace(repositoryRoot) || string.IsNullOrWhiteSpace(path))
            throw new InvalidOperationException("Replay drill evidence path and repository root are required.");

        var fullPath = Path.GetFullPath(path);
        var testResultsRoot = Path.GetFullPath(Path.Combine(repositoryRoot, "TestResults"));
        var relative = Path.GetRelativePath(testResultsRoot, fullPath);
        if (relative == "." || Path.IsPathRooted(relative) ||
            relative.Equals("..", StringComparison.Ordinal) ||
            relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal) ||
            relative.StartsWith(".." + Path.AltDirectorySeparatorChar, StringComparison.Ordinal))
            throw new InvalidOperationException("Replay drill evidence must remain under project TestResults.");

        var current = testResultsRoot;
        RejectReparsePoint(current);
        foreach (var segment in relative.Split(new[] { Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar }, StringSplitOptions.RemoveEmptyEntries))
        {
            current = Path.Combine(current, segment);
            RejectReparsePoint(current);
        }

        return fullPath;

        static void RejectReparsePoint(string candidate)
        {
            if (TryGetAttributes(candidate, out var attributes) && attributes.HasFlag(FileAttributes.ReparsePoint))
                throw new InvalidOperationException("Replay drill evidence cannot pass through a symbolic link or reparse point.");
        }

        static bool TryGetAttributes(string candidate, out FileAttributes attributes)
        {
            try
            {
                attributes = File.GetAttributes(candidate);
                return true;
            }
            catch (FileNotFoundException)
            {
                attributes = FileAttributes.Normal;
                return false;
            }
            catch (DirectoryNotFoundException)
            {
                attributes = FileAttributes.Normal;
                return false;
            }
        }
    }

    private static string FindRepositoryRoot()
    {
        foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
        {
            var current = new DirectoryInfo(start);
            while (current is not null)
            {
                if (File.Exists(Path.Combine(current.FullName, "automation", "config", "runtime-targets.json"))) return current.FullName;
                current = current.Parent;
            }
        }

        throw new DirectoryNotFoundException("Could not locate the repository runtime-target catalog.");
    }

    private static string CreatePendingJournal(
        ReplayDrillSettings settings,
        ReplayDrillRuntimeTarget target,
        int tenantId,
        Guid requestId,
        Guid quarantineId)
    {
        var reportPath = Path.Combine(target.RepositoryRoot, "TestResults", "Phase10", $"azure-replay-drill-{settings.RunId:N}.json");
        reportPath = ResolveEvidencePathUnderTestResults(target.RepositoryRoot, reportPath);
        Directory.CreateDirectory(Path.GetDirectoryName(reportPath)!);

        var report = new
        {
            schemaVersion = 1,
            status = "RUNNING",
            environment = "azure-dev",
            scenario = settings.Scenario.ToString(),
            runId = settings.RunId,
            requestId,
            quarantineId,
            tenantCode = settings.TenantCode,
            tenantId,
            businessDatabase = settings.BusinessDatabaseName,
            recoveryNote = "If this remains RUNNING after interruption, inspect the replay manifest, SQL checkpoint, queue delivery count and consumer effects before any retry.",
            credentialValuesRecorded = false,
            startedUtc = DateTimeOffset.UtcNow
        };
        using var output = new FileStream(reportPath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        JsonSerializer.Serialize(output, report, new JsonSerializerOptions { WriteIndented = true });
        return reportPath;
    }

    private static void WriteSanitizedReport(
        string reportPath,
        ReplayDrillSettings settings,
        int tenantId,
        Guid messageId,
        Guid orderReferenceId,
        int publishCalls,
        DurableEffectCounts effects,
        (long InventoryDuplicateTraces, long NotificationDuplicateTraces)? duplicateTraces,
        long pendingReplayRequestCount)
    {
        using var existing = JsonDocument.Parse(File.ReadAllText(reportPath));
        if (existing.RootElement.GetProperty("status").GetString() != "RUNNING" ||
            existing.RootElement.GetProperty("runId").GetGuid() != settings.RunId)
            throw new IOException("Replay drill journal is not the current run's incomplete journal; it was not overwritten.");
        var restoreEvidence = CreateRestoreEvidence(settings.ExpectedSubscriptionId, settings.ReplayRequestId, pendingReplayRequestCount);
        var report = new
        {
            schemaVersion = 1,
            status = restoreEvidence.Status,
            environment = restoreEvidence.Environment,
            subscriptionId = restoreEvidence.SubscriptionId,
            scenario = settings.Scenario.ToString(),
            runId = settings.RunId,
            replayRequestId = restoreEvidence.ReplayRequestId,
            publisherCheckpointed = restoreEvidence.PublisherCheckpointed,
            pendingReplayRequestCount = restoreEvidence.PendingReplayRequestCount,
            tenantCode = settings.TenantCode,
            tenantId,
            businessDatabase = settings.BusinessDatabaseName,
            businessMessageId = messageId,
            orderReferenceId,
            publishCalls,
            effects,
            duplicateConsumerTraceCounts = duplicateTraces is null
                ? null
                : new { inventory = duplicateTraces.Value.InventoryDuplicateTraces, notifications = duplicateTraces.Value.NotificationDuplicateTraces },
            credentialValuesRecorded = false,
            startedUtc = existing.RootElement.GetProperty("startedUtc").GetDateTimeOffset(),
            checkedUtc = DateTimeOffset.UtcNow
        };
        File.WriteAllText(reportPath, JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine($"Sanitized Azure replay drill report: {reportPath}");
    }

    internal static ReplayDrillRestoreEvidence CreateRestoreEvidence(
        string subscriptionId,
        Guid replayRequestId,
        long pendingReplayRequestCount)
    {
        if (string.IsNullOrWhiteSpace(subscriptionId) || replayRequestId == Guid.Empty)
            throw new InvalidOperationException("Restore evidence requires the approved subscription and replay request identity.");
        if (pendingReplayRequestCount != 0)
            throw new InvalidOperationException("Restore evidence cannot PASS while any replay requests remain unprocessed.");

        return new ReplayDrillRestoreEvidence("PASS", "dev", subscriptionId, replayRequestId, true, pendingReplayRequestCount);
    }

    internal sealed record ReplayDrillRestoreEvidence(
        string Status,
        string Environment,
        string SubscriptionId,
        Guid ReplayRequestId,
        bool PublisherCheckpointed,
        long PendingReplayRequestCount);

    private sealed record DurableEffectCounts(long InventoryInbox, long NotificationInbox, long InventoryReservations, long NotificationDeliveries)
    {
        public bool IsExactlyOnce => InventoryInbox == 1 && NotificationInbox == 1 && InventoryReservations == 1 && NotificationDeliveries == 1;
    }

    private sealed record ReplayDrillRuntimeTarget(
        string RepositoryRoot,
        string ResourceGroup,
        string SqlServerName,
        string KeyVaultName,
        string OperationsDatabaseName,
        string ServiceBusNamespaceName,
        string ServiceBusFullyQualifiedNamespace,
        string OrderEventsTopicName,
        string ReplayRequestQueueName,
        string ReplayDrillRequestQueueName,
        string ApplicationInsightsName,
        string OrdersApp,
        string PaymentsApp,
        string InventoryApp,
        string NotificationsApp,
        string FunctionApp);

    private enum ReplayDrillScenario { ProcessedCheckpoint, SendAcceptedBeforeCheckpoint }

    private sealed record ReplayDrillSettings(
        string ExpectedSubscriptionId,
        string RunnerPrincipalObjectId,
        string TenantCode,
        string BusinessDatabaseName,
        Guid ReplayRequestId,
        Guid RunId,
        ReplayDrillScenario Scenario,
        string PreflightReportPath,
        string ConfigManifestPath)
    {
        public static ReplayDrillSettings Load()
        {
            string Required(string key) => Environment.GetEnvironmentVariable(key) is { Length: > 0 } value
                ? value
                : throw new InvalidOperationException($"Required opt-in replay setting '{key}' is not configured.");
            if (Environment.GetEnvironmentVariable("PHASE10_REPLAY_DRILL_ENABLE") != EnableValue)
                throw new InvalidOperationException("Set the exact Azure-dev replay opt-in before running this live test.");
            if (!Guid.TryParse(Required("PHASE10_REPLAY_DRILL_EXPECTED_SUBSCRIPTION_ID"), out var subscriptionId) || subscriptionId == Guid.Empty)
                throw new InvalidOperationException("Expected subscription must be a non-empty GUID.");
            if (!Guid.TryParse(Required("PHASE10_REPLAY_DRILL_REQUEST_ID"), out var requestId) || requestId == Guid.Empty)
                throw new InvalidOperationException("Replay request ID must be a non-empty GUID approved through the application API.");
            if (!Guid.TryParse(Required("PHASE10_REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID"), out var principalId) || principalId == Guid.Empty)
                throw new InvalidOperationException("Runner principal object ID must match the dedicated preflighted operator user.");
            if (!Guid.TryParse(Required("PHASE10_REPLAY_DRILL_RUN_ID"), out var runId) || runId == Guid.Empty)
                throw new InvalidOperationException("Run ID must be a new non-empty GUID.");
            if (!Enum.TryParse<ReplayDrillScenario>(Required("PHASE10_REPLAY_DRILL_SCENARIO"), ignoreCase: true, out var scenario))
                throw new InvalidOperationException("Scenario must be ProcessedCheckpoint or SendAcceptedBeforeCheckpoint.");
            var tenant = Required("PHASE10_REPLAY_DRILL_TENANT_CODE");
            if (!System.Text.RegularExpressions.Regex.IsMatch(tenant, "^[A-Za-z0-9_-]{1,64}$"))
                throw new InvalidOperationException("Tenant code contains unsupported characters.");
            var database = Required("PHASE10_REPLAY_DRILL_BUSINESS_DATABASE");
            if (!System.Text.RegularExpressions.Regex.IsMatch(database, "^[A-Za-z0-9_]{1,128}$"))
                throw new InvalidOperationException("Business database name contains unsupported characters.");
            return new ReplayDrillSettings(subscriptionId.ToString("D"), principalId.ToString("D"), tenant, database, requestId, runId, scenario,
                Path.GetFullPath(Required("PHASE10_REPLAY_DRILL_PREFLIGHT_REPORT")),
                Path.GetFullPath(Required("PHASE10_REPLAY_DRILL_CONFIG_MANIFEST")));
        }

        public void ValidateTarget(ReplayDrillRuntimeTarget target)
        {
            if (target.ServiceBusFullyQualifiedNamespace != $"{target.ServiceBusNamespaceName}.servicebus.windows.net" ||
                target.ReplayRequestQueueName == target.ReplayDrillRequestQueueName ||
                string.IsNullOrWhiteSpace(target.OperationsDatabaseName) ||
                string.IsNullOrWhiteSpace(target.ReplayDrillRequestQueueName) ||
                !System.Text.RegularExpressions.Regex.IsMatch(BusinessDatabaseName, "^[A-Za-z0-9_]{1,128}$"))
                throw new InvalidOperationException("Runtime target is not a valid isolated Azure-dev replay target.");
        }
    }
}

[AttributeUsage(AttributeTargets.Method)]
internal sealed class AzureReplayDrillFactAttribute : FactAttribute
{
    public AzureReplayDrillFactAttribute()
    {
        if (Environment.GetEnvironmentVariable("PHASE10_REPLAY_DRILL_ENABLE") != "I_APPROVE_AZURE_DEV_REPLAY_DRILL")
            Skip = "Azure replay drill is opt-in and requires the explicit dev-only approval variable.";
    }
}

[CollectionDefinition("AzureReplayDrillSerial", DisableParallelization = true)]
public sealed class AzureReplayDrillSerialCollection;
