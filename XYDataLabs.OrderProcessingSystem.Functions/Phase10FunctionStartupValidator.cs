using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

namespace XYDataLabs.OrderProcessingSystem.Functions;

public sealed class Phase10FunctionStartupValidator(
    IConfiguration configuration,
    IOptions<ServiceBusOptions> serviceBusOptions)
{
    public void Validate()
    {
        var storageConnectionString = configuration["AzureWebJobsStorage"];
        var storageAccountName = configuration["AzureWebJobsStorage:accountName"];
        var storageCredential = configuration["AzureWebJobsStorage:credential"];
        var storageClientId = configuration["AzureWebJobsStorage:clientId"];
        var hasStorageConnectionString = !string.IsNullOrWhiteSpace(storageConnectionString);
        var hasAnyIdentityStorageSetting = !string.IsNullOrWhiteSpace(storageAccountName)
            || !string.IsNullOrWhiteSpace(storageCredential)
            || !string.IsNullOrWhiteSpace(storageClientId);
        var hasCompleteIdentityStorageSettings = !string.IsNullOrWhiteSpace(storageAccountName)
            && string.Equals(storageCredential, "managedidentity", StringComparison.OrdinalIgnoreCase)
            && !string.IsNullOrWhiteSpace(storageClientId);

        if (hasStorageConnectionString && hasAnyIdentityStorageSetting)
        {
            throw new InvalidOperationException(
                "Configure either AzureWebJobsStorage for local connection-string storage or the complete AzureWebJobsStorage identity settings, not both.");
        }

        if (!hasStorageConnectionString && !hasCompleteIdentityStorageSettings)
        {
            throw new InvalidOperationException(
                "Configure AzureWebJobsStorage for local storage or AzureWebJobsStorage:accountName, AzureWebJobsStorage:credential=managedidentity, and AzureWebJobsStorage:clientId for Azure host storage.");
        }

        var options = serviceBusOptions.Value;
        if (options.Enabled && string.IsNullOrWhiteSpace(options.ConnectionString))
        {
            throw new InvalidOperationException("ServiceBus:ConnectionString must be configured when ServiceBus:Enabled is true.");
        }

        if (options.Enabled && string.IsNullOrWhiteSpace(configuration["ServiceBusConnection"]))
        {
            throw new InvalidOperationException("ServiceBusConnection must be configured when Service Bus triggers are enabled.");
        }

        if (options.Enabled
            && string.IsNullOrWhiteSpace(configuration.GetConnectionString("OrderProcessingSystemDbConnection")))
        {
            throw new InvalidOperationException(
                "ConnectionStrings:OrderProcessingSystemDbConnection must be configured for durable DLQ quarantine state.");
        }

        var operationsConnectionString = configuration.GetConnectionString("OrderProcessingSystemDbConnection");
        if (options.Enabled && hasCompleteIdentityStorageSettings)
        {
            if (string.IsNullOrWhiteSpace(operationsConnectionString)
                || !operationsConnectionString.Contains("Authentication=Active Directory Managed Identity", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException(
                    "Azure Functions SQL access must use Active Directory Managed Identity when Azure host storage uses managed identity.");
            }

            if (System.Text.RegularExpressions.Regex.IsMatch(
                    operationsConnectionString,
                    @"(?i)(?:^|;)\s*(?:User\s*ID|UID|Password|PWD)\s*="))
            {
                throw new InvalidOperationException(
                    "Azure Functions SQL connection must not contain SQL username or password credentials.");
            }
        }

        if (options.Enabled
            && string.IsNullOrWhiteSpace(configuration["Phase10DlqIntakeSubscriptionName"]))
        {
            throw new InvalidOperationException("Phase10DlqIntakeSubscriptionName must be configured.");
        }

        if (options.Enabled
            && string.IsNullOrWhiteSpace(configuration["Phase10DlqTopicName"]))
        {
            throw new InvalidOperationException("Phase10DlqTopicName must be configured.");
        }

        if (options.Enabled
            && string.IsNullOrWhiteSpace(configuration["Phase10ReplayRequestQueueName"]))
        {
            throw new InvalidOperationException("Phase10ReplayRequestQueueName must be configured.");
        }

        if (options.Enabled
            && !string.Equals(configuration["Phase10DlqTopicName"], options.DeadLetterTopicName, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "Phase10DlqTopicName must match ServiceBus:DeadLetterTopicName so the DLQ intake trigger uses the configured topic.");
        }

        if (options.Enabled
            && !string.Equals(configuration["Phase10DlqIntakeSubscriptionName"], options.DeadLetterSubscriptionName, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "Phase10DlqIntakeSubscriptionName must match ServiceBus:DeadLetterSubscriptionName so the DLQ intake trigger uses the configured subscription.");
        }

        if (options.Enabled
            && !string.Equals(configuration["Phase10ReplayRequestQueueName"], options.ReplayRequestQueueName, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "Phase10ReplayRequestQueueName must match ServiceBus:ReplayRequestQueueName so replay requests reach the configured queue.");
        }
    }
}
