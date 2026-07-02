# Phase 10 Azure Smoke Runbook

This runbook covers the first live check for the Phase 10 transport slice defined in [docs/internal/phase10-implementation-checklist.md](../internal/phase10-implementation-checklist.md).

## Scope

- Entry point: `infra/main.phase10.bicep`
- Parameters: `infra/parameters/phase10-dev.json`, `infra/parameters/phase10-staging.json`, `infra/parameters/phase10-prod.json`
- Transport path: `Orders -> Service Bus -> Inventory/Notifications`
- Replay path: `order-events-dlq -> dlq-replay -> order-events`
- The Service Bus namespace, transport auth rule, and connection-string lookup are owned by `infra/modules/servicebus.bicep`; `infra/main.phase10.bicep` consumes that module output during deployment.

## Quick Command Checklist

Use this if you want the shortest possible runbook for the first Azure dev proof.

```powershell
$env:AZURE_CONFIG_DIR = "$PWD\.azure-cli"
$deploymentName = "phase10-dev-$(Get-Date -Format yyyyMMddHHmmss)"

az deployment sub what-if `
  --location centralindia `
  --template-file infra/main.phase10.bicep `
  --parameters @infra/parameters/phase10-dev.json

az deployment sub create `
  --name $deploymentName `
  --location centralindia `
  --template-file infra/main.phase10.bicep `
  --parameters @infra/parameters/phase10-dev.json

$outputs = az deployment sub show --name $deploymentName --query "properties.outputs" -o json | ConvertFrom-Json
$resourceGroupName = $outputs.resourceGroupName.value
$serviceBusNamespaceName = $outputs.serviceBusNamespaceName.value
$logAnalyticsWorkspaceName = $outputs.logAnalyticsWorkspaceName.value
$managedEnvironmentId = $outputs.managedEnvironmentId.value
$gatewayContainerAppName = $outputs.gatewayContainerAppName.value
$uiContainerAppName = $outputs.uiContainerAppName.value
$ordersContainerAppName = $outputs.ordersContainerAppName.value
$inventoryContainerAppName = $outputs.inventoryContainerAppName.value
$notificationsContainerAppName = $outputs.notificationsContainerAppName.value
$functionAppName = $outputs.functionAppName.value
$keyVaultName = $outputs.keyVaultName.value
$appInsightsName = $outputs.appInsightsName.value

az servicebus namespace show --resource-group $resourceGroupName --name $serviceBusNamespaceName
az servicebus topic show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --name order-events
az servicebus topic subscription show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --topic-name order-events --name inventory-order-created
az servicebus topic subscription show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --topic-name order-events --name notifications-order-created
az servicebus topic show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --name order-events-dlq
az servicebus topic subscription show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --topic-name order-events-dlq --name dlq-replay

az functionapp config appsettings list --resource-group $resourceGroupName --name $functionAppName
az containerapp show --resource-group $resourceGroupName --name $ordersContainerAppName --query "properties.template.containers[0].env"
az containerapp show --resource-group $resourceGroupName --name $inventoryContainerAppName --query "properties.template.containers[0].env"
az containerapp show --resource-group $resourceGroupName --name $notificationsContainerAppName --query "properties.template.containers[0].env"
az monitor log-analytics workspace show --resource-group $resourceGroupName --workspace-name $logAnalyticsWorkspaceName
az resource show --ids $managedEnvironmentId
az resource show --resource-group $resourceGroupName --resource-type Microsoft.Insights/components --name $appInsightsName
```

Expected:
- the deployment completes successfully
- the outputs resolve without manual guessing
- the Service Bus namespace, topic, subscriptions, and DLQ path exist
- the runtime settings include the Service Bus connection string and replay values
- the ACA environment and App Insights are wired to the same transport slice

## Operator Notes

1. Confirm `az` is authenticated in the target subscription.
2. Confirm the workspace-local Azure config dir is usable if the default profile is locked down.
3. Confirm the repo is clean enough to deploy the current Phase 10 stack.
4. Confirm the target environment is `dev`, `staging`, or `prod`.
5. If `az bicep version` fails, run `az bicep install` once so the local compiler is available for preview and deployment validation.

## Minimal Flow

### 1. Preview the deployment

```powershell
az deployment sub what-if --location centralindia --template-file infra/main.phase10.bicep --parameters @infra/parameters/phase10-dev.json
```

Expected:
- The plan shows the Phase 10 transport stack.
- The plan includes Service Bus, Log Analytics, ACA, Functions, Key Vault, and App Insights resources.

### 2. Deploy the environment

```powershell
az deployment sub create --location centralindia --template-file infra/main.phase10.bicep --parameters @infra/parameters/phase10-dev.json --name phase10-dev-<timestamp>
```

Expected:
- The deployment completes successfully.
- The deployment outputs include the Service Bus namespace, Log Analytics workspace, ACA environment, Function App, Key Vault, and App Insights names.

### 3. Capture deployment outputs

```powershell
$deploymentName = "phase10-dev-<timestamp>"
$outputs = az deployment sub show --name $deploymentName --query "properties.outputs" -o json | ConvertFrom-Json
$resourceGroupName = $outputs.resourceGroupName.value
$serviceBusNamespaceName = $outputs.serviceBusNamespaceName.value
$logAnalyticsWorkspaceName = $outputs.logAnalyticsWorkspaceName.value
$managedEnvironmentId = $outputs.managedEnvironmentId.value
$gatewayContainerAppName = $outputs.gatewayContainerAppName.value
$uiContainerAppName = $outputs.uiContainerAppName.value
$ordersContainerAppName = $outputs.ordersContainerAppName.value
$inventoryContainerAppName = $outputs.inventoryContainerAppName.value
$notificationsContainerAppName = $outputs.notificationsContainerAppName.value
$functionAppName = $outputs.functionAppName.value
$keyVaultName = $outputs.keyVaultName.value
$appInsightsName = $outputs.appInsightsName.value
```

Expected:
- You have the exact Azure names needed for post-deploy verification.
- The values come from the Phase 10 template outputs, not manual guesswork.

## Verify Everything

Use this compact block if you only want the minimum confirmation set after deploy:

```powershell
az servicebus namespace show --resource-group $resourceGroupName --name $serviceBusNamespaceName
az functionapp config appsettings list --resource-group $resourceGroupName --name $functionAppName
az monitor log-analytics workspace show --resource-group $resourceGroupName --workspace-name $logAnalyticsWorkspaceName
az resource show --ids $managedEnvironmentId
az resource show --resource-group $resourceGroupName --resource-type Microsoft.Insights/components --name $appInsightsName
```

Expected:
- the Service Bus namespace exists and is reachable
- the runtime settings contain the transport connection string and replay values
- the ACA environment and App Insights share the same transport slice
- the environment is ready for the publish / consume / replay smoke

## Fallback Checks

### 4. Verify Service Bus topology

```powershell
az servicebus namespace show --resource-group $resourceGroupName --name $serviceBusNamespaceName
az servicebus topic show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --name order-events
az servicebus topic subscription show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --topic-name order-events --name inventory-order-created
az servicebus topic subscription show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --topic-name order-events --name notifications-order-created
az servicebus topic show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --name order-events-dlq
az servicebus topic subscription show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --topic-name order-events-dlq --name dlq-replay
```

Confirm the deployed namespace contains:
- `order-events`
- `inventory-order-created`
- `notifications-order-created`
- `order-events-dlq`
- `dlq-replay`

Confirm the namespace also contains the Phase 10 transport auth rule.

### 5. Verify runtime configuration

```powershell
az functionapp config appsettings list --resource-group $resourceGroupName --name $functionAppName
az containerapp show --resource-group $resourceGroupName --name $gatewayContainerAppName --query "properties.template.containers[0].env"
az containerapp show --resource-group $resourceGroupName --name $uiContainerAppName --query "properties.template.containers[0].env"
az containerapp show --resource-group $resourceGroupName --name $ordersContainerAppName --query "properties.template.containers[0].env"
az containerapp show --resource-group $resourceGroupName --name $inventoryContainerAppName --query "properties.template.containers[0].env"
az containerapp show --resource-group $resourceGroupName --name $notificationsContainerAppName --query "properties.template.containers[0].env"
```

Confirm the deployed runtime settings include:
- `ServiceBus__Enabled=true`
- `ServiceBus__ConnectionString`
- `ServiceBus__TopicName=order-events`
- `ServiceBus__DeadLetterTopicName=order-events-dlq`
- `ServiceBus__DeadLetterSubscriptionName=dlq-replay`
- `ServiceBus__ReplayEnabled=true`
- `KeyVault__Uri`
- `APPLICATIONINSIGHTS_CONNECTION_STRING`
- `ServiceBus__SubscriptionName` on Inventory and Notifications
- `ServiceBus__SubscriptionName` is not required on Orders because it is the publisher slice

Confirm the runtime can read the Service Bus connection string from configuration instead of falling back to in-memory, and that the connection string was derived from the transport auth rule rather than hand-entered into app settings.

### 6. Verify observability wiring

```powershell
az monitor log-analytics workspace show --resource-group $resourceGroupName --workspace-name $logAnalyticsWorkspaceName
az resource show --ids $managedEnvironmentId
az resource show --resource-group $resourceGroupName --resource-type Microsoft.Insights/components --name $appInsightsName
```

Confirm:
- the Log Analytics workspace exists and is linked to the ACA environment
- App Insights exists and is emitting to the same transport slice
- ACA container app logs are enabled through the workspace-backed environment
- the Orders, Inventory, and Notifications apps have the transport-first Service Bus settings in their environment payloads
- the Gateway and UI container apps exist in the same ACA environment

### 7. Transport Smoke

```powershell
# Trigger the first order-created path through the running service.
# Use the repo's existing local or Azure request path for an order create.
```

1. Send or trigger a single `OrderCreatedV1` flow through the `Orders` service.
2. Confirm the message is published to Service Bus.
3. Confirm the downstream consumer receives the message once.
4. Confirm duplicate delivery remains harmless if the message is replayed.
5. Confirm dead-lettered messages are visible through the `order-events-dlq` path.

### 8. Replay Smoke

```powershell
# Use a controlled failure or seeded dead-letter message to exercise replay.
```

1. Force a controlled transient failure for one replayable message.
2. Confirm the message lands in the dead-letter topic.
3. Confirm `DlqReplayWorker` rehydrates the canonical envelope.
4. Confirm the replayed message is sent back to `order-events`.
5. Confirm poison or unclassified messages remain quarantined.

## Success Criteria

- The transport stack deploys cleanly.
- The runtime uses Service Bus instead of the in-memory publisher.
- The first order-created flow is observable end to end.
- Replay and quarantine behavior are both visible in Azure.
- The Phase 10 transport slice remains separate from the hosting cutover.

## If Smoke Fails

- Keep `infra/main.bicep` reserved for the later hosting path.
- Fix the transport wiring or Service Bus config before moving on to broader hosting work.
- Do not introduce `SharedContracts` as a workaround for a transport failure.
