import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export function auditAzureDeployContract({ functionsProject, functionsBicep, mainBicep, infraDeployWorkflow, orchestratorWorkflow, azurePreflightScript, parameterFiles }) {
  const failures = [];
  const blocked = [];
  if (!/TargetFramework>net8\.0<\/TargetFramework>/.test(functionsProject)) failures.push('Functions project must target the validated .NET 8 isolated-worker runtime.');
  if (!/name:\s*'FUNCTIONS_EXTENSION_VERSION'[\s\S]*?value:\s*'~4'/.test(functionsBicep)) failures.push('Function App must explicitly configure Functions host version ~4.');
  if (!/name:\s*'FUNCTIONS_WORKER_RUNTIME'[\s\S]*?value:\s*'dotnet-isolated'/.test(functionsBicep)) failures.push('Function App must explicitly configure the dotnet-isolated worker.');
  if (!/name:\s*'ServiceBusConnection'[\s\S]*?value:\s*serviceBusConnectionString/.test(functionsBicep)) failures.push('Functions trigger connection name ServiceBusConnection must map to the configured Azure Service Bus connection.');
  if (!/name:\s*'ServiceBus__ConnectionString'[\s\S]*?value:\s*serviceBusConnectionString/.test(functionsBicep)) failures.push('Functions application Service Bus configuration must remain present.');
  const storageContractPresent = /resource\s+hostStorage\s+'Microsoft\.Storage\/storageAccounts@/.test(functionsBicep)
    && /resource\s+hostStorageIdentity\s+'Microsoft\.ManagedIdentity\/userAssignedIdentities@/.test(functionsBicep)
    && /resource\s+hostStorageBlobDataOwner\s+'Microsoft\.Authorization\/roleAssignments@/.test(functionsBicep)
    && /scope:\s*hostStorage[\s\S]*?roleDefinitionId:\s*storageBlobDataOwnerRoleId[\s\S]*?principalId:\s*hostStorageIdentity\.properties\.principalId/.test(functionsBicep)
    && /allowBlobPublicAccess:\s*false/.test(functionsBicep)
    && /allowSharedKeyAccess:\s*false/.test(functionsBicep)
    && /minimumTlsVersion:\s*'TLS1_2'[\s\S]*?supportsHttpsTrafficOnly:\s*true/.test(functionsBicep)
    && /name:\s*'AzureWebJobsStorage__accountName'[\s\S]*?value:\s*hostStorage\.name/.test(functionsBicep)
    && /name:\s*'AzureWebJobsStorage__credential'[\s\S]*?value:\s*'managedidentity'/.test(functionsBicep)
    && /name:\s*'AzureWebJobsStorage__clientId'[\s\S]*?value:\s*hostStorageIdentity\.properties\.clientId/.test(functionsBicep)
    && /type:\s*'SystemAssigned, UserAssigned'[\s\S]*?userAssignedIdentities:[\s\S]*?hostStorageIdentity\.id/.test(functionsBicep)
    && /dependsOn:\s*\[[\s\S]*?hostStorageBlobDataOwner/.test(functionsBicep);
  if (!storageContractPresent) blocked.push('Dedicated Functions host storage with a scoped managed-identity role assignment is not configured.');
  if (!/param\s+functionsHostStorageSkuName\s+string/.test(mainBicep) || !/hostStorageSkuName:\s*functionsHostStorageSkuName/.test(mainBicep)) {
    failures.push('The Functions host-storage redundancy setting must be explicit in the deployment contract.');
  }
  if (!/phase10-azure-preflight\.mjs/.test(orchestratorWorkflow) || !/roleAssignments\/write/.test(azurePreflightScript)) {
    failures.push('Azure preflight must check the scoped role-assignment permission required for identity-based Functions storage.');
  }
  if (!/dryRun:[\s\S]*?default:\s*true/.test(orchestratorWorkflow)) failures.push('The manual Azure orchestrator must default to dry-run mode.');
  const imageParameterNames = ['gatewayImage', 'ordersImage', 'paymentsImage', 'inventoryImage', 'notificationsImage', 'uiImage'];
  for (const environment of ['dev', 'staging', 'prod']) {
    const parameters = parameterFiles?.[environment]?.parameters;
    if (!parameters || parameters.functionsHostStorageSkuName?.value !== (environment === 'prod' ? 'Standard_GRS' : 'Standard_LRS')) {
      failures.push(`The ${environment} parameter contract must explicitly select the reviewed Functions host-storage redundancy profile.`);
    }
    if (imageParameterNames.some((name) => Object.hasOwn(parameters ?? {}, name))) {
      failures.push(`The ${environment} parameter file must not select mutable image references; release digests are required at deployment.`);
    }
  }
  if (!/verify-phase10-release-inputs\.mjs/.test(infraDeployWorkflow) || !/releaseRunAttempt/.test(infraDeployWorkflow) || !/approvedParameterIdentity/.test(infraDeployWorkflow)) failures.push('Reusable deployment must verify the named immutable release and parameter identity before cloud authentication.');
  if (!/az functionapp deployment source config-zip/.test(infraDeployWorkflow) || !/FUNCTIONS_PACKAGE_SHA256/.test(infraDeployWorkflow)) failures.push('Reusable deployment must consume the exact hashed Functions package.');
  if (!/verify-phase10-function-package-runtime\.mjs/.test(infraDeployWorkflow) || !/WEBSITE_RUN_FROM_PACKAGE/.test(functionsBicep)) failures.push('Reusable deployment must compare the mounted Functions ZIP bytes with the approved package hash.');
  if (!/az functionapp function list/.test(infraDeployWorkflow)) failures.push('Reusable deployment must verify Functions host indexing after package deployment.');
  if (/:phase10\b|:latest\b/.test(infraDeployWorkflow) || !/@sha256:\[0-9a-f\]\{64\}/.test(infraDeployWorkflow)) failures.push('Reusable deployment must reject mutable image tags and require digest-qualified references.');
  if (!/candidateSha/.test(orchestratorWorkflow) || !/releaseRunId/.test(orchestratorWorkflow) || !/approvedParameterIdentity/.test(orchestratorWorkflow)) failures.push('Orchestrator must require exact candidate, producer run, and reviewed parameter identity.');

  return { status: failures.length ? 'FAIL' : blocked.length ? 'BLOCKED' : 'PASS', failures, blocked };
}

async function main() {
  const root = process.cwd();
  const [functionsProject, functionsBicep, mainBicep, infraDeployWorkflow, orchestratorWorkflow, azurePreflightScript, devParameters, stagingParameters, prodParameters] = await Promise.all([
    readFile(path.join(root, 'XYDataLabs.OrderProcessingSystem.Functions/XYDataLabs.OrderProcessingSystem.Functions.csproj'), 'utf8'),
    readFile(path.join(root, 'infra/modules/functions.bicep'), 'utf8'),
    readFile(path.join(root, 'infra/main.phase10.bicep'), 'utf8'),
    readFile(path.join(root, '.github/workflows/infra-deploy.yml'), 'utf8'),
    readFile(path.join(root, '.github/workflows/phase10-deploy-orchestrator.yml'), 'utf8'),
    readFile(path.join(root, 'scripts/phase10-azure-preflight.mjs'), 'utf8'),
    readFile(path.join(root, 'infra/parameters/phase10-dev.json'), 'utf8').then(JSON.parse),
    readFile(path.join(root, 'infra/parameters/phase10-staging.json'), 'utf8').then(JSON.parse),
    readFile(path.join(root, 'infra/parameters/phase10-prod.json'), 'utf8').then(JSON.parse),
  ]);
  const result = auditAzureDeployContract({ functionsProject, functionsBicep, mainBicep, infraDeployWorkflow, orchestratorWorkflow, azurePreflightScript, parameterFiles: { dev: devParameters, staging: stagingParameters, prod: prodParameters } });
  for (const failure of result.failures) console.error(`[FAIL] ${failure}`);
  for (const reason of result.blocked) console.error(`[BLOCKED] ${reason}`);
  if (result.status === 'PASS') console.log('[PASS] Azure deployment contract is structurally ready for authorized live preflight.');
  else console.error(`Azure deployment contract status: ${result.status}.`);
  if (result.status !== 'PASS') process.exitCode = 1;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => { console.error(`Azure static preflight could not complete: ${error.message}`); process.exitCode = 1; });
}
