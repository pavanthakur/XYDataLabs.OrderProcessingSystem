using System.Text.Json;
using System.Diagnostics;
using System.Globalization;
using Azure.Messaging.ServiceBus;
using Microsoft.Data.SqlClient;

namespace XYDataLabs.OrderProcessingSystem.Tools.Phase10.NfrProbe;

internal static class FunctionsAcceptance
{
    private const double MaximumReplayVisibilitySeconds = 60;

    public static async Task<int> RunAsync(ProbeOptions options)
    {
        var result = new Dictionary<string, object?> { ["status"]="failed",["runtime"]="local-docker",["startedUtc"]=DateTime.UtcNow };
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(options.ResultPath))!);
            var cs=new SqlConnectionStringBuilder(options.SqlConnectionString);
            if (!cs.DataSource.Contains("127.0.0.1,14330",StringComparison.OrdinalIgnoreCase)
                || cs.InitialCatalog != "OrderProcessingSystem_Dev"
                || !options.ServiceBusConnectionString.Contains("UseDevelopmentEmulator=true",StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Functions acceptance requires verified local Docker SQL and the Service Bus emulator.");
            await using var connection=new SqlConnection(options.SqlConnectionString);
            await connection.OpenAsync();
            async Task<object?> Sql(string query, params (string,object)[] parameters)
            {
                // Every caller supplies a compile-time SQL literal below; all
                // message IDs, tenant codes and other data use bound parameters.
#pragma warning disable CA2100
                await using var command=new SqlCommand(query,connection);
#pragma warning restore CA2100
                foreach(var (name,value) in parameters) command.Parameters.AddWithValue(name,value);
                return await command.ExecuteScalarAsync();
            }
            var tenantId=Convert.ToInt32(await Sql("SELECT Id FROM dbo.Tenants WHERE Code=@code AND Status='Active'",("@code",options.TenantCode)));
            if(tenantId<=0) throw new InvalidOperationException("Active test tenant missing.");
            var messageId=Guid.NewGuid(); var correlation=$"functions-acceptance-{messageId:N}";
            result["correlationId"]=correlation;
            var body=BinaryData.FromObjectAsJson(new {customerId=101,orderDate=DateTime.UtcNow,totalPrice=1m,productCount=1,orderReferenceId=Guid.NewGuid()});
            ServiceBusMessage Message(string id)
            {
                var message=new ServiceBusMessage(body){MessageId=id,CorrelationId=correlation,Subject="OrderCreatedV1",ContentType="application/json"};
                message.ApplicationProperties["TenantId"]=tenantId;
                message.ApplicationProperties["TenantCode"]=options.TenantCode;
                message.ApplicationProperties["EventType"]="OrderCreatedV1";
                message.ApplicationProperties["EnvelopeMessageId"]=messageId.ToString("D");
                message.ApplicationProperties["AttemptCount"]=0;
                message.ApplicationProperties["FailureCategory"]="transient-dependency";
                return message;
            }
            await using var client=new ServiceBusClient(options.ServiceBusConnectionString,new ServiceBusClientOptions
                {RetryOptions=new ServiceBusRetryOptions {TryTimeout=TimeSpan.FromSeconds(15),MaxRetries=1,Delay=TimeSpan.FromSeconds(1)}});
            await using var intake=client.CreateSender("order-events-dlq");
            await intake.SendMessageAsync(Message(messageId.ToString("D")));
            async Task<object> Poll(string sql, params (string,object)[] parameters)
            {
                var deadline=DateTime.UtcNow.AddSeconds(options.TimeoutSeconds);
                while(DateTime.UtcNow<deadline)
                {
                    var value=await Sql(sql,parameters);
                    if(value is not null && value != DBNull.Value) return value;
                    await Task.Delay(1000);
                }
                throw new TimeoutException("Expected Functions processing evidence did not appear within the bounded wait.");
            }
            var poisonId=Guid.NewGuid();
            var poison=Message(poisonId.ToString("D"));
            poison.Body=BinaryData.FromString("not-json");
            poison.ApplicationProperties["EnvelopeMessageId"]=poisonId.ToString("D");
            await using var normalTopic=client.CreateSender(options.TopicName);
            await normalTopic.SendMessageAsync(poison);
            await Poll("SELECT 1 FROM operations.DlqQuarantineRecords WHERE SourceMessageId=@id AND TenantId=@tenant AND FailureReason IN ('malformed-payload','permanent-contract-failure')",("@id",poisonId.ToString("D")),("@tenant",tenantId));
            result["brokerDlqForwarding"]="passed";
            var quarantine=(Guid)await Poll("SELECT Id FROM operations.DlqQuarantineRecords WHERE SourceMessageId=@id AND TenantId=@tenant",("@id",messageId.ToString("D")),("@tenant",tenantId));
            result["intake"]="passed"; result["quarantineId"]=quarantine;
            var approvalPath=Path.Combine(Path.GetDirectoryName(Path.GetFullPath(options.ResultPath))!, $"{Path.GetFileNameWithoutExtension(options.ResultPath)}.approval.json");
            result["approvalStatus"]="pending-reconciliation";
            var approval=await RequestLocalReplayApprovalAsync(options,quarantine,approvalPath);
            var replayRequestId=approval.ReplayRequestId;
            result["approvalOutcome"]="approved";
            result["approvalMethod"]="authenticated-local-keycloak-pkce-api";
            result["replayRequestId"]=replayRequestId;
            result["approvalState"]=approval.State;
            result["approvedUtc"]=approval.ApprovedUtc;
            var replayClock=System.Diagnostics.Stopwatch.StartNew();
            await Poll("SELECT 1 FROM operations.DlqReplayRequests r JOIN operations.DlqQuarantineRecords q ON q.Id=r.QuarantineId WHERE r.Id=@r AND r.QuarantineId=@q AND q.TenantId=@tenant AND r.ProcessedUtc IS NOT NULL AND q.State='Replayed'",("@r",replayRequestId),("@q",quarantine), ("@tenant",tenantId));
            var replaySeconds=Math.Round(replayClock.Elapsed.TotalSeconds,3);
            result["replayVisibilitySeconds"]=replaySeconds; result["replayVisibilityLimitSeconds"]=MaximumReplayVisibilitySeconds;
            if(replaySeconds>MaximumReplayVisibilitySeconds){result["replay"]="threshold-exceeded"; throw new InvalidOperationException("Approved replay was not visible within the limit.");}
            result["replay"]="passed";
            await Poll("SELECT 1 WHERE (SELECT COUNT(*) FROM inventory.InventoryReservations WHERE CorrelationId=@c)=1 AND (SELECT COUNT(*) FROM notifications.NotificationDeliveries WHERE CorrelationId=@c)=1",("@c",correlation));
            result["downstreamEffects"]="passed";result["status"]="passed";
        }
        catch(Exception error){result["errorType"]=error.GetType().Name; result["message"]="Functions proof incomplete. Inspect local service readiness and replay enablement; no credentials recorded.";}
        result["finishedUtc"]=DateTime.UtcNow;
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(options.ResultPath))!);
        await File.WriteAllTextAsync(options.ResultPath,JsonSerializer.Serialize(result,new JsonSerializerOptions{WriteIndented=true}));
        return Equals(result["status"],"passed")?0:1;
    }

    private static async Task<LocalReplayApproval> RequestLocalReplayApprovalAsync(
        ProbeOptions options,
        Guid quarantineId,
        string approvalPath)
    {
        var workspaceRoot=Directory.GetCurrentDirectory();
        var identityProof=Path.Combine(workspaceRoot,"frontend","apps","web","scripts","phase10-identity-proof.mjs");
        if(!File.Exists(identityProof)) throw new FileNotFoundException("Local PKCE identity proof script is unavailable.",identityProof);
        if(string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("KEYCLOAK_TENANT_ADMIN_PASSWORD"))
            && string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("LOCAL_KEYCLOAK_TEST_PASSWORD")))
            throw new InvalidOperationException("The local Keycloak operator password must be supplied through the existing private test environment.");

        var identityEvidencePath=Path.ChangeExtension(approvalPath,".identity.json");
        var start=new ProcessStartInfo
        {
            FileName="node",
            WorkingDirectory=workspaceRoot,
            UseShellExecute=false,
            RedirectStandardOutput=true,
            RedirectStandardError=true,
            CreateNoWindow=true
        };
        start.ArgumentList.Add(identityProof);
        foreach(var argument in new[]
        {
            "--url","http://localhost:5022",
            "--gateway-api-url","http://localhost:5080",
            "--orders-api-url","http://localhost:5081",
            "--payments-api-url","http://localhost:5084",
            "--approval-api-url","http://localhost:5081",
            "--approve-quarantine-id",quarantineId.ToString("D"),
            "--approval-tenant-code",options.TenantCode,
            "--approval-output",approvalPath,
            "--output",identityEvidencePath
        }) start.ArgumentList.Add(argument);

        using var process=new Process { StartInfo=start };
        if(!process.Start()) throw new InvalidOperationException("Could not start the local PKCE operator proof.");
        var stdoutTask=process.StandardOutput.ReadToEndAsync();
        var stderrTask=process.StandardError.ReadToEndAsync();
        using var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(Math.Clamp(options.TimeoutSeconds+120,120,420)));
        try
        {
            await process.WaitForExitAsync(timeout.Token);
        }
        catch(OperationCanceledException)
        {
            try { process.Kill(entireProcessTree:true); }
            catch(InvalidOperationException) { throw new TimeoutException("Local PKCE replay approval stopped before cancellation could be confirmed."); }
            throw new TimeoutException("Local PKCE replay approval did not finish within the bounded browser wait; inspect the sanitized identity report and reconcile before retrying.");
        }
        _=await stdoutTask;
        _=await stderrTask;
        if(process.ExitCode!=0) throw new InvalidOperationException($"Local PKCE replay approval or identity checks failed (exit {process.ExitCode}); no replay acceptance is claimed.");
        if(!File.Exists(approvalPath)) throw new InvalidDataException("Local PKCE proof exited without writing validated approval metadata.");

        using var document=JsonDocument.Parse(await File.ReadAllTextAsync(approvalPath));
        var root=document.RootElement;
        if(!root.TryGetProperty("status",out var evidenceStatus)
            || evidenceStatus.GetString()!="APPROVED")
            throw new InvalidDataException("Local approval evidence is incomplete; reconcile before retrying.");
        var returnedQuarantine=root.GetProperty("quarantineId").GetString();
        var replayRequestId=root.GetProperty("replayRequestId").GetString();
        var state=root.GetProperty("state").GetString();
        var approvedUtc=root.GetProperty("approvedUtc").GetString();
        if(!Guid.TryParse(returnedQuarantine,out var parsedQuarantine) || parsedQuarantine!=quarantineId
            || !Guid.TryParse(replayRequestId,out var parsedReplayRequest)
            || !string.Equals(state,"approved",StringComparison.OrdinalIgnoreCase)
            || !root.TryGetProperty("alreadyApproved",out var alreadyApproved) || alreadyApproved.GetBoolean()
            || !DateTimeOffset.TryParse(approvedUtc,CultureInfo.InvariantCulture,DateTimeStyles.RoundtripKind,out var approvedAt))
            throw new InvalidDataException("Local PKCE approval metadata is incomplete or mismatched; reconcile before retrying.");
        return new LocalReplayApproval(parsedReplayRequest,state!,approvedAt);
    }

    private sealed record LocalReplayApproval(Guid ReplayRequestId,string State,DateTimeOffset ApprovedUtc);
}
