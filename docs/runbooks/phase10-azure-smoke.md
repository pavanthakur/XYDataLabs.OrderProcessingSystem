# Phase 10 Azure Smoke Runbook

This runbook covers the first live check for the Phase 10 transport slice defined in [docs/internal/phase10-implementation-checklist.md](../internal/phase10-implementation-checklist.md).

## Scope

- Entry point: `infra/main.phase10.bicep`
- Parameters: `infra/parameters/phase10-dev.json`, `infra/parameters/phase10-staging.json`, `infra/parameters/phase10-prod.json`
- Transport path: `Orders -> Service Bus -> Inventory/Notifications`
- Replay path: `order-events-dlq -> dlq-replay -> order-events`
- The Service Bus namespace, transport auth rule, and connection-string lookup are owned by `infra/modules/servicebus.bicep`; `infra/main.phase10.bicep` consumes that module output during deployment.
- GitHub Actions entrypoint: `phase10-deploy-orchestrator.yml` (which calls `infra-deploy.yml` internally)
- Friendly alias inputs: `publicDomain`, `bindAliases`, `aliasMode`

If you want human-friendly public URLs, choose:

- `bindAliases=false` for summary-only runs
- `bindAliases=true` and `aliasMode=direct` for direct custom-domain binding
- `bindAliases=true` and `aliasMode=frontdoor` for DNS or Front Door planning only

When alias binding is enabled, supply a real `publicDomain` value such as `contoso.com`.

Quick chooser:

- Pick `direct` if you want the custom domain to land directly on the Container App ingress.
- Pick `frontdoor` if you want the run to only prepare the alias plan for a Front Door or DNS layer.
- Leave aliasing off for dry run and first deploys unless you already own the public domain.
- `direct` is the safer default when you are testing the Phase 10 path for the first time.

Shared operator rule:
- Local Docker and Azure Container Apps should be treated as the same Phase 10 service graph with different hosting targets.
- Both hosts now consume the same `orderprocessing-*` service image family, so the only contract difference is the runtime host and ingress surface.
- The service names stay environment-suffixed and split by responsibility, so cleanup and redeploy can safely target the exact gateway, Orders, Inventory, Notifications, and UI resources.
- The public hostname layer is the only thing that changes between the two hosts: localhost ports in Docker, ACA ingress or friendly aliases in Azure.
- The `AZUREAPPSERVICE_*` GitHub secrets referenced in this repo are environment-scoped OIDC identifiers carried forward from the earlier setup flow; they are used by the active Phase 10 Container Apps workflows, not to imply an App Service deployment target.

Local-vs-CI guidance:
- Use the local hook or VS Code tasks when you need to debug the Docker stack interactively.
- Use the GitHub Actions workflow as the pre-merge gate to confirm the same sequence still passes on a runner and still writes the expected log pointers and artifacts.

## Runtime Verification Checklist

Use this checklist to prove the shared contract is behaving the same way across both hosts:

1. Local Phase 10 stack
   - Start the local Phase 10 container stack.
   - Confirm the gateway, Orders, Inventory, Notifications, and UI containers all start with the `orderprocessing-*` image family.
   - Run the local smoke path and confirm the gateway and UI respond on their local ports.
2. Azure infra deploy
   - Run `phase10-deploy-orchestrator.yml` with the target environment and confirm the deployment summary reports the expected gateway and UI ingress outputs.
   - Verify the published image refs match the service-specific `orderprocessing-*` contract for gateway, Orders, Inventory, Notifications, and UI.
3. Azure smoke and automation
   - Run the Phase 10 Azure smoke after the deployment completes.
   - Confirm publish, consume, DLQ, and replay checks pass before promoting aliases or treating the environment as ready.

## GitHub UI Path

To launch the deployment from GitHub:

1. Open the repository in GitHub.
2. Select the `Actions` tab.
3. Click `Phase 10 Deploy Orchestrator`.
4. Click `Run workflow`.
5. Choose the target branch.
6. Set `environment`, `location`, and, if needed, `bindAliases`, `aliasMode`, `publicDomain`, and `cleanupInfra`.
7. Click `Run workflow` to start the deployment.

## VS Code Local Validation Path

Use these tasks when you want a local replica of the Phase 10 service graph before touching Azure:

1. `1 Run: Phase 10 Local Container Stack 00 Start`
2. `1 Run: Phase 10 Local Container Stack 01 Wait Ready + Keycloak`
3. `1 Run: Phase 10 Local Container Stack 02 Playwright Smoke`
4. `1 Run: Phase 10 Local Container Stack 03 Integration Suite`
5. `1 Run: Phase 10 Local Container Stack 04 Payment Matrix`
6. `1 Run: Phase 10 Local Container Stack 05 Full Validation`
7. `1 Run: Phase 10 Local Container Stack 06 Cleanup After Validation`

Log locations for the local container stack:

- `TestResults\Playwright\phase10-docker-http\<timestamp>_profile\...`
- `TestResults\Playwright\phase10-docker-http\<timestamp>_profile\01-env-ready.log`
- `TestResults\Playwright\phase10-docker-http\<timestamp>_smoke\...`
- `TestResults\Integration\<timestamp>\...`
- `TestResults\Playwright\phase10-docker-http\<timestamp>_endtoend\summary.json`
- `TestResults\Playwright\phase10-docker-http\latest-playwright-profile.txt`
- `TestResults\Playwright\phase10-docker-http\latest-playwright-smoke.txt`
- `TestResults\Playwright\latest-playwright-run.txt`

### Single-Command End-to-End Hook

If you want the same validation flow without launching the individual tasks one by one, use:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/run-phase10-docker-dev-e2e-hook.ps1
```

Or from the automation workspace:

```powershell
npm --prefix automation run run:docker:dev:http:e2e-hook
```

Use the hook when:

- you want the stack started automatically if it is not already running
- you want a single pass that includes ready, smoke, integration, matrix, and full validation
- you want the same log trail for repeatable validation and handoff

Quick start:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/run-phase10-docker-dev-e2e-hook.ps1
```

Use the individual tasks when:

- you are debugging a single step
- you want to pause between phases
- you want to keep the stack alive after one stage for manual inspection

### Common Troubleshooting

- If the hook fails before the stack starts, verify Docker Desktop is running and the engine is healthy.
- If the browser or smoke step times out, verify that the local ports for the gateway and UI are not already in use.
- If the gateway revision keeps activating or restarting, open the Container Apps logs and inspect the startup-probe failure details.
- If you need persistent logs for investigation, run the individual stack tasks instead of the single-command hook so cleanup does not happen until you ask for it.

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
$gatewayFqdn = $outputs.gatewayContainerAppFqdn.value
$uiFqdn = $outputs.uiContainerAppFqdn.value

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
Write-Host "Gateway ingress: https://$gatewayFqdn"
Write-Host "UI ingress: https://$uiFqdn"
```

Expected:
- the deployment completes successfully
- the outputs resolve without manual guessing
- the Service Bus namespace, topic, subscriptions, and DLQ path exist
- the runtime settings include the Service Bus connection string and replay values
- the ACA environment and App Insights are wired to the same transport slice
- the gateway and UI ingress URLs resolve from the deployment outputs

## Operator Notes

1. Confirm `az` is authenticated in the target subscription.
2. Confirm the workspace-local Azure config dir is usable if the default profile is locked down.
3. Confirm the repo is clean enough to deploy the current Phase 10 stack.
4. Confirm the target environment is `dev`, `staging`, or `prod`.
5. If `az bicep version` fails, run `az bicep install` once so the local compiler is available for preview and deployment validation.
6. If you are running from GitHub Actions, open `Actions > Phase 10 Deploy Orchestrator > Run workflow`, then set `environment`, `location`, and optionally `publicDomain`, `bindAliases`, `aliasMode`, and `cleanupInfra`.

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
- The deployment outputs include the gateway and UI ingress FQDNs.

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
$gatewayFqdn = $outputs.gatewayContainerAppFqdn.value
$uiFqdn = $outputs.uiContainerAppFqdn.value
```

Expected:
- You have the exact Azure names needed for post-deploy verification.
- The values come from the Phase 10 template outputs, not manual guesswork.
- You also have the friendly ingress targets for the gateway and UI.

### 4. Review the workflow summary

If the deployment was launched from GitHub Actions, open the run summary and confirm:

- the environment matches the target
- the resource group and transport outputs are present
- the gateway and UI ingress URLs are shown
- the friendly aliases are shown if `bindAliases` was enabled

If `bindAliases=true`, also confirm the workflow rejected placeholder domains and required a real `publicDomain`.

## Recommended Inputs

Use these defaults for the first pass in each environment:

| Environment | Location | bindAliases | aliasMode | publicDomain |
|-------------|----------|-------------|-----------|--------------|
| dev | `centralindia` | `false` | `direct` | empty |
| staging | `centralindia` | `false` | `direct` | empty |
| prod | `centralindia` | `false` | `direct` | empty |

Enable aliasing only when you are ready to manage a real public domain:

| Environment | bindAliases | aliasMode | publicDomain |
|-------------|-------------|-----------|--------------|
| dev | `true` | `direct` or `frontdoor` | `contoso.com` or your real suffix |
| staging | `true` | `direct` or `frontdoor` | `contoso.com` or your real suffix |
| prod | `true` | `direct` or `frontdoor` | `contoso.com` or your real suffix |

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
- the gateway and UI ingress URLs are recorded from the same deployment output set

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
- The deployment summary exposes the correct env-suffixed ingress URLs and friendly aliases when enabled.

## If Smoke Fails

- Keep `infra/main.bicep` reserved for the later hosting path.
- Fix the transport wiring or Service Bus config before moving on to broader hosting work.
- Do not introduce `SharedContracts` as a workaround for a transport failure.
