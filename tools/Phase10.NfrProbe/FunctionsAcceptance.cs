using System.Text.Json;
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
            var messageId=Guid.NewGuid(); var replayRequestId=Guid.NewGuid(); var correlation=$"functions-acceptance-{messageId:N}";
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
            await Sql("UPDATE operations.DlqQuarantineRecords SET State='Approved' WHERE Id=@q; INSERT INTO operations.DlqReplayRequests (Id,QuarantineId,ApprovedBy,ApprovedUtc,PublishedUtc) VALUES (@r,@q,'local-acceptance',GETUTCDATE(),GETUTCDATE()); SELECT 1",("@q",quarantine),("@r",replayRequestId));
            var replay=Message($"{messageId:D}-replay");
            replay.ApplicationProperties["QuarantineId"]=quarantine.ToString("D");
            replay.ApplicationProperties["ReplayRequestId"]=replayRequestId.ToString("D");
            replay.ApplicationProperties["ReplayApproved"]=true;
            await using var requests=client.CreateSender("dlq-replay-requests");
            var replayClock=System.Diagnostics.Stopwatch.StartNew();
            await requests.SendMessageAsync(replay);
            await Poll("SELECT 1 FROM operations.DlqReplayRequests r JOIN operations.DlqQuarantineRecords q ON q.Id=r.QuarantineId WHERE r.Id=@r AND r.ProcessedUtc IS NOT NULL AND q.State='Replayed'",("@r",replayRequestId));
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
}
