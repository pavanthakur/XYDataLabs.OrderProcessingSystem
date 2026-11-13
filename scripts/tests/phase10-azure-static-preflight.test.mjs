import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { auditAzureDeployContract, validateAzureRuntimeTargets } from '../phase10-azure-static-preflight.mjs';

const requireAutomation = createRequire(new URL('../../automation/package.json', import.meta.url));
const yaml = requireAutomation('js-yaml');

const runtimeTarget = (key, environment) => ({
  key, runtime: 'azure', verificationMode: 'azure', browserMode: 'azure', allowGeneratedAzureUrlFallback: false,
  baseUrl: `https://${environment}.example.test`, apiBaseUrl: `https://api-${environment}.example.test`,
  publicUiBaseUrl: `https://${environment}.example.test`, publicApiBaseUrl: `https://api-${environment}.example.test`,
});

const valid = {
  functionsProject: '<TargetFramework>net8.0</TargetFramework>',
  functionsBicep: `resource hostStorage 'Microsoft.Storage/storageAccounts@2023-05-01' resource hostStorageIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' resource hostStorageBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' scope: hostStorage roleDefinitionId: storageBlobDataOwnerRoleId principalId: hostStorageIdentity.properties.principalId allowBlobPublicAccess: false allowSharedKeyAccess: false minimumTlsVersion: 'TLS1_2' supportsHttpsTrafficOnly: true name: 'WEBSITE_RUN_FROM_PACKAGE' value: '1' name: 'FUNCTIONS_EXTENSION_VERSION' value: '~4' name: 'FUNCTIONS_WORKER_RUNTIME' value: 'dotnet-isolated' name: 'ServiceBusConnection' value: serviceBusConnectionString name: 'ServiceBus__ConnectionString' value: serviceBusConnectionString name: 'AzureWebJobsStorage__accountName' value: hostStorage.name name: 'AzureWebJobsStorage__credential' value: 'managedidentity' name: 'AzureWebJobsStorage__clientId' value: hostStorageIdentity.properties.clientId type: 'SystemAssigned, UserAssigned' userAssignedIdentities: hostStorageIdentity.id dependsOn: [ hostStorageBlobDataOwner
  resource app 'Microsoft.Web/sites@2023-12-01' = { name: 'function-app' }
  resource appScm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = { parent: app name: 'scm' properties: { allow: false } }
  resource appFtp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = { parent: app name: 'ftp' properties: { allow: false } }`,
  hostingBicep: `resource apiApp 'Microsoft.Web/sites@2023-12-01' = { name: 'api-app' }
  resource uiApp 'Microsoft.Web/sites@2023-12-01' = { name: 'ui-app' }
  resource apiScm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = { parent: apiApp name: 'scm' properties: { allow: false } }
  resource apiFtp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = { parent: apiApp name: 'ftp' properties: { allow: false } }
  resource uiScm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = { parent: uiApp name: 'scm' properties: { allow: false } }
  resource uiFtp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = { parent: uiApp name: 'ftp' properties: { allow: false } }`,
  functionsPackageVerifier: "execFile('az', ['account', 'get-access-token']); authorization: `Bearer \${accessToken}`",
  mainBicep: "param functionsHostStorageSkuName string = 'Standard_LRS' hostStorageSkuName: functionsHostStorageSkuName",
  infraDeployWorkflow: 'id-token: write uses: azure/login@v3 Azure CLI 2.48.1 or later is required verify-phase10-release-inputs.mjs releaseRunAttempt approvedParameterIdentity DEPLOYMENT_WORKFLOW_SHA az functionapp deployment source config-zip FUNCTIONS_PACKAGE_SHA256 verify-phase10-function-package-runtime.mjs az functionapp function list image@sha256:[0-9a-f]{64}',
  orchestratorWorkflow: 'candidateSha deploymentWorkflowSha git merge-base --is-ancestor ref: ${{ github.sha }} source_hosted_ci_artifact_name deploymentWorkflowSha: ${{ github.sha }} releaseRunId approvedParameterIdentity phase10-azure-preflight.mjs dryRun: default: true',
  azurePreflightScript: 'phase10-azure-preflight.mjs Microsoft.Authorization/roleAssignments/write',
  parameterFiles: {
    dev: { parameters: { functionsHostStorageSkuName: { value: 'Standard_LRS' } } },
    staging: { parameters: { functionsHostStorageSkuName: { value: 'Standard_LRS' } } },
    prod: { parameters: { functionsHostStorageSkuName: { value: 'Standard_GRS' } } },
  },
  runtimeTargets: { targets: [runtimeTarget('azure-dev', 'dev'), runtimeTarget('azure-stg', 'stg'), runtimeTarget('azure-prod', 'prod')] },
};

test('static Azure deployment contract accepts explicit host, transport, immutable release and package settings', () => {
  const result = auditAzureDeployContract(valid);
  assert.equal(result.status, 'PASS', JSON.stringify(result));
});

test('static Azure contract requires every Functions and App Service endpoint to disable publishing Basic auth', () => {
  const functionsPolicyEnabled = auditAzureDeployContract({
    ...valid,
    functionsBicep: valid.functionsBicep.replace('allow: false', 'allow: true'),
  });
  assert.match(functionsPolicyEnabled.failures.join('\n'), /App Service 'app' must explicitly disable SCM basic publishing authentication/);

  const hostingPolicyMissing = auditAzureDeployContract({ ...valid, hostingBicep: valid.hostingBicep.replace(/resource uiFtp[\s\S]*$/, '') });
  assert.match(hostingPolicyMissing.failures.join('\n'), /App Service 'uiApp' must explicitly disable FTP basic publishing authentication/);
});

test('Azure preflight applies the passwordless deployment convention to newly added App Service templates', () => {
  const result = auditAzureDeployContract({
    ...valid,
    infraBicepFiles: [
      { path: 'infra/modules/new-app.bicep', content: "resource futureApp 'Microsoft.Web/sites@2023-12-01' = { name: 'future-app' }" },
    ],
  });
  assert.match(result.failures.join('\n'), /new-app\.bicep: App Service 'futureApp' must explicitly disable SCM basic publishing authentication/);
  assert.match(result.failures.join('\n'), /new-app\.bicep: App Service 'futureApp' must explicitly disable FTP basic publishing authentication/);
});

test('Azure preflight requires OIDC for newly added App Service deployment workflows', () => {
  const result = auditAzureDeployContract({
    ...valid,
    deploymentWorkflows: [{
      path: '.github/workflows/new-webapp.yml',
      content: 'uses: azure/webapps-deploy@v3 publish-profile',
    }],
  });
  assert.match(result.failures.join('\n'), /new-webapp\.yml: App Service deployment must authenticate with GitHub OIDC/);
  assert.match(result.failures.join('\n'), /new-webapp\.yml: App Service deployment must not use or retrieve publishing credentials/);

  const oidcWorkflow = auditAzureDeployContract({
    ...valid,
    deploymentWorkflows: [{
      path: '.github/workflows/new-webapp.yml',
      content: 'permissions: id-token: write uses: azure/login@v3 uses: azure/webapps-deploy@v3',
    }],
  });
  assert.ok(!oidcWorkflow.failures.some((failure) => failure.includes('new-webapp.yml')));
});

test('static Azure contract rejects a publishing-credential fallback in workflow or verifier', () => {
  const basicVerifier = auditAzureDeployContract({ ...valid, functionsPackageVerifier: "az functionapp deployment list-publishing-credentials; authorization: `Basic \\${credentials}`" });
  assert.match(basicVerifier.failures.join('\n'), /Entra Bearer token/);

  const publishProfile = auditAzureDeployContract({ ...valid, infraDeployWorkflow: `${valid.infraDeployWorkflow} publish-profile` });
  assert.match(publishProfile.failures.join('\n'), /GitHub OIDC and Entra CLI deployment/);
});

test('static Azure deployment contract blocks missing dedicated host storage or managed-identity grants without promoting it to PASS', () => {
  const result = auditAzureDeployContract({ ...valid, functionsBicep: valid.functionsBicep.replace("name: 'AzureWebJobsStorage__accountName' value: hostStorage.name", '') });
  assert.equal(result.status, 'BLOCKED');
  assert.match(result.blocked[0], /host storage/);
});

test('static Azure deployment contract blocks public-blob or shared-key host storage and unscoped identity grants', () => {
  const insecureStorage = valid.functionsBicep.replace('allowSharedKeyAccess: false', 'allowSharedKeyAccess: true');
  const result = auditAzureDeployContract({ ...valid, functionsBicep: insecureStorage });
  assert.equal(result.status, 'BLOCKED');
});

test('static Azure deployment contract fails mutable tags, missing worker contract, and missing package verification', () => {
  const result = auditAzureDeployContract({
    ...valid,
    functionsBicep: valid.functionsBicep.replace("name: 'ServiceBusConnection' value: serviceBusConnectionString", ''),
    infraDeployWorkflow: 'image:phase10 az functionapp deployment source config-zip',
  });
  assert.equal(result.status, 'FAIL');
  assert.ok(result.failures.length >= 3);
});

test('static Azure deployment contract requires manual deployment form to default to dry-run', () => {
  const result = auditAzureDeployContract({ ...valid, orchestratorWorkflow: valid.orchestratorWorkflow.replace('default: true', 'default: false') });
  assert.match(result.failures.join('\n'), /default to dry-run/);
});

test('static Azure deployment contract preserves separate source and deployment revisions for promotion', () => {
  const result = auditAzureDeployContract({
    ...valid,
    orchestratorWorkflow: valid.orchestratorWorkflow.replace('deploymentWorkflowSha git merge-base --is-ancestor', 'candidateSha'),
  });
  assert.equal(result.status, 'FAIL');
  assert.match(result.failures.join('\n'), /distinct artifact source SHA/);
  const missingSourceEvidence = auditAzureDeployContract({
    ...valid,
    orchestratorWorkflow: valid.orchestratorWorkflow.replace('source_hosted_ci_artifact_name', 'missing_source_artifact'),
  });
  assert.match(missingSourceEvidence.failures.join('\n'), /validate source and deployment CI evidence/);
});

test('Azure runtime targets require stable HTTPS cloud origins and reject local, emulator and unapproved generated hosts', () => {
  assert.deepEqual(validateAzureRuntimeTargets(valid.runtimeTargets), []);
  for (const value of [
    'http://localhost:5022',
    'https://127.0.0.1',
    'https://azurite:10000',
    'C:\\local\\api',
    'https://app.example.azurecontainerapps.io',
    'https://app.example.azurewebsites.net',
  ]) {
    const broken = structuredClone(valid.runtimeTargets);
    broken.targets[0].publicApiBaseUrl = value;
    assert.ok(validateAzureRuntimeTargets(broken).length > 0, value);
  }
  const diagnostic = structuredClone(valid.runtimeTargets);
  diagnostic.targets[0].allowGeneratedAzureUrlFallback = true;
  diagnostic.targets[0].publicApiBaseUrl = 'https://app.example.azurecontainerapps.io';
  assert.deepEqual(validateAzureRuntimeTargets(diagnostic), []);
  diagnostic.targets[1].allowGeneratedAzureUrlFallback = true;
  diagnostic.targets[1].publicApiBaseUrl = 'https://app.example.azurecontainerapps.io';
  assert.match(validateAzureRuntimeTargets(diagnostic).join(' '), /staging and production/);
  assert.match(validateAzureRuntimeTargets({})[0] ?? '', /targets array/);
});

test('Azure dev alone may resolve generated origins at runtime without committing their suffix', () => {
  const generated = structuredClone(valid.runtimeTargets);
  Object.assign(generated.targets[0], { publicUrlMode: 'generated', allowGeneratedAzureUrlFallback: true,
    baseUrl: '', apiBaseUrl: '', publicUiBaseUrl: '', publicApiBaseUrl: '',
    azureResourceGroupName: 'rg-orderprocessing-dev', azureManagedEnvironmentName: 'aca-orderprocessing-dev',
    azureGatewayContainerAppName: 'orderprocessing-gate-dev', azureUiContainerAppName: 'orderprocessing-ui-dev' });
  assert.deepEqual(validateAzureRuntimeTargets(generated), []);
  generated.targets[0].publicUiBaseUrl = 'https://random.azurecontainerapps.io';
  assert.match(validateAzureRuntimeTargets(generated).join(' '), /must be empty/);
  generated.targets[0].publicUiBaseUrl = '';
  generated.targets[1].publicUrlMode = 'generated';
  assert.match(validateAzureRuntimeTargets(generated).join(' '), /only for explicitly enabled Azure dev/);
});

test('dev hostname bootstrap is manual, dry-run by default, and shares the full-deploy ACA definition', async () => {
  const [workflowText, bootstrap, main, containerApps, environmentModule, catalogText] = await Promise.all([
    readFile('.github/workflows/phase10-dev-hostname-bootstrap.yml', 'utf8'),
    readFile('infra/main.phase10.dev-hostname-bootstrap.bicep', 'utf8'),
    readFile('infra/main.phase10.bicep', 'utf8'),
    readFile('infra/modules/containerapps.bicep', 'utf8'),
    readFile('infra/modules/aca-environment.phase10.bicep', 'utf8'),
    readFile('automation/config/runtime-targets.json', 'utf8'),
  ]);
  const workflow = yaml.load(workflowText);
  assert.equal(workflow.on.workflow_dispatch.inputs.dryRun.default, true);
  assert.equal(workflow.jobs.hostname_bootstrap.if, "github.ref == 'refs/heads/dev'");
  const create = workflow.jobs.hostname_bootstrap.steps.find((step) => step.name === 'Create dev hostname foundation');
  assert.equal(create.if, '${{ !inputs.dryRun }}');
  assert.match(bootstrap, /modules\/aca-environment\.phase10\.bicep/);
  assert.match(main, /modules\/aca-environment\.phase10\.bicep/);
  assert.doesNotMatch(containerApps, /resource acaEnvironment/);
  assert.match(environmentModule, /output defaultDomain string/);
  assert.doesNotMatch(bootstrap, /gatewayImage|sqlAdminPassword|modules\/servicebus|modules\/functions/i);
  assert.doesNotMatch(catalogText, /azurecontainerapps\.io/);
});

test('environment catalog keeps the branch, environment, and resource suffix contract aligned', async () => {
  const policy = JSON.parse(await readFile('Resources/Azure-Deployment/branch-policy.json', 'utf8'));
  assert.deepEqual(Object.fromEntries(Object.entries(policy).map(([key, value]) => [key, [value.branch, value.environment, value.resourceSuffix]])), {
    dev: ['dev', 'dev', 'dev'],
    staging: ['staging', 'staging', 'stg'],
    prod: ['main', 'prod', 'prod'],
  });
  for (const environment of ['dev', 'staging', 'prod']) {
    const parameters = JSON.parse(await readFile(`infra/parameters/phase10-${environment}.json`, 'utf8')).parameters;
    assert.equal(parameters.environment.value, environment);
    assert.equal(parameters.resourceSuffix.value, policy[environment].resourceSuffix);
  }
});

test('current repository preflight verifies dedicated Functions host storage wiring structurally', async () => {
  const [functionsProject, functionsBicep, hostingBicep, functionsPackageVerifier, mainBicep, infraDeployWorkflow, orchestratorWorkflow, azurePreflightScript, devParameters, stagingParameters, prodParameters, runtimeTargets] = await Promise.all([
    readFile('XYDataLabs.OrderProcessingSystem.Functions/XYDataLabs.OrderProcessingSystem.Functions.csproj', 'utf8'),
    readFile('infra/modules/functions.bicep', 'utf8'),
    readFile('infra/modules/hosting.bicep', 'utf8'),
    readFile('scripts/verify-phase10-function-package-runtime.mjs', 'utf8'),
    readFile('infra/main.phase10.bicep', 'utf8'),
    readFile('.github/workflows/infra-deploy.yml', 'utf8'),
    readFile('.github/workflows/phase10-deploy-orchestrator.yml', 'utf8'),
    readFile('scripts/phase10-azure-preflight.mjs', 'utf8'),
    readFile('infra/parameters/phase10-dev.json', 'utf8').then(JSON.parse),
    readFile('infra/parameters/phase10-staging.json', 'utf8').then(JSON.parse),
    readFile('infra/parameters/phase10-prod.json', 'utf8').then(JSON.parse),
    readFile('automation/config/runtime-targets.json', 'utf8').then(JSON.parse),
  ]);
  const result = auditAzureDeployContract({ functionsProject, functionsBicep, hostingBicep, infraBicepFiles: [
    { path: 'infra/modules/functions.bicep', content: functionsBicep },
    { path: 'infra/modules/hosting.bicep', content: hostingBicep },
  ], deploymentWorkflows: [{ path: '.github/workflows/infra-deploy.yml', content: infraDeployWorkflow }], functionsPackageVerifier, mainBicep, infraDeployWorkflow, orchestratorWorkflow, azurePreflightScript, parameterFiles: { dev: devParameters, staging: stagingParameters, prod: prodParameters }, runtimeTargets });
  assert.equal(result.status, 'PASS');
  assert.deepEqual(result.blocked, []);
});

test('deployment parameter identity is recorded before the approval comparison for diagnosable failures', async () => {
  const workflow = await readFile('.github/workflows/phase10-deploy-orchestrator.yml', 'utf8');
  const identityOutput = workflow.indexOf('Calculated deployment parameter identity:');
  const identityComparison = workflow.indexOf('[[ "$calculated" == "$APPROVED_PARAMETER_IDENTITY" ]]');
  assert.notEqual(identityOutput, -1, 'the non-secret calculated identity must appear in the failed job summary');
  assert.ok(identityComparison > identityOutput, 'the calculated identity must be recorded before mismatch can fail the job');
  assert.match(workflow, /Calculated deployment parameter identity:.*\$calculated/);
});

test('deploy and Azure acceptance workflows share a per-environment non-cancelling lease', async () => {
  const workflowPaths = [
    '.github/workflows/phase10-deploy-orchestrator.yml',
    '.github/workflows/phase10-azure-runtime-smoke.yml',
    '.github/workflows/phase10-azure-transport-smoke.yml',
    '.github/workflows/phase10-azure-payment-matrix.yml',
  ];
  for (const workflowPath of workflowPaths) {
    const workflow = yaml.load(await readFile(workflowPath, 'utf8'), { schema: yaml.JSON_SCHEMA, maxAliasCount: 0 });
    assert.deepEqual(workflow.concurrency, {
      group: 'phase10-azure-${{ inputs.environment }}',
      queue: 'max',
      'cancel-in-progress': false,
    }, `${workflowPath} must use the shared lease and never cancel the active run`);
    assert.ok(workflow.on?.workflow_dispatch?.inputs?.environment, `${workflowPath} must key the lease by selected environment`);
  }
});

test('the internal Azure deploy workflow stays caller-owned so it cannot bypass the orchestrator lease', async () => {
  const [internal, orchestrator] = await Promise.all([
    readFile('.github/workflows/infra-deploy.yml', 'utf8'),
    readFile('.github/workflows/phase10-deploy-orchestrator.yml', 'utf8'),
  ]);
  const internalWorkflow = yaml.load(internal, { schema: yaml.JSON_SCHEMA, maxAliasCount: 0 });
  assert.ok(internalWorkflow.on?.workflow_call, 'infra-deploy must remain reusable-only');
  assert.ok(!internalWorkflow.on?.workflow_dispatch, 'infra-deploy must not expose an independent manual route');
  assert.match(orchestrator, /uses:\s*\.\/\.github\/workflows\/infra-deploy\.yml/);
});

test('dry-run routes to validation and what-if only, never deployment token creation or image publication', async () => {
  const [internal, orchestrator] = await Promise.all([
    readFile('.github/workflows/infra-deploy.yml', 'utf8'),
    readFile('.github/workflows/phase10-deploy-orchestrator.yml', 'utf8'),
  ]);
  const workflow = yaml.load(internal, { schema: yaml.JSON_SCHEMA, maxAliasCount: 0 });
  const routeScript = workflow.jobs.route.steps.find((step) => step.id === 'route').run;
  const dryRunBranch = routeScript.match(/elif \[ "\$\{\{ inputs\.dryRun \}\}" = "true" \]; then([\s\S]*?)else/);
  assert.ok(dryRunBranch, 'dry-run branch must remain explicit in the route job');
  assert.match(dryRunBranch[1], /RUN_VALIDATE="true"/);
  assert.match(dryRunBranch[1], /RUN_VALIDATE_ONLY="true"/);
  assert.doesNotMatch(dryRunBranch[1], /RUN_DEPLOY="true"|RUN_CLEANUP="true"/);
  assert.match(workflow.jobs.validate.if, /run_validate == 'true'/);
  assert.match(workflow.jobs.deploy.if, /run_deploy == 'true'/);
  const deploySteps = workflow.jobs.deploy.steps;
  assert.ok(deploySteps.some((step) => step.id === 'acr_pull_token'), 'ACR scoped-token mutation must be isolated to the deploy job');
  assert.match(orchestrator, /dry-run what-if path using prebuilt immutable release/);
  assert.doesNotMatch(orchestrator, /build-phase10-images\.yml/, 'orchestration must not build or publish images during validation');
});
