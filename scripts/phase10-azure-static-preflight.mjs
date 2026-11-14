import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export function validateAzureRuntimeTargets(document) {
  const issues = [];
  const targets = document?.targets;
  if (!Array.isArray(targets)) return ['Runtime target catalog must contain a targets array.'];
  const azureTargets = targets.filter((target) => target?.runtime === 'azure');
  if (azureTargets.length === 0) return ['Runtime target catalog must define at least one Azure target.'];
  for (const target of azureTargets) {
    if (target.verificationMode !== 'azure' || target.browserMode !== 'azure') issues.push(`${target.key}: Azure target must use Azure verification and browser modes.`);
    if (!target.azureReplayRequestQueueName) issues.push(`${target.key}: azureReplayRequestQueueName is required for deployed Functions replay topology.`);
    if (!target.azureSqlServerName || !target.azureOperationsDatabaseName) issues.push(`${target.key}: SQL server and operations database targets are required for fail-closed Functions configuration when SQL deployment is skipped.`);
    if (target.publicUrlMode && !['catalog', 'generated'].includes(target.publicUrlMode)) issues.push(`${target.key}: publicUrlMode is unsupported.`);
    if (target.publicUrlMode === 'generated') {
      if (target.key !== 'azure-dev' || target.allowGeneratedAzureUrlFallback !== true) issues.push(`${target.key}: generated URL mode is permitted only for explicitly enabled Azure dev.`);
      for (const field of ['azureResourceGroupName', 'azureManagedEnvironmentName', 'azureGatewayContainerAppName', 'azureUiContainerAppName']) {
        if (!target[field]) issues.push(`${target.key}: ${field} is required for live generated URL resolution.`);
      }
      for (const field of ['baseUrl', 'apiBaseUrl', 'publicUiBaseUrl', 'publicApiBaseUrl']) {
        if (target[field] !== '') issues.push(`${target.key}: ${field} must be empty in generated URL mode; resolve it from Azure control plane.`);
      }
      continue;
    }
    for (const field of ['baseUrl', 'apiBaseUrl', 'publicUiBaseUrl', 'publicApiBaseUrl']) {
      const value = target[field];
      let url;
      try { url = new URL(value); } catch { issues.push(`${target.key}: ${field} must be an absolute HTTPS URL.`); continue; }
      if (url.protocol !== 'https:') issues.push(`${target.key}: ${field} must use HTTPS.`);
      if (/^(localhost|127(?:\.\d{1,3}){3}|\[::1\])$/i.test(url.hostname) || /(?:azurite|emulator|host\.docker\.internal)/i.test(url.hostname)) {
        issues.push(`${target.key}: ${field} must not point to a local or emulator host.`);
      }
      if (/(?:azurecontainerapps\.io|azurewebsites\.net)$/i.test(url.hostname) && target.allowGeneratedAzureUrlFallback !== true) {
        issues.push(`${target.key}: generated Azure hostname in ${field} requires explicit diagnostic fallback policy.`);
      }
      if (/(?:azurecontainerapps\.io|azurewebsites\.net)$/i.test(url.hostname) && target.key !== 'azure-dev') {
        issues.push(`${target.key}: staging and production require owned custom-domain URLs.`);
      }
    }
  }
  return issues;
}

function hasDisabledBasicPublishingPolicy(bicep, parentName, endpoint) {
  const resourceBlocks = String(bicep ?? '').split(/(?=resource\s+\w+\s+'Microsoft\.Web\/sites\/basicPublishingCredentialsPolicies@)/g);
  const expectedName = "name: '${" + parentName + `}/${endpoint}'`;
  const parentSymbol = parentName.replace(/\.name$/, '');
  const matchingPolicies = resourceBlocks.filter((block) => block.startsWith('resource ')
    && (block.includes(expectedName)
      || (block.includes(`parent: ${parentSymbol}`) && block.includes(`name: '${endpoint}'`))));
  return matchingPolicies.length === 1 && /allow:\s*false\b/.test(matchingPolicies[0]);
}

function validateAppServiceDeploymentWorkflows(workflows = []) {
  const failures = [];
  for (const workflow of workflows) {
    const content = typeof workflow === 'string' ? workflow : workflow.content;
    const label = typeof workflow === 'string' ? '(unknown workflow)' : workflow.path;
    if (!/az\s+(?:webapp\s+deploy|functionapp\s+deployment\s+source\s+config-zip)|azure\/(?:webapps-deploy|functions-action)/i.test(content ?? '')) continue;
    if (!/id-token:\s*write/.test(content ?? '') || !/uses:\s*azure\/login@v\d+/.test(content ?? '')) {
      failures.push(`${label}: App Service deployment must authenticate with GitHub OIDC through azure/login.`);
    }
    if (/publish-profile|list-publishing-credentials|publishing-password|authorization\s*:\s*Basic/i.test(content ?? '')) {
      failures.push(`${label}: App Service deployment must not use or retrieve publishing credentials.`);
    }
  }
  return failures;
}

export function auditAzureDeployContract({ functionsProject, functionsBicep, serviceBusBicep, hostingBicep, infraBicepFiles = [], deploymentWorkflows = [], functionsPackageVerifier, mainBicep, infraDeployWorkflow, orchestratorWorkflow, azurePreflightScript, parameterFiles, runtimeTargets }) {
  const failures = [];
  const blocked = [];
  if (!/TargetFramework>net8\.0<\/TargetFramework>/.test(functionsProject)) failures.push('Functions project must target the validated .NET 8 isolated-worker runtime.');
  if (!/name:\s*'FUNCTIONS_EXTENSION_VERSION'[\s\S]*?value:\s*'~4'/.test(functionsBicep)) failures.push('Function App must explicitly configure Functions host version ~4.');
  if (!/name:\s*'FUNCTIONS_WORKER_RUNTIME'[\s\S]*?value:\s*'dotnet-isolated'/.test(functionsBicep)) failures.push('Function App must explicitly configure the dotnet-isolated worker.');
  if (!/resource\s+app\s+'Microsoft\.Web\/sites@[^']+'[\s\S]*?siteConfig:\s*\{[\s\S]*?alwaysOn:\s*true\b/.test(functionsBicep)) failures.push('Function App on the dedicated App Service plan must set siteConfig.alwaysOn=true so background triggers remain active.');
  if (!/name:\s*'ServiceBusConnection'[\s\S]*?value:\s*serviceBusConnectionString/.test(functionsBicep)) failures.push('Functions trigger connection name ServiceBusConnection must map to the configured Azure Service Bus connection.');
  if (!/name:\s*'ServiceBus__ConnectionString'[\s\S]*?value:\s*serviceBusConnectionString/.test(functionsBicep)) failures.push('Functions application Service Bus configuration must remain present.');
  for (const [name, value] of [
    ['ConnectionStrings__OrderProcessingSystemDbConnection', 'operationsDatabaseConnectionString'],
    ['Phase10DlqTopicName', 'deadLetterTopicName'],
    ['Phase10DlqIntakeSubscriptionName', 'deadLetterSubscriptionName'],
    ['Phase10ReplayRequestQueueName', 'replayRequestQueueName'],
    ['ServiceBus__ReplayRequestQueueName', 'replayRequestQueueName'],
  ]) {
    if (!new RegExp(`name:\\s*'${name}'[\\s\\S]*?value:\\s*${value}`).test(functionsBicep)) {
      failures.push(`Functions must configure ${name} from its authoritative deployment value.`);
    }
  }
  if (!/Authentication=Active Directory Managed Identity/.test(functionsBicep)) {
    failures.push('Functions SQL access must use managed identity rather than a SQL administrator credential.');
  }
  if (!/var\s+sqlConnectionString\s*=\s*deploySql\s*\?\s*'[^']*Authentication=Active Directory Managed Identity;[^']*'\s*:\s*''/.test(mainBicep)) {
    failures.push('Container Apps SQL access must use managed identity; SQL administrator credentials are provisioning-only.');
  }
  if (!/param\s+existingFunctionsSqlServerName\s+string/.test(mainBicep)
    || !/param\s+existingFunctionsSqlDatabaseName\s+string/.test(mainBicep)
    || !/sqlServerFqdn:\s*deploySql\s*\?\s*sql\.outputs\.sqlServerFqdn\s*:\s*'\$\{existingFunctionsSqlServerName\}\.\$\{az\.environment\(\)\.suffixes\.sqlServerHostname\}'/.test(mainBicep)
    || !/sqlDatabaseName:\s*deploySql\s*\?\s*sql\.outputs\.databaseName\s*:\s*existingFunctionsSqlDatabaseName/.test(mainBicep)
    || !/@minLength\(1\)[\s\S]*?param\s+sqlServerFqdn\s+string/.test(functionsBicep)
    || !/@minLength\(1\)[\s\S]*?param\s+sqlDatabaseName\s+string/.test(functionsBicep)) {
    failures.push('Functions must receive nonempty SQL target details from the deployed SQL module or an explicit existing SQL target; blank SQL settings are invalid.');
  }
  for (const name of ['AzureWebJobs.DlqIntakeFunction.Disabled', 'AzureWebJobs.DlqReplayFunction.Disabled']) {
    const settingIndex = functionsBicep.indexOf(`name: '${name}'`);
    const settingBlock = settingIndex < 0 ? '' : functionsBicep.slice(settingIndex, settingIndex + 180);
    if (!settingBlock.includes("value: 'true'")) {
      failures.push(`Functions deployment must pause ${name} until the database identity grant and package checks complete.`);
    }
  }
  if (!/ConnectionStrings__OrderProcessingSystemDbConnection/.test(functionsBicep) || /sqlAdminPassword/.test(functionsBicep)) {
    failures.push('Functions SQL connection must be present and must not contain the SQL administrator password.');
  }
  if (!/param\s+replayRequestQueueName\s+string/.test(mainBicep)
    || !/replayRequestQueueName:\s*serviceBus\.outputs\.replayRequestQueueName/.test(mainBicep)
    || !/output\s+replayRequestQueueName\s+string\s*=\s*serviceBus\.outputs\.replayRequestQueueName/.test(mainBicep)) {
    failures.push('The Phase 10 main template must pass and publish the authoritative replay-request queue name.');
  }
  if (!/resource\s+replayRequestQueue\s+'Microsoft\.ServiceBus\/namespaces\/queues@/.test(serviceBusBicep ?? '')
    || !/output\s+replayRequestQueueName\s+string\s*=\s*replayRequestQueue\.name/.test(serviceBusBicep ?? '')) {
    failures.push('Service Bus IaC must create and output the replay-request queue consumed by Functions and the API.');
  }
  const appServiceTemplates = infraBicepFiles.length ? infraBicepFiles : [
    { path: 'infra/modules/functions.bicep', content: functionsBicep },
    { path: 'infra/modules/hosting.bicep', content: hostingBicep },
  ];
  for (const template of appServiceTemplates) {
    const content = typeof template === 'string' ? template : template.content;
    const label = typeof template === 'string' ? '(unknown template)' : template.path;
    for (const [, symbol] of String(content ?? '').matchAll(/resource\s+(\w+)\s+'Microsoft\.Web\/sites@/g)) {
      for (const endpoint of ['scm', 'ftp']) {
        if (!hasDisabledBasicPublishingPolicy(content, `${symbol}.name`, endpoint)) {
          failures.push(`${label}: App Service '${symbol}' must explicitly disable ${endpoint.toUpperCase()} basic publishing authentication.`);
        }
      }
    }
  }
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
    const replayQueueName = parameters?.replayRequestQueueName?.value;
    const targetKey = environment === 'staging' ? 'azure-stg' : `azure-${environment}`;
    const runtimeTarget = runtimeTargets?.targets?.find((target) => target.key === targetKey);
    if (!replayQueueName || runtimeTarget?.azureReplayRequestQueueName !== replayQueueName) {
      failures.push(`The ${environment} replay queue name must match its runtime-target catalog entry.`);
    }
    if (!runtimeTarget?.azureSqlServerName || !runtimeTarget?.azureOperationsDatabaseName) {
      failures.push(`The ${environment} runtime target must identify the existing SQL server and Operations database for SQL-disabled validation/deployment paths.`);
    }
    if (imageParameterNames.some((name) => Object.hasOwn(parameters ?? {}, name))) {
      failures.push(`The ${environment} parameter file must not select mutable image references; release digests are required at deployment.`);
    }
  }
  if (!/verify-phase10-release-inputs\.mjs/.test(infraDeployWorkflow) || !/releaseRunAttempt/.test(infraDeployWorkflow) || !/approvedParameterIdentity/.test(infraDeployWorkflow)) failures.push('Reusable deployment must verify the named immutable release and parameter identity before cloud authentication.');
  if (!/az functionapp deployment source config-zip/.test(infraDeployWorkflow) || !/FUNCTIONS_PACKAGE_SHA256/.test(infraDeployWorkflow)) failures.push('Reusable deployment must consume the exact hashed Functions package.');
  if (!/verify-phase10-function-package-runtime\.mjs/.test(infraDeployWorkflow) || !/WEBSITE_RUN_FROM_PACKAGE/.test(functionsBicep)) failures.push('Reusable deployment must compare the mounted Functions ZIP bytes with the approved package hash.');
  if (!/account['\"]?,\s*['\"]get-access-token/.test(functionsPackageVerifier ?? '')
    || !/Bearer \$\{accessToken\}/.test(functionsPackageVerifier ?? '')
    || /list-publishing-credentials|Authorization\s*:\s*Basic|authorization:\s*`Basic/i.test(functionsPackageVerifier ?? '')) {
    failures.push('Functions package verification must use an Entra Bearer token and must not retrieve or send publishing credentials.');
  }
  if (!/id-token:\s*write/.test(infraDeployWorkflow) || !/uses:\s*azure\/login@v3/.test(infraDeployWorkflow)
    || /list-publishing-credentials|publish-profile|publishing-password/i.test(infraDeployWorkflow)
    || !/Azure CLI 2\.48\.1 or later is required/.test(infraDeployWorkflow)) {
    failures.push('Azure deployment workflow must use GitHub OIDC and Entra CLI deployment, fail closed on unsupported CLI versions, and contain no publishing-credential fallback.');
  }
  failures.push(...validateAppServiceDeploymentWorkflows(deploymentWorkflows));
  const transportWorkflow = deploymentWorkflows.find((workflow) => /phase10-azure-transport-smoke\.yml$/i.test(workflow.path))?.content ?? '';
  if (!/az functionapp config show[\s\S]*?--query alwaysOn[\s\S]*?refusing to publish transport test messages/.test(transportWorkflow)) failures.push('Azure transport smoke must fail before publishing messages when the Functions host is not always-on.');
  if (!/az functionapp function list/.test(infraDeployWorkflow)) failures.push('Reusable deployment must verify Functions host indexing after package deployment.');
  if (!/az functionapp config show[\s\S]*?--query alwaysOn[\s\S]*?alwaysOn must be true/.test(infraDeployWorkflow)) failures.push('Reusable deployment must verify the Function App always-on setting before accepting the deployed package.');
  if (!/azureOperationsDatabaseName/.test(infraDeployWorkflow)
    || !/azureSqlServerName/.test(infraDeployWorkflow)
    || !/--parameters existingFunctionsSqlServerName=/.test(infraDeployWorkflow)
    || !/--parameters existingFunctionsSqlDatabaseName=/.test(infraDeployWorkflow)) {
    failures.push('Deployment what-if/create must pass existing Functions SQL targets from the runtime target catalog when the SQL module is skipped.');
  }
  const sqlMigrationStep = infraDeployWorkflow.indexOf('name: Run Azure SQL Migrations');
  const sqlIdentityGrantStep = infraDeployWorkflow.indexOf('name: Grant Phase 10 Runtime SQL Managed Identity Access');
  const functionPackageStep = infraDeployWorkflow.indexOf('name: Deploy exact Functions package and verify host indexing');
  const triggerActivationStep = infraDeployWorkflow.indexOf('name: Enable Functions triggers after identity, SQL, and package gates');
  if (sqlMigrationStep < 0 || sqlIdentityGrantStep <= sqlMigrationStep || functionPackageStep <= sqlIdentityGrantStep || triggerActivationStep <= functionPackageStep
    || !infraDeployWorkflow.includes('AzureWebJobs.DlqIntakeFunction.Disabled=false')
    || !infraDeployWorkflow.includes('AzureWebJobs.DlqReplayFunction.Disabled=false')
    || !infraDeployWorkflow.includes('az functionapp config appsettings list')) {
    failures.push('Functions DLQ/replay triggers must remain paused until SQL migrations, runtime identity grants, and exact package/index checks pass, then be enabled and verified.');
  }
  if (/:phase10\b|:latest\b/.test(infraDeployWorkflow) || !/@sha256:\[0-9a-f\]\{64\}/.test(infraDeployWorkflow)) failures.push('Reusable deployment must reject mutable image tags and require digest-qualified references.');
  if (!/candidateSha/.test(orchestratorWorkflow) || !/releaseRunId/.test(orchestratorWorkflow) || !/approvedParameterIdentity/.test(orchestratorWorkflow)) failures.push('Orchestrator must require exact candidate, producer run, and reviewed parameter identity.');
  if (!/deploymentWorkflowSha/.test(orchestratorWorkflow) || !/git merge-base --is-ancestor/.test(orchestratorWorkflow) || !/DEPLOYMENT_WORKFLOW_SHA/.test(infraDeployWorkflow)) {
    failures.push('Release promotion must preserve a distinct artifact source SHA and verify its ancestry to the exact deployment workflow revision.');
  }
  failures.push(...validateAzureRuntimeTargets(runtimeTargets));
  if (!/ref:\s*\$\{\{\s*github\.sha\s*\}\}/.test(orchestratorWorkflow)
    || !/source_hosted_ci_artifact_name/.test(orchestratorWorkflow)
    || !/deploymentWorkflowSha:\s*\$\{\{\s*github\.sha\s*\}\}/.test(orchestratorWorkflow)) {
    failures.push('Promotion must validate source and deployment CI evidence while checking out and forwarding the exact deployment workflow revision.');
  }

  return { status: failures.length ? 'FAIL' : blocked.length ? 'BLOCKED' : 'PASS', failures, blocked };
}

async function main() {
  const root = process.cwd();
  async function collectBicepFiles(directory) {
    const entries = await readdir(directory, { withFileTypes: true });
    const files = await Promise.all(entries.map(async (entry) => {
      const entryPath = path.join(directory, entry.name);
      if (entry.isDirectory()) return collectBicepFiles(entryPath);
      if (entry.isFile() && entry.name.endsWith('.bicep')) return [{ path: path.relative(root, entryPath), content: await readFile(entryPath, 'utf8') }];
      return [];
    }));
    return files.flat();
  }
  async function collectWorkflowFiles(directory) {
    const entries = await readdir(directory, { withFileTypes: true });
    const files = await Promise.all(entries.map(async (entry) => {
      const entryPath = path.join(directory, entry.name);
      if (entry.isDirectory()) return collectWorkflowFiles(entryPath);
      if (entry.isFile() && /\.ya?ml$/i.test(entry.name)) return [{ path: path.relative(root, entryPath), content: await readFile(entryPath, 'utf8') }];
      return [];
    }));
    return files.flat();
  }
  const infraBicepFiles = await collectBicepFiles(path.join(root, 'infra'));
  const deploymentWorkflows = await collectWorkflowFiles(path.join(root, '.github/workflows'));
  const [functionsProject, functionsBicep, serviceBusBicep, hostingBicep, functionsPackageVerifier, mainBicep, infraDeployWorkflow, orchestratorWorkflow, azurePreflightScript, devParameters, stagingParameters, prodParameters, runtimeTargets] = await Promise.all([
    readFile(path.join(root, 'XYDataLabs.OrderProcessingSystem.Functions/XYDataLabs.OrderProcessingSystem.Functions.csproj'), 'utf8'),
    readFile(path.join(root, 'infra/modules/functions.bicep'), 'utf8'),
    readFile(path.join(root, 'infra/modules/servicebus.bicep'), 'utf8'),
    readFile(path.join(root, 'infra/modules/hosting.bicep'), 'utf8'),
    readFile(path.join(root, 'scripts/verify-phase10-function-package-runtime.mjs'), 'utf8'),
    readFile(path.join(root, 'infra/main.phase10.bicep'), 'utf8'),
    readFile(path.join(root, '.github/workflows/infra-deploy.yml'), 'utf8'),
    readFile(path.join(root, '.github/workflows/phase10-deploy-orchestrator.yml'), 'utf8'),
    readFile(path.join(root, 'scripts/phase10-azure-preflight.mjs'), 'utf8'),
    readFile(path.join(root, 'infra/parameters/phase10-dev.json'), 'utf8').then(JSON.parse),
    readFile(path.join(root, 'infra/parameters/phase10-staging.json'), 'utf8').then(JSON.parse),
    readFile(path.join(root, 'infra/parameters/phase10-prod.json'), 'utf8').then(JSON.parse),
    readFile(path.join(root, 'automation/config/runtime-targets.json'), 'utf8').then(JSON.parse),
  ]);
  const result = auditAzureDeployContract({ functionsProject, functionsBicep, serviceBusBicep, hostingBicep, infraBicepFiles, deploymentWorkflows, functionsPackageVerifier, mainBicep, infraDeployWorkflow, orchestratorWorkflow, azurePreflightScript, parameterFiles: { dev: devParameters, staging: stagingParameters, prod: prodParameters }, runtimeTargets });
  for (const failure of result.failures) console.error(`[FAIL] ${failure}`);
  for (const reason of result.blocked) console.error(`[BLOCKED] ${reason}`);
  if (result.status === 'PASS') console.log('[PASS] Azure deployment contract is structurally ready for authorized live preflight.');
  else console.error(`Azure deployment contract status: ${result.status}.`);
  if (result.status !== 'PASS') process.exitCode = 1;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => { console.error(`Azure static preflight could not complete: ${error.message}`); process.exitCode = 1; });
}
