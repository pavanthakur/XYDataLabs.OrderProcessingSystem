import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { auditAzureDeployContract, validateAzureRuntimeTargets } from '../phase10-azure-static-preflight.mjs';

const runtimeTarget = (key, environment) => ({
  key, runtime: 'azure', verificationMode: 'azure', browserMode: 'azure', allowGeneratedAzureUrlFallback: false,
  baseUrl: `https://${environment}.example.test`, apiBaseUrl: `https://api-${environment}.example.test`,
  publicUiBaseUrl: `https://${environment}.example.test`, publicApiBaseUrl: `https://api-${environment}.example.test`,
});

const valid = {
  functionsProject: '<TargetFramework>net8.0</TargetFramework>',
  functionsBicep: `resource hostStorage 'Microsoft.Storage/storageAccounts@2023-05-01' resource hostStorageIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' resource hostStorageBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' scope: hostStorage roleDefinitionId: storageBlobDataOwnerRoleId principalId: hostStorageIdentity.properties.principalId allowBlobPublicAccess: false allowSharedKeyAccess: false minimumTlsVersion: 'TLS1_2' supportsHttpsTrafficOnly: true name: 'WEBSITE_RUN_FROM_PACKAGE' value: '1' name: 'FUNCTIONS_EXTENSION_VERSION' value: '~4' name: 'FUNCTIONS_WORKER_RUNTIME' value: 'dotnet-isolated' name: 'ServiceBusConnection' value: serviceBusConnectionString name: 'ServiceBus__ConnectionString' value: serviceBusConnectionString name: 'AzureWebJobsStorage__accountName' value: hostStorage.name name: 'AzureWebJobsStorage__credential' value: 'managedidentity' name: 'AzureWebJobsStorage__clientId' value: hostStorageIdentity.properties.clientId type: 'SystemAssigned, UserAssigned' userAssignedIdentities: hostStorageIdentity.id dependsOn: [ hostStorageBlobDataOwner`,
  mainBicep: "param functionsHostStorageSkuName string = 'Standard_LRS' hostStorageSkuName: functionsHostStorageSkuName",
  infraDeployWorkflow: 'verify-phase10-release-inputs.mjs releaseRunAttempt approvedParameterIdentity DEPLOYMENT_WORKFLOW_SHA az functionapp deployment source config-zip FUNCTIONS_PACKAGE_SHA256 verify-phase10-function-package-runtime.mjs az functionapp function list image@sha256:[0-9a-f]{64}',
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
  assert.match(validateAzureRuntimeTargets({})[0] ?? '', /targets array/);
});

test('current repository preflight verifies dedicated Functions host storage wiring structurally', async () => {
  const [functionsProject, functionsBicep, mainBicep, infraDeployWorkflow, orchestratorWorkflow, azurePreflightScript, devParameters, stagingParameters, prodParameters, runtimeTargets] = await Promise.all([
    readFile('XYDataLabs.OrderProcessingSystem.Functions/XYDataLabs.OrderProcessingSystem.Functions.csproj', 'utf8'),
    readFile('infra/modules/functions.bicep', 'utf8'),
    readFile('infra/main.phase10.bicep', 'utf8'),
    readFile('.github/workflows/infra-deploy.yml', 'utf8'),
    readFile('.github/workflows/phase10-deploy-orchestrator.yml', 'utf8'),
    readFile('scripts/phase10-azure-preflight.mjs', 'utf8'),
    readFile('infra/parameters/phase10-dev.json', 'utf8').then(JSON.parse),
    readFile('infra/parameters/phase10-staging.json', 'utf8').then(JSON.parse),
    readFile('infra/parameters/phase10-prod.json', 'utf8').then(JSON.parse),
    readFile('automation/config/runtime-targets.json', 'utf8').then(JSON.parse),
  ]);
  const result = auditAzureDeployContract({ functionsProject, functionsBicep, mainBicep, infraDeployWorkflow, orchestratorWorkflow, azurePreflightScript, parameterFiles: { dev: devParameters, staging: stagingParameters, prod: prodParameters }, runtimeTargets });
  assert.equal(result.status, 'PASS');
  assert.deepEqual(result.blocked, []);
});
