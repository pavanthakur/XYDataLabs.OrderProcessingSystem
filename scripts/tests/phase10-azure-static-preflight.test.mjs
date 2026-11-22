import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { auditAzureDeployContract, validateAzureRuntimeTargets } from '../phase10-azure-static-preflight.mjs';
import { verifyFunctionsSqlEndpoint } from '../verify-phase10-functions-sql-endpoint.mjs';
import { validateLocalDlqApprovalResponse, validateLocalOperatorClaims } from '../../frontend/apps/web/scripts/phase10-local-dlq-approval-contract.mjs';
import { normalizeKeyVaultAccessPolicies } from '../normalize-phase10-keyvault-access-policies.mjs';

const requireAutomation = createRequire(new URL('../../automation/package.json', import.meta.url));
const yaml = requireAutomation('js-yaml');
const verifierSource = await readFile(new URL('../verify-payment-run-azure.ps1', import.meta.url), 'utf8');
const paymentWorkflowSource = await readFile(new URL('../../.github/workflows/phase10-azure-payment-matrix.yml', import.meta.url), 'utf8');
const matrixRunnerSource = await readFile(new URL('../../automation/src/cli/run-azure-matrix.ts', import.meta.url), 'utf8');
const replaySqlVerifierSource = await readFile(new URL('../verify-phase10-azure-dlq-replay.ps1', import.meta.url), 'utf8');
const releaseInputVerifierSource = await readFile(new URL('../verify-phase10-release-inputs.mjs', import.meta.url), 'utf8');

test('desktop Playwright tasks show the active subscription in their own terminal and confirm before resource calls', async () => {
  const ts = requireAutomation('typescript');
  const taskSource = await readFile(new URL('../../.vscode/tasks.json', import.meta.url), 'utf8');
  const parsed = ts.parseConfigFileTextToJson('tasks.json', taskSource);
  assert.equal(parsed.error, undefined);
  const { tasks } = parsed.config;
  const expectedEntry = '${workspaceFolder}/scripts/run-phase10-azure-dev-operator-matrix.ps1';
  const preflight = tasks.filter(task => task.label === '5 Run: Azure Dev 01 Playwright Auth Preflight (No Payments)');
  const matrix = tasks.filter(task => task.label === '5 Run: Azure Dev 02 Playwright Provider Matrix (Submits Sandbox Payments)');
  assert.equal(tasks.some(task => task.label?.startsWith('5 Run: Azure Dev 00 ')), false);
  assert.equal(preflight.length, 1);
  assert.equal(matrix.length, 1);
  for (const [task, mode] of [[preflight[0], 'AuthPreflight'], [matrix[0], 'ProviderMatrix']]) {
    assert.equal(task.type, 'process');
    assert.equal(task.command, 'pwsh');
    assert.deepEqual(task.args, ['-NoProfile', '-File', expectedEntry, '-Mode', mode,
      '-PromptForExpectedSubscriptionId',
      ...(mode === 'ProviderMatrix' ? ['-RequireSandboxConfirmation'] : [])]);
    assert.equal(task.dependsOn, undefined);
    assert.equal(task.runOptions?.runOn, undefined);
  }
  assert.ok(tasks.every(task => !task.dependsOn?.includes?.(matrix[0].label)));
  const runner = await readFile(new URL('../run-phase10-azure-dev-operator-matrix.ps1', import.meta.url), 'utf8');
  const lookup = runner.indexOf('& az account show');
  const display = runner.indexOf('Write-Host "Active Azure CLI subscription ID:');
  const prompt = runner.indexOf("$answer = Read-Host 'Verify the ID above");
  const guard = runner.indexOf("$confirmation -cne 'RUN SANDBOX'");
  const resourceCall = runner.indexOf('& az containerapp env show');
  assert.ok(lookup >= 0 && lookup < display && display < prompt && prompt < guard && guard < resourceCall);
  assert.match(runner.slice(prompt, resourceCall), /\$activeSubscription -ne \$ExpectedSubscriptionId/);
  assert.match(runner.slice(guard, resourceCall), /\(Get-ActiveAzureSubscription\) -ne \$ExpectedSubscriptionId/);
});

test('Azure operator checkpoint and launch safety regressions execute in hosted contract CI', () => {
  const environment = { ...process.env };
  delete environment.NODE_TEST_CONTEXT;
  const output = execFileSync(process.execPath, [
    fileURLToPath(new URL('../../automation/node_modules/tsx/dist/cli.mjs', import.meta.url)), '--test',
    fileURLToPath(new URL('../../automation/src/support/azure-matrix-checkpoint.test.ts', import.meta.url)),
    fileURLToPath(new URL('../../automation/src/support/payment-case-ledger.test.ts', import.meta.url)),
    fileURLToPath(new URL('../../automation/src/support/reconcile-payment-checkpoint.test.ts', import.meta.url)),
    fileURLToPath(new URL('../../automation/src/verification/payment-verification-report.test.ts', import.meta.url)),
    fileURLToPath(new URL('../../automation/src/contracts/payment-scenarios.test.ts', import.meta.url)),
    fileURLToPath(new URL('../../automation/src/cli/dry-run-reporting.test.ts', import.meta.url)),
    fileURLToPath(new URL('../../automation/src/browser/local-browser-launch.test.ts', import.meta.url))
  ], { encoding: 'utf8', env: environment });
  assert.match(output, /# fail 0/);
  const paidOrderOutput=execFileSync('pwsh',['-NoProfile','-File',fileURLToPath(new URL('./phase10-paid-order-evidence.test.ps1',import.meta.url))],{encoding:'utf8'});
  assert.match(paidOrderOutput,/Paid-order evidence tests passed/);
});

test('read-only Razorpay order lookup is sandbox-only and does not route to the payment matrix', async () => {
  const workflow = yaml.load(paymentWorkflowSource);
  const steps = workflow.jobs.azure_payment_matrix.steps;
  const matrix = steps.find((step) => step.name === 'Run no-payment service preflight');
  assert.equal(matrix.if, "inputs.runMode == 'service-preflight'");
  const lookup = steps.find((step) => step.name === 'Read existing Razorpay order and payments (no charge)');
  assert.equal(lookup.if, "inputs.runMode == 'razorpay-order-lookup'");
  assert.match(lookup.run, /lookup-phase10-azure-razorpay-order\.ps1/);
  assert.doesNotMatch(lookup.run, /ProcessPayment|capture|refund|--value/);
  const core = await readFile(new URL('../phase10-razorpay-order-lookup-core.ps1', import.meta.url), 'utf8');
  assert.match(core, /-Method Get -MaximumRedirection 0/);
  assert.match(core, /rzp_test_/);
  assert.match(core, /Select-Object id, status, amount, currency/);
  const entry = await readFile(new URL('../lookup-phase10-azure-razorpay-order.ps1', import.meta.url), 'utf8');
  assert.match(entry, /refs\/heads\/dev/);
  assert.match(entry, /ExpectedSubscriptionId/);
  assert.match(entry, /PaymentProviders--\$TenantCode--Razorpay--PrivateKey/);
  const output = execFileSync('pwsh', ['-NoProfile', '-File', fileURLToPath(new URL('./phase10-razorpay-order-lookup.test.ps1', import.meta.url))], { encoding: 'utf8' });
  assert.match(output, /Passed 10 read-only provider diagnostic tests/);
});

const runtimeTarget = (key, environment) => ({
  key, runtime: 'azure', verificationMode: 'azure', browserMode: 'azure', allowGeneratedAzureUrlFallback: false,
  baseUrl: `https://${environment}.example.test`, apiBaseUrl: `https://api-${environment}.example.test`,
  publicUiBaseUrl: `https://${environment}.example.test`, publicApiBaseUrl: `https://api-${environment}.example.test`,
  azureReplayRequestQueueName: `dlq-replay-requests-${environment}`,
  azureSqlServerName: `orderprocessing-sql-${environment}`,
  azureOperationsDatabaseName: environment === 'stg' ? 'OrderProcessingSystem_Staging' : `OrderProcessingSystem_${environment === 'prod' ? 'Prod' : 'Dev'}`,
});

const valid = {
  functionsProject: '<TargetFramework>net8.0</TargetFramework>',
  functionsBicep: `resource hostStorage 'Microsoft.Storage/storageAccounts@2023-05-01' resource hostStorageIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' resource hostStorageBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' scope: hostStorage roleDefinitionId: storageBlobDataOwnerRoleId principalId: hostStorageIdentity.properties.principalId allowBlobPublicAccess: false allowSharedKeyAccess: false minimumTlsVersion: 'TLS1_2' supportsHttpsTrafficOnly: true name: 'WEBSITE_RUN_FROM_PACKAGE' value: '1' name: 'FUNCTIONS_EXTENSION_VERSION' value: '~4' name: 'FUNCTIONS_WORKER_RUNTIME' value: 'dotnet-isolated' name: 'ServiceBusConnection' value: serviceBusConnectionString name: 'ServiceBus__ConnectionString' value: serviceBusConnectionString name: 'AzureWebJobsStorage__accountName' value: hostStorage.name name: 'AzureWebJobsStorage__credential' value: 'managedidentity' name: 'AzureWebJobsStorage__clientId' value: hostStorageIdentity.properties.clientId name: 'ConnectionStrings__OrderProcessingSystemDbConnection' value: operationsDatabaseConnectionString name: 'Phase10DlqTopicName' value: deadLetterTopicName name: 'Phase10DlqIntakeSubscriptionName' value: deadLetterSubscriptionName name: 'Phase10ReplayRequestQueueName' value: replayRequestQueueName name: 'ServiceBus__ReplayRequestQueueName' value: replayRequestQueueName Authentication=Active Directory Managed Identity type: 'SystemAssigned, UserAssigned' userAssignedIdentities: hostStorageIdentity.id dependsOn: [ hostStorageBlobDataOwner
  resource app 'Microsoft.Web/sites@2023-12-01' = { name: 'function-app' siteConfig: { alwaysOn: true } }
  resource appScm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = { parent: app name: 'scm' properties: { allow: false } }
  resource appFtp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = { parent: app name: 'ftp' properties: { allow: false } }`,
  hostingBicep: `resource apiApp 'Microsoft.Web/sites@2023-12-01' = { name: 'api-app' }
  resource uiApp 'Microsoft.Web/sites@2023-12-01' = { name: 'ui-app' }
  resource apiScm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = { parent: apiApp name: 'scm' properties: { allow: false } }
  resource apiFtp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = { parent: apiApp name: 'ftp' properties: { allow: false } }
  resource uiScm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = { parent: uiApp name: 'scm' properties: { allow: false } }
  resource uiFtp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = { parent: uiApp name: 'ftp' properties: { allow: false } }`,
  serviceBusBicep: "resource replayRequestQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' output replayRequestQueueName string = replayRequestQueue.name",
  functionsPackageVerifier: "execFile('az', ['account', 'get-access-token']); authorization: `Bearer \${accessToken}`",
  mainBicep: "param functionsHostStorageSkuName string = 'Standard_LRS' hostStorageSkuName: functionsHostStorageSkuName param replayRequestQueueName string replayRequestQueueName: serviceBus.outputs.replayRequestQueueName output replayRequestQueueName string = serviceBus.outputs.replayRequestQueueName",
  infraDeployWorkflow: 'id-token: write uses: azure/login@v3 Azure CLI 2.48.1 or later is required verify-phase10-release-inputs.mjs releaseRunAttempt approvedParameterIdentity DEPLOYMENT_WORKFLOW_SHA ACTIVATE_EXISTING_FUNCTIONS_TRIGGERS: ${{ inputs.activateExistingFunctionsTriggers }} ACTIVATE_EXISTING_FUNCTIONS_TRIGGERS: ${{ inputs.activateExistingFunctionsTriggers }} az functionapp deployment source config-zip FUNCTIONS_PACKAGE_SHA256 verify-phase10-function-package-runtime.mjs az functionapp function list az functionapp config show --query alwaysOn alwaysOn must be true azureSqlServerName azureOperationsDatabaseName --parameters existingFunctionsSqlServerName= --parameters existingFunctionsSqlDatabaseName= name: Get Deployment Outputs name: Verify Functions SQL endpoint matches Azure SQL host az sql server show --query fullyQualifiedDomainName ConnectionStrings__OrderProcessingSystemDbConnection scripts/verify-phase10-functions-sql-endpoint.mjs name: Verify SQL Entra administrator before migrations az sql server ad-admin show actual_sid EXPECTED_SQL_ENTRA_ADMIN_OBJECT_ID actual_login EXPECTED_SQL_ENTRA_ADMIN_LOGIN name: Run Azure SQL Migrations name: Grant Phase 10 Runtime SQL Managed Identity Access name: Deploy exact Functions package and verify host indexing name: Enable Functions triggers after database and package gates AzureWebJobs.DlqIntakeFunction.Disabled=false AzureWebJobs.DlqReplayFunction.Disabled=false az functionapp config appsettings list image@sha256:[0-9a-f]{64}',
  deploymentWorkflows: [{ path: '.github/workflows/phase10-azure-transport-smoke.yml', content: 'az functionapp config show --query alwaysOn refusing to publish transport test messages intake_disabled=az functionapp config appsettings list AzureWebJobs.DlqIntakeFunction.Disabled [[ "$intake_disabled" == "false" ]] || { echo "DlqIntakeFunction is disabled or its state is unknown; refusing to publish transport/DLQ smoke messages."; exit 1; }' }],
  orchestratorWorkflow: 'candidateSha deploymentWorkflowSha git merge-base --is-ancestor ref: ${{ github.sha }} source_hosted_ci_artifact_name deploymentWorkflowSha: ${{ github.sha }} releaseRunId approvedParameterIdentity phase10-azure-preflight.mjs activateExistingFunctionsTriggers: ${{ inputs.activateExistingFunctionsTriggers }} ACTIVATE_EXISTING_FUNCTIONS_TRIGGERS: ${{ inputs.activateExistingFunctionsTriggers }} --activateExistingFunctionsTriggers "$ACTIVATE_EXISTING_FUNCTIONS_TRIGGERS" dryRun: default: true',
  azurePreflightScript: 'phase10-azure-preflight.mjs Microsoft.Authorization/roleAssignments/write',
  parameterFiles: {
    dev: { parameters: { functionsHostStorageSkuName: { value: 'Standard_LRS' }, replayRequestQueueName: { value: 'dlq-replay-requests-dev' } } },
    staging: { parameters: { functionsHostStorageSkuName: { value: 'Standard_LRS' }, replayRequestQueueName: { value: 'dlq-replay-requests-stg' } } },
    prod: { parameters: { functionsHostStorageSkuName: { value: 'Standard_GRS' }, replayRequestQueueName: { value: 'dlq-replay-requests-prod' } } },
  },
  runtimeTargets: { targets: [runtimeTarget('azure-dev', 'dev'), runtimeTarget('azure-stg', 'stg'), runtimeTarget('azure-prod', 'prod')] },
};

valid.infraDeployWorkflow += [
  '',
  '  deploy:',
  '    steps:',
  '      - name: Determine parameters',
  '        env:',
  '          SQL_ENTRA_ADMIN_OBJECT_ID: ${{ vars.SQL_ENTRA_ADMIN_OBJECT_ID }}',
  '          SQL_ENTRA_ADMIN_LOGIN: ${{ vars.SQL_ENTRA_ADMIN_LOGIN }}',
  '        run: |',
  '          echo "deploySql=${{ inputs.deploySql }}" >> $GITHUB_OUTPUT',
  '          echo "deployRedis=${{ inputs.deployRedis }}" >> $GITHUB_OUTPUT',
  '          echo "activateExistingFunctionsTriggers=${{ inputs.activateExistingFunctionsTriggers }}" >> $GITHUB_OUTPUT',
  '          [[ "${{ inputs.environment }}" == "dev" && "${{ inputs.deploySql }}" == "false" && "${{ inputs.cleanupInfra }}" == "false" && "${{ inputs.dryRun }}" == "false" ]] || activationGuard',
  '        if: ${{ steps.params.outputs.deploySql == \'true\' || steps.params.outputs.activateExistingFunctionsTriggers == \'true\' }}',
  '          if [ "${{ inputs.deploySql }}" = "true" ]; then',
  '            [[ "$SQL_ENTRA_ADMIN_OBJECT_ID" =~ ^[0-9a-fA-F-]{36}$ && -n "$SQL_ENTRA_ADMIN_LOGIN" ]] || { echo "SQL_ENTRA_ADMIN_OBJECT_ID and SQL_ENTRA_ADMIN_LOGIN must be configured as environment variables before deploying SQL." >&2; exit 1; }',
  '            echo "aadAdminObjectId=${SQL_ENTRA_ADMIN_OBJECT_ID}" >> $GITHUB_OUTPUT',
  '            echo "aadAdminLogin=${SQL_ENTRA_ADMIN_LOGIN}" >> $GITHUB_OUTPUT',
  '          fi',
  '      - name: Resolve SQL bootstrap credential',
  '        run: bash scripts/resolve-phase10-sql-bootstrap-credential.sh',
  '      - name: Verify existing SQL bootstrap login before updating SQL',
  '      - name: Deploy (subscription scope)',
  '        run: az deployment sub create',
  '      - name: Verify deployed SQL bootstrap login and Key Vault read-back',
  '        run: ./Resources/Azure-Deployment/Test-Phase10SqlBootstrapLogin.ps1 -VerifyVault',
  '      - name: Run Azure SQL Migrations',
  '      - name: Snapshot existing Functions trigger state before ARM deployment',
  '      - name: Restore existing Functions trigger state after routine redeploy',
  "        if: ${{ steps.params.outputs.deploySql != 'true' && steps.params.outputs.activateExistingFunctionsTriggers != 'true' }}",
  '        run: AzureWebJobs.DlqIntakeFunction.Disabled=$INTAKE_DISABLED AzureWebJobs.DlqReplayFunction.Disabled=$REPLAY_DISABLED Could not restore existing Functions setting',
].join('\n');
valid.infraDeployWorkflow = valid.infraDeployWorkflow.replace('az sql server ad-admin show', 'az sql server ad-admin list');

valid.functionsBicep = `@minLength(1) param sqlServerFqdn string @minLength(1) param sqlDatabaseName string ${valid.functionsBicep} name: 'AzureWebJobs.DlqIntakeFunction.Disabled' value: 'true' name: 'AzureWebJobs.DlqReplayFunction.Disabled' value: 'true'`;
valid.mainBicep += " param existingFunctionsSqlServerName string param existingFunctionsSqlDatabaseName string var existingFunctionsSqlServerFqdn = replace('${existingFunctionsSqlServerName}.${az.environment().suffixes.sqlServerHostname}', '..', '.') sqlServerFqdn: deploySql ? sql.outputs.sqlServerFqdn : existingFunctionsSqlServerFqdn output sqlServerFqdn string = deploySql ? sql.outputs.sqlServerFqdn : existingFunctionsSqlServerFqdn sqlDatabaseName: deploySql ? sql.outputs.databaseName : existingFunctionsSqlDatabaseName";
valid.mainBicep += " var sqlConnectionString = deploySql ? 'Server=tcp:sql.database.windows.net;Authentication=Active Directory Managed Identity;' : ''";

test('static Azure deployment contract accepts explicit host, transport, immutable release and package settings', () => {
  const result = auditAzureDeployContract(valid);
  assert.equal(result.status, 'PASS', JSON.stringify(result));
});

test('Functions SQL endpoint verifier normalizes Azure suffix dots and rejects mismatches without exposing secrets', () => {
  const matching = verifyFunctionsSqlEndpoint({
    deploymentSqlFqdn: 'orderprocessing-sql-dev.database.windows.net',
    sqlResourceFqdn: 'orderprocessing-sql-dev.database.windows.net.',
    functionsSqlConnection: 'Server=tcp:orderprocessing-sql-dev.database.windows.net,1433;Initial Catalog=orders;Password=do-not-print',
  });
  assert.equal(matching.ok, true);
  assert.equal(matching.message, 'Functions SQL endpoint matches the deployed Azure SQL server (credential values not emitted).');
  const cliOutput = execFileSync(process.execPath, [fileURLToPath(new URL('../verify-phase10-functions-sql-endpoint.mjs', import.meta.url))], {
    input: 'orderprocessing-sql-dev.database.windows.net\norderprocessing-sql-dev.database.windows.net\nServer=tcp:orderprocessing-sql-dev.database.windows.net,1433;Password=do-not-print',
    encoding: 'utf8',
  });
  assert.match(cliOutput, /credential values not emitted/);
  assert.doesNotMatch(cliOutput, /do-not-print|Password/i);

  const mismatch = verifyFunctionsSqlEndpoint({
    deploymentSqlFqdn: 'orderprocessing-sql-dev.database.windows.net',
    sqlResourceFqdn: 'orderprocessing-sql-dev.database.windows.net',
    functionsSqlConnection: 'Server=tcp:other.database.windows.net,1433;Password=do-not-print',
  });
  assert.equal(mismatch.ok, false);
  assert.doesNotMatch(mismatch.message, /do-not-print|Password/i);
  assert.throws(() => execFileSync(process.execPath, [fileURLToPath(new URL('../verify-phase10-functions-sql-endpoint.mjs', import.meta.url))], {
    input: 'orderprocessing-sql-dev.database.windows.net\norderprocessing-sql-dev.database.windows.net\nServer=tcp:other.database.windows.net,1433;Password=do-not-print',
    encoding: 'utf8',
  }), (error) => {
    assert.match(String(error.stderr), /Functions SQL endpoint does not match/);
    assert.doesNotMatch(String(error.stderr), /do-not-print|Password/i);
    return true;
  });

  const malformed = verifyFunctionsSqlEndpoint({
    deploymentSqlFqdn: 'orderprocessing-sql-dev..database.windows.net',
    sqlResourceFqdn: 'orderprocessing-sql-dev.database.windows.net',
    functionsSqlConnection: 'Server=tcp:orderprocessing-sql-dev.database.windows.net,1433;Password=do-not-print',
  });
  assert.equal(malformed.ok, false);
});

const resolverBash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';
test('SQL bootstrap resolver distinguishes new, existing and unverified Azure state', {
  skip: process.platform === 'win32' && !existsSync(resolverBash),
}, () => {
  const output = execFileSync(resolverBash, ['scripts/tests/phase10-sql-bootstrap-credential.test.sh'], {
    cwd: fileURLToPath(new URL('../../', import.meta.url)), encoding: 'utf8',
  });
  assert.match(output, /5 mocked cases passed/);
});

test('Azure deploy contract requires the runtime deployment job to forward and validate SQL Entra admin inputs', () => {
  const missingRuntimeJobMapping = auditAzureDeployContract({
    ...valid,
    infraDeployWorkflow: valid.infraDeployWorkflow.replace('          SQL_ENTRA_ADMIN_OBJECT_ID: ${{ vars.SQL_ENTRA_ADMIN_OBJECT_ID }}', ''),
  });
  assert.match(missingRuntimeJobMapping.failures.join('\n'), /deployment job must forward its explicit SQL\/Redis selections, pass and validate the configured SQL Entra administrator/);

  const missingDeployedAdminVerification = auditAzureDeployContract({
    ...valid,
    infraDeployWorkflow: valid.infraDeployWorkflow.replace('name: Verify SQL Entra administrator before migrations', ''),
  });
  assert.match(missingDeployedAdminVerification.failures.join('\n'), /SQL Entra administrator must be verified before migrations/);
  const missingSqlEndpointVerification = auditAzureDeployContract({
    ...valid,
    infraDeployWorkflow: valid.infraDeployWorkflow.replace('name: Verify Functions SQL endpoint matches Azure SQL host', ''),
  });
  assert.match(missingSqlEndpointVerification.failures.join('\n'), /compare the Function SQL connection host, ARM output, and Azure SQL resource FQDN/);
  const missingVaultProbe = auditAzureDeployContract({
    ...valid,
    infraDeployWorkflow: valid.infraDeployWorkflow.replace('name: Verify deployed SQL bootstrap login and Key Vault read-back', ''),
  });
  assert.match(missingVaultProbe.failures.join('\n'), /verify Key Vault read-back and login before migrations/);
});

test('Azure payment verifier treats dedicated tenants generically instead of hardcoding TenantC', () => {
  assert.doesNotMatch(verifierSource, /q[25]TenantC|preflightTenantC|tenantCDbChargeIds/);
  assert.match(verifierSource, /foreach \(\$tenant in \$dedicatedTenants\)/);
  assert.match(verifierSource, /DedicatedDatabaseName = \$dedicatedDatabaseName/);
});

test('Azure payment verifier de-duplicates SQL history fallback rows and validates history integrity', () => {
  assert.match(verifierSource, /tsh\.Id AS HistoryId/);
  assert.match(verifierSource, /Sort-Object Tenant, CustomerOrderId, HistoryId -Unique/);
  assert.match(verifierSource, /PaymentHistoryEvidence = @\(\$allHistoryRows/);
  assert.match(verifierSource, /function Get-HistoryIntegrityForTenant/);
  assert.match(verifierSource, /TerminalStatusMismatchCount/);
  assert.match(verifierSource, /MissingHistoryCount -eq 0/);
});

test('Azure payment workflow runs service-access preflight before the browser payment matrix', () => {
  const preflightIndex = matrixRunnerSource.indexOf('runAzureVerificationServicePreflight({');
  const paymentIndex = matrixRunnerSource.indexOf('executePaymentAutomationRun({');
  assert.ok(preflightIndex >= 0 && paymentIndex > preflightIndex, 'service preflight must precede browser payment execution');
  assert.match(matrixRunnerSource, /"-PreflightOnly"/);
  assert.match(matrixRunnerSource, /No browser journey or payment was started/);
  assert.match(paymentWorkflowSource, /EXPECTED_AZURE_SUBSCRIPTION_ID: \$\{\{ secrets\.AZUREAPPSERVICE_SUBSCRIPTIONID \}\}/);
  assert.match(paymentWorkflowSource, /\$topologyParameters = @\{[\s\S]*?Environment = '\$\{\{ inputs\.environment \}\}'[\s\S]*?\}/);
  assert.match(paymentWorkflowSource, /if \('\$\{\{ inputs\.environment \}\}' -eq 'dev'\) \{ \$topologyParameters\.RequiredProviderCodes = @\('Razorpay', 'OpenPay'\) \}/);
  assert.match(paymentWorkflowSource, /verify-phase10-azure-tenant-topology\.ps1\s+@topologyParameters/);
});

test('hosted service-preflight-only mode is dev-only and cannot reach payment automation', () => {
  const preflightGuard = matrixRunnerSource.indexOf('if (options.servicePreflightOnly) {');
  const paymentExecution = matrixRunnerSource.indexOf('executePaymentAutomationRun({');
  const workflow = yaml.load(paymentWorkflowSource);
  assert.equal(workflow.on.workflow_dispatch.inputs.runMode.default, 'service-preflight');
  assert.deepEqual(workflow.on.workflow_dispatch.inputs.environment.options, ['dev']);
  const steps = workflow.jobs.azure_payment_matrix.steps;
  assert.match(steps.find(step => step.name === 'Run no-payment service preflight').run, /--service-preflight-only\s*\n/);
  assert.doesNotMatch(paymentWorkflowSource, /playwright install|--skip-verification|--operator-assisted-entra/);
  assert.match(paymentWorkflowSource, /temporary SQL firewall lease/);
  assert.match(steps.find(step => step.name === 'Validate hosted Azure-dev run selection').run, /requires branch dev and environment dev/);
  assert.equal(steps.find(step => step.name === 'Ensure payment verifier firewall leases are cleaned').if, "always() && steps.azure_login.outcome == 'success'");
  assert.ok(preflightGuard >= 0 && paymentExecution > preflightGuard, 'service-only mode must continue past the target without invoking browser payment automation');
  assert.match(matrixRunnerSource, /--service-preflight-only/);
  assert.match(matrixRunnerSource, /runId: process\.env\.GITHUB_RUN_ID \?\? matrixRunId/);
});

test('Azure Functions keep-alive is required in IaC, deployment verification, and transport preflight', () => {
  const missingIaC = auditAzureDeployContract({
    ...valid,
    functionsBicep: valid.functionsBicep.replace('alwaysOn: true', 'alwaysOn: false'),
  });
  assert.match(missingIaC.failures.join('\n'), /siteConfig\.alwaysOn=true/);

  const missingDeploymentCheck = auditAzureDeployContract({
    ...valid,
    infraDeployWorkflow: valid.infraDeployWorkflow.replace('az functionapp config show --query alwaysOn alwaysOn must be true', ''),
  });
  assert.match(missingDeploymentCheck.failures.join('\n'), /verify the Function App always-on setting/);

  const missingTransportCheck = auditAzureDeployContract({
    ...valid,
    deploymentWorkflows: [{
      path: '.github/workflows/phase10-azure-transport-smoke.yml',
      content: 'publishes test messages without checking the Functions host',
    }],
  });
  assert.match(missingTransportCheck.failures.join('\n'), /fail before publishing messages when the Functions host is not always-on/);

  const originalTransportWorkflow = valid.deploymentWorkflows[0];
  valid.deploymentWorkflows[0] = {
    ...originalTransportWorkflow,
    content: originalTransportWorkflow.content.split('refusing to publish transport/DLQ smoke messages').join('refusing to publish messages'),
  };
  const missingIntakePreflight = auditAzureDeployContract({
    ...valid,
    deploymentWorkflows: [{
      path: '.github/workflows/phase10-azure-transport-smoke.yml',
      content: valid.deploymentWorkflows.find((workflow) => /phase10-azure-transport-smoke\.yml$/i.test(workflow.path)).content
        .replace(/intake_disabled=.*\n\s*\[\[ \"\$intake_disabled\" == \"false\" \]\].*\n/, ''),
    }],
  });
  assert.match(missingIntakePreflight.failures.join('\n'), /fail before publishing messages when Functions quarantine intake is disabled or unknown/);
  valid.deploymentWorkflows[0] = originalTransportWorkflow;
});

test('routine Azure redeploys preserve Functions trigger state and explicit activation is dev-only', () => {
  const missingRestore = auditAzureDeployContract({
    ...valid,
    infraDeployWorkflow: valid.infraDeployWorkflow.replace('name: Restore existing Functions trigger state after routine redeploy', ''),
  });
  assert.match(missingRestore.failures.join('\n'), /routine redeploys must restore captured Functions trigger state/);

  const missingOrchestratorForward = auditAzureDeployContract({
    ...valid,
    orchestratorWorkflow: valid.orchestratorWorkflow.replace('activateExistingFunctionsTriggers: ${{ inputs.activateExistingFunctionsTriggers }}', ''),
  });
  assert.match(missingOrchestratorForward.failures.join('\n'), /must forward the explicit existing-Functions-trigger activation selection/);

  const missingIdentityBinding = auditAzureDeployContract({
    ...valid,
    orchestratorWorkflow: valid.orchestratorWorkflow.replace('--activateExistingFunctionsTriggers "$ACTIVATE_EXISTING_FUNCTIONS_TRIGGERS"', ''),
  });
  assert.match(missingIdentityBinding.failures.join('\n'), /must bind the explicit existing-Functions-trigger activation selection/);
});

test('Azure deploy contract rejects missing SQL fallback workflow wiring and SQL-admin runtime credentials', () => {
  const missingFallback = auditAzureDeployContract({
    ...valid,
    infraDeployWorkflow: valid.infraDeployWorkflow.replace('--parameters existingFunctionsSqlServerName=', ''),
  });
  assert.match(missingFallback.failures.join('\n'), /must pass existing Functions SQL targets/);

  const sqlAdminRuntime = auditAzureDeployContract({
    ...valid,
    mainBicep: valid.mainBicep.replace('Authentication=Active Directory Managed Identity;', 'User ID=sqladmin;Password=admin-secret;'),
  });
  assert.match(sqlAdminRuntime.failures.join('\n'), /Container Apps SQL access must use managed identity/);
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

test('Azure runtime targets require an explicit Functions replay queue name', () => {
  const broken = structuredClone(valid.runtimeTargets);
  delete broken.targets[1].azureReplayRequestQueueName;
  assert.match(validateAzureRuntimeTargets(broken).join(' '), /azure-stg: azureReplayRequestQueueName is required/);
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

test('all Phase 10 Container Apps keep traffic on the latest revision during redeploys', async () => {
  const containerApps = await readFile('infra/modules/containerapps.bicep', 'utf8');
  const ingressBlocks = [...containerApps.matchAll(/ingress:\s*\{([\s\S]*?)\n\s{6}\}/g)];
  assert.equal(ingressBlocks.length, 6, 'expected the six public/internal Phase 10 Container Apps');
  for (const [, ingress] of ingressBlocks) {
    assert.match(ingress, /traffic:\s*\[[\s\S]*?latestRevision:\s*true[\s\S]*?weight:\s*100[\s\S]*?\]/,
      'each ingress must explicitly route 100% to the latest revision');
  }
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

test('current repository preflight verifies Functions storage, SQL identity, and replay topology wiring structurally', async () => {
  const [functionsProject, functionsBicep, serviceBusBicep, hostingBicep, functionsPackageVerifier, mainBicep, infraDeployWorkflow, transportSmokeWorkflow, orchestratorWorkflow, azurePreflightScript, devParameters, stagingParameters, prodParameters, runtimeTargets] = await Promise.all([
    readFile('XYDataLabs.OrderProcessingSystem.Functions/XYDataLabs.OrderProcessingSystem.Functions.csproj', 'utf8'),
    readFile('infra/modules/functions.bicep', 'utf8'),
    readFile('infra/modules/servicebus.bicep', 'utf8'),
    readFile('infra/modules/hosting.bicep', 'utf8'),
    readFile('scripts/verify-phase10-function-package-runtime.mjs', 'utf8'),
    readFile('infra/main.phase10.bicep', 'utf8'),
    readFile('.github/workflows/infra-deploy.yml', 'utf8'),
    readFile('.github/workflows/phase10-azure-transport-smoke.yml', 'utf8'),
    readFile('.github/workflows/phase10-deploy-orchestrator.yml', 'utf8'),
    readFile('scripts/phase10-azure-preflight.mjs', 'utf8'),
    readFile('infra/parameters/phase10-dev.json', 'utf8').then(JSON.parse),
    readFile('infra/parameters/phase10-staging.json', 'utf8').then(JSON.parse),
    readFile('infra/parameters/phase10-prod.json', 'utf8').then(JSON.parse),
    readFile('automation/config/runtime-targets.json', 'utf8').then(JSON.parse),
  ]);
  const result = auditAzureDeployContract({ functionsProject, functionsBicep, serviceBusBicep, hostingBicep, infraBicepFiles: [
    { path: 'infra/modules/functions.bicep', content: functionsBicep },
    { path: 'infra/modules/hosting.bicep', content: hostingBicep },
  ], deploymentWorkflows: [
    { path: '.github/workflows/infra-deploy.yml', content: infraDeployWorkflow },
    { path: '.github/workflows/phase10-azure-transport-smoke.yml', content: transportSmokeWorkflow },
  ], functionsPackageVerifier, mainBicep, infraDeployWorkflow, orchestratorWorkflow, azurePreflightScript, parameterFiles: { dev: devParameters, staging: stagingParameters, prod: prodParameters }, runtimeTargets });
  assert.equal(result.status, 'PASS');
  assert.deepEqual(result.blocked, []);
});

test('Azure transport smoke never competes with the deployed Functions intake subscription', async () => {
  const source = await readFile('tools/Phase10.TransportSmoke/Program.cs', 'utf8');
  const transportScript = await readFile('scripts/run-phase10-azure-transport-smoke.ps1', 'utf8');
  const workflow = await readFile('.github/workflows/phase10-azure-transport-smoke.yml', 'utf8');
  const runtimeScript = await readFile('scripts/run-phase10-azure-runtime-smoke.ps1', 'utf8');
  const runtimeWorkflow = await readFile('.github/workflows/phase10-azure-runtime-smoke.yml', 'utf8');
  const approvalController = await readFile('XYDataLabs.OrderProcessingSystem.Orders.API/Controllers/DlqAdminController.cs', 'utf8');
  const localNfrProbe = await readFile('tools/Phase10.NfrProbe/FunctionsAcceptance.cs', 'utf8');
  const replayFunctionTests = await readFile('tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/Scenarios/DlqReplayFunctionOwnershipTests.cs', 'utf8');
  assert.match(source, /WaitForQuarantineRecordAsync\(options, dlqMessageId\)/);
  assert.match(source, /\[operations\]\.\[DlqQuarantineRecords\]/);
  assert.doesNotMatch(source, /CreateReceiver\(|ReceiveMessagesAsync\(|CompleteMessageAsync\(/);
  assert.match(source, /does not prove approved Functions replay/);
  assert.match(workflow, /Run transport publish consume and Functions quarantine smoke/);
  assert.match(source, /phase10-azure-transport-smoke-v1/);
  assert.match(source, /SummaryJsonPath/);
  assert.match(source, /name = check\.Name, status = check\.Passed \? "passed" : "failed"/);
  assert.doesNotMatch(source, /connectionString\s*=|sqlConnectionString\s*=|detail\s*=\s*check\.Detail/);
  assert.match(workflow, /prepareReplayCandidate:[\s\S]*?default: false[\s\S]*?type: boolean/);
  assert.match(workflow, /replayTenantCode:[\s\S]*?type: string/);
  assert.match(transportScript, /\[switch\]\$PrepareReplayCandidate/);
  assert.match(transportScript, /Replay-candidate preparation is restricted to Azure dev/);
  assert.match(transportScript, /Transport smoke output paths must be unique/);
  assert.match(transportScript, /Transport smoke output artifact already exists; choose new run-specific paths before any Azure access/);
  assert.match(transportScript, /OrdinalIgnoreCase/);
  assert.ok(transportScript.indexOf('if ($PrepareReplayCandidate)') < transportScript.indexOf('$subscriptionId = Invoke-AzureCliText'), 'replay-candidate argument validation must precede Azure CLI access');
  assert.ok(transportScript.indexOf('Transport smoke output artifact already exists') < transportScript.indexOf('New-Phase10FirewallLease'), 'existing output paths must be rejected before firewall mutation');
  assert.ok(transportScript.indexOf('Transport smoke output paths must be unique') < transportScript.indexOf('New-Phase10FirewallLease'), 'colliding output paths must be rejected before firewall mutation');
  assert.match(transportScript, /PHASE10_TRANSPORT_OPERATIONS_SQL_CONNECTION_STRING/);
  assert.match(source, /FailureCategory"\] = "transient-dependency"/);
  assert.match(source, /phase10-azure-dlq-replay-candidate-v1/);
  assert.match(source, /OperationsSqlConnectionString/);
  assert.doesNotMatch(source, /CreateReceiver\(|ReceiveMessagesAsync\(|CompleteMessageAsync\(/);
  assert.match(transportScript, /ReplayTenantCode and ReplayCandidateJsonPath are valid only with -PrepareReplayCandidate/);
  assert.match(workflow, /phase10-azure-dlq-replay-candidate\.json/);
  assert.match(transportScript, /--summary-json/);
  assert.match(workflow, /phase10-azure-transport-smoke\.json/);
  assert.match(runtimeScript, /phase10-azure-runtime-smoke-v1/);
  assert.match(runtimeScript, /SummaryJsonPath/);
  assert.match(runtimeScript, /httpStatus = \[string\]\$_\.Status/);
  assert.match(runtimeWorkflow, /phase10-azure-runtime-smoke\.json/);
  assert.doesNotMatch(workflow, /Run transport publish consume replay smoke/);
  assert.match(approvalController, /\[Authorize\(Roles = "phase10-operator"\)\]/);
  assert.match(approvalController, /HttpPost\("\{quarantineId:guid\}\/approve"\)/);
  assert.match(localNfrProbe, /RequestLocalReplayApprovalAsync/);
  assert.match(localNfrProbe, /authenticated-local-keycloak-pkce-api/);
  assert.doesNotMatch(localNfrProbe, /UPDATE\s+operations\.DlqQuarantineRecords|INSERT\s+INTO\s+operations\.DlqReplayRequests/i);
  assert.match(localNfrProbe, /ProcessedUtc IS NOT NULL AND q\.State='Replayed'/);
  assert.match(localNfrProbe, /frontend.*phase10-identity-proof\.mjs/);
  const localIdentityProof = await readFile('frontend/apps/web/scripts/phase10-identity-proof.mjs', 'utf8');
  assert.match(localIdentityProof, /--approve-quarantine-id/);
  assert.match(localIdentityProof, /authorized-local-replay-approval/);
  assert.match(localIdentityProof, /no retry was attempted/);
  assert.match(localIdentityProof, /hasOperatorRole/);
  assert.match(localIdentityProof, /cannot traverse a symlink outside TestResults/);
  assert.match(localIdentityProof, /replaceAll\(password, "\[REDACTED\]"\)/);
  const localApprovalContract = await readFile('frontend/apps/web/scripts/phase10-local-dlq-approval-contract.mjs', 'utf8');
  assert.match(localApprovalContract, /alreadyApproved !== false/);
  assert.match(localIdentityProof, /validateLocalDlqApprovalResponse/);
  assert.throws(() => validateLocalOperatorClaims({ realm_access: { roles: ["platform-admin"] } }, "TenantA"), /phase10-operator/);
  assert.throws(() => validateLocalOperatorClaims({ realm_access: { roles: ["phase10-operator"] }, tenant_code: "TenantA" }, "TenantB"), /not assigned/);
  assert.throws(() => validateLocalDlqApprovalResponse("11111111-1111-4111-8111-111111111111", {
    quarantineId: "11111111-1111-4111-8111-111111111111", replayRequestId: "22222222-2222-4222-8222-222222222222",
    state: "approved", approvedUtc: "2026-11-16T10:00:00.000Z", alreadyApproved: true
  }), /incomplete metadata/);
  assert.match(replayFunctionTests, /RunCoreAsync_WhenReplayRequestAlreadyProcessed_Completes_Without_Republishing/);
  assert.match(replayFunctionTests, /persistedQuarantine\.ReplayAttemptCount\.Should\(\)\.Be\(2\)/);
  assert.doesNotMatch(localIdentityProof, /console\.(?:log|error).*token|writeFile.*token/i);
});

test('Azure DLQ replay approval is explicit, Azure-dev-only, role-gated, single-attempt, and not misreported as completion', async () => {
  const [runner, approval, cli, helper, packageJson] = await Promise.all([
    readFile('automation/src/browser/payment-journey-runner.ts', 'utf8'),
    readFile('automation/src/verification/dlq-replay-approval.ts', 'utf8'),
    readFile('automation/src/cli/run-azure-dlq-replay-approval.ts', 'utf8'),
    readFile('automation/src/verification/dlq-replay-approval.test.ts', 'utf8'),
    readFile('automation/package.json', 'utf8')
  ]);
  assert.match(packageJson, /run:azure:dlq-replay-approval/);
  assert.match(cli, /--confirm-approval/);
  assert.match(cli, /resolve\("azure-dev"\)/);
  assert.match(cli, /REPLAY_EFFECTS_VERIFIED_DUPLICATE_DELIVERY_PENDING/);
  assert.match(cli, /--confirm-firewall-lease/);
  assert.match(cli, /closeOperatorAssistedSession/);
  assert.match(runner, /request\.target\.key !== "azure-dev"/);
  assert.match(runner, /request\.operatorAssistedEntra !== true \|\| request\.headless/);
  assert.match(runner, /dlqReplayApprovalQuarantineId/);
  assert.match(runner, /This is not proof of Functions processing or downstream effects/);
  assert.match(approval, /tokenHasRoleClaim\(request\.accessToken, "phase10-operator"\)/);
  assert.match(approval, /new URL\(`\/api\/v1\/admin\/dlq/);
  assert.match(approval, /method: "POST"/);
  assert.match(approval, /was not retried/);
  assert.match(approval, /authorization: `Bearer \$\{request\.accessToken\}`/);
  assert.doesNotMatch(approval, /console\.(log|error).*accessToken|writeFile.*accessToken/s);
  assert.match(helper, /does not retry ambiguous approval failures/);
});

test('Azure replay SQL evidence is read-only, tenant/database-routed, bounded, and firewall-lease guarded', () => {
  assert.match(replaySqlVerifierSource, /ValidateSet\('dev'\)/);
  assert.match(replaySqlVerifierSource, /ExpectedSubscriptionId/);
  assert.match(replaySqlVerifierSource, /ConfirmFirewallLease/);
  assert.ok(replaySqlVerifierSource.indexOf('$requestedTenantCode = $TenantCode') < replaySqlVerifierSource.indexOf('. $fixtureLibrary'), 'capture the requested tenant before dot-sourcing the shared fixture, which has a same-named parameter');
  assert.match(replaySqlVerifierSource, /Resolve-ReplayTenantDatabase -Code \$requestedTenantCode/);
  assert.match(replaySqlVerifierSource, /tenantCode = \$requestedTenantCode/);
  assert.match(replaySqlVerifierSource, /TimeoutSeconds = 120/);
  assert.match(replaySqlVerifierSource, /Initialize-AzureFixtureTopology/);
  assert.match(replaySqlVerifierSource, /Resolve-ReplayTenantDatabase/);
  assert.match(replaySqlVerifierSource, /SpecifyKind\(\$timestamp, \[DateTimeKind\]::Utc\)/, 'SQL datetime2 values written as UTC must not be reinterpreted in the local timezone');
  assert.match(replaySqlVerifierSource, /Convert-SqlUtcDateTime -Value \$row\.ApprovedUtc/);
  assert.match(replaySqlVerifierSource, /PublishedUtc/);
  assert.match(replaySqlVerifierSource, /ProcessedUtc/);
  assert.match(replaySqlVerifierSource, /InventoryReservations/);
  assert.match(replaySqlVerifierSource, /NotificationDeliveries/);
  assert.match(replaySqlVerifierSource, /FirewallLeaseRestored/);
  assert.doesNotMatch(replaySqlVerifierSource, /\b(?:INSERT|UPDATE|DELETE|MERGE)\s+(?:INTO\s+)?(?:operations\.|inventory\.|notifications\.|dbo\.)/i);
  assert.doesNotMatch(replaySqlVerifierSource, /-NonQuery/);
});

test('workflow 04 sends supervised modes only to an unprivileged desktop handoff', async () => {
  const workflow = yaml.load(paymentWorkflowSource);
  assert.deepEqual(workflow.on.workflow_dispatch.inputs.runMode.options,
    ['service-preflight', 'supervised-browser-auth', 'supervised-sandbox-payments', 'razorpay-order-lookup']);
  const hosted = workflow.jobs.azure_payment_matrix;
  const handoff = workflow.jobs.supervised_browser_handoff;
  assert.equal(hosted.if, "inputs.runMode != 'supervised-browser-auth' && inputs.runMode != 'supervised-sandbox-payments'");
  assert.equal(handoff.if, "inputs.runMode == 'supervised-browser-auth' || inputs.runMode == 'supervised-sandbox-payments'");
  assert.deepEqual(handoff.permissions, {});
  assert.equal(handoff.environment, undefined);
  assert.equal(handoff.steps.length, 1);
  assert.equal(handoff.steps[0].uses, undefined);
  assert.match(handoff.steps[0].run, /Awaiting supervised evidence — browser and payments NOT RUN/);
  assert.match(handoff.steps[0].run, /'AuthPreflight' \} else \{ 'ProviderMatrix'/);
  assert.match(handoff.steps[0].run, /Selecting this mode is not that approval/);
  const fixture = await mkdtemp(path.join(os.tmpdir(), 'phase10-browser-handoff-'));
  try {
    const script = path.join(fixture, 'handoff.ps1');
    const summary = path.join(fixture, 'summary.md');
    await writeFile(script, handoff.steps[0].run, 'utf8');
    const invoke = (overrides) => execFileSync('pwsh', ['-NoProfile', '-File', script], {
      stdio: 'pipe', env: { ...process.env, GITHUB_REF: 'refs/heads/dev', GITHUB_SHA: 'candidate-sha',
        GITHUB_STEP_SUMMARY: summary, TARGET_ENVIRONMENT: 'dev', RUN_MODE: 'supervised-browser-auth',
        LOOKUP_TENANT: '', LOOKUP_ORDER: '', LOOKUP_AMOUNT: '0', ...overrides },
    });
    assert.throws(() => invoke({ GITHUB_REF: 'refs/heads/staging' }), /requires branch dev/);
    assert.throws(() => invoke({ LOOKUP_AMOUNT: '1' }), /Lookup parameters are not allowed/);
    assert.equal(existsSync(summary), false);
    invoke({});
    assert.match(await readFile(summary, 'utf8'), /-Mode AuthPreflight/);
    invoke({ RUN_MODE: 'supervised-sandbox-payments' });
    const evidence = await readFile(summary, 'utf8');
    assert.match(evidence, /-Mode ProviderMatrix/);
    assert.match(evidence, /workflow SHA candidate-sha/);
  } finally {
    await rm(fixture, { recursive: true, force: true });
  }
});

test('operator-assisted Azure Entra mode fails closed before mutations and is dev-only', async () => {
  const [cli, runner] = await Promise.all([
    readFile('automation/src/cli/run-azure-matrix.ts', 'utf8'),
    readFile('automation/src/browser/payment-journey-runner.ts', 'utf8'),
  ]);
  assert.match(cli, /--operator-assisted-entra/);
  assert.match(cli, /payment mode requires an explicit tenant or the complete --all-active-tenants two-provider fixture matrix/);
  assert.match(cli, /providerFixtureMatrixRequested && \(!operatorAssistedEntra \|\| authPreflightOnly \|\| normalizedTargets\.length !== 1 \|\| normalizedTargets\[0\] !== "azure-dev"\)/);
  assert.match(cli, /new Set\(tenantCodes\.map\(\(code\) => code\.toLowerCase\(\)\)\)\.size !== tenantCodes\.length/);
  assert.match(cli, /if \(operatorAssistedEntra\) tenantTimeoutMs = Math\.max\(tenantTimeoutMs, 420000\)/);
  assert.match(cli, /if \(authPreflightOnly && !operatorAssistedEntra\)/);
  assert.match(cli, /\(options\.authPreflightOnly \|\| options\.servicePreflightOnly\) \? "preflight-passed"/);
  assert.match(cli, /executionMode: options\.dryRun \? "dry-run" : options\.servicePreflightOnly \? "service-preflight-only" : options\.authPreflightOnly \? "auth-preflight-only"/);
  const authPreflight = runner.indexOf('const accessProbe = await apiContext.get("/api/v1/Customer/GetAllCustomers"');
  const configurationPreflight = runner.indexOf('const paymentConfiguration = await this.resolvePaymentConfiguration');
  const mutation = runner.indexOf('const authoritativeOrder = request.manualEntry ? await this.createOrderThroughUi');
  assert.ok(authPreflight >= 0 && configurationPreflight >= 0 && mutation > configurationPreflight,
    'Entra scope/tenant authorization and sandbox configuration must be verified before order creation');
  const authOnly = runner.indexOf('if (request.authPreflightOnly)');
  const orderCreation = runner.indexOf('const authoritativeOrder = request.manualEntry ? await this.createOrderThroughUi');
  assert.ok(authOnly > configurationPreflight && authOnly < orderCreation,
    'auth-only mode must stop after authenticated configuration checks and before any order creation');
  assert.match(runner, /journeyOutcome: "auth-preflight-passed"/);
  assert.match(runner, /customerOrderId: "not-created"/);
  assert.match(runner, /Admin UI tenant-switch cycle passed/);
  assert.match(runner, /tenantPicker\.selectOption\(tenantCode\)/);
  assert.match(runner, /tenantPreflightResults\.push/);
  assert.match(runner, /paymentConfiguration:|paymentProvider: tenantConfiguration\.activeProviderType/);
  assert.match(runner, /localStorage\.getItem\("orderprocessing\.accessToken"\)/);
  assert.match(runner, /launchLocalBrowser\(\(options\) => chromium\.launch\(options\), request\.headless, headedOperatorEntra\)/);
  assert.match(runner, /viewport: headedOperatorEntra \? null : undefined/);
  assert.match(runner, /if \(headedOperatorEntra\) await page\.bringToFront\(\)/);
  assert.match(runner, /WAITING_FOR_SIGN_IN/);
  assert.match(runner, /SESSION_EXPIRED/);
  const originalTabPreflight = runner.indexOf('await this.verifyOriginalOperatorSignOut(page, request.target.baseUrl, 60000)');
  assert.ok(originalTabPreflight >= 0 && originalTabPreflight < orderCreation);
  assert.match(runner, /await context\.newPage\(\);\s+await this\.verifyOriginalOperatorSignOut\(page, request\.target\.baseUrl, 60000\)/);
  assert.match(runner, /const signInPage = previousSession\?\.signInPage \?\? journeyPage/);
  assert.match(runner, /await this\.verifyOriginalOperatorSignOut\(session\.signInPage, session\.baseUrl, timeoutMs\)/);
  assert.match(runner, /identity-provider logout could not be confirmed/);
  assert.match(runner, /heading && localStorage\.getItem\("orderprocessing\.accessToken"\) === null/);
  assert.doesNotMatch(runner, /observedHeading|allTextContents\(\)/);
  assert.match(runner, /return `\$\{url\.origin\}\$\{url\.pathname\}`/);
  assert.match(runner, /No credentials or browser state will be saved/);
  assert.match(runner, /request\.diagnosticsDirectory && !request\.operatorAssistedEntra/);
  assert.match(runner, /No Entra application access token became available within the sign-in window/);
  assert.match(runner, /configuredApiOrigin !== null && configuredApiOrigin !== expectedUiOrigin && configuredApiOrigin !== expectedApiOrigin/);
  assert.match(runner, /Entra sign-in returned OAuth error code/);
  assert.doesNotMatch(runner, /authResult\.error.*error_description/s);
  assert.match(runner, /MFA is completed by the operator, never bypassed by automation/);
  assert.match(runner, /reuseEntraSession === true/);
  assert.match(runner, /Reusing the in-memory Entra browser session/);
  assert.match(runner, /closeOperatorAssistedSession/);
  const executor = await readFile('automation/src/orchestrator/payment-automation-executor.ts', 'utf8');
  assert.match(executor, /reuseEntraSession: options\.operatorAssistedEntra/);
  assert.match(executor, /await paymentJourneyRunner\.closeOperatorAssistedSession\(log\)/);
  assert.match(executor, /required provider\/SQL verification failed, so no further tenant payment will be submitted/);
});

test('Azure all-active-tenant provider fixtures use Entra SQL, exact recovery, and remain dev-only', async () => {
  const [cli, provisioner, fixture, localRunner, workflow, journey, executor] = await Promise.all([
    readFile('automation/src/cli/run-azure-matrix.ts', 'utf8'),
    readFile('automation/src/adapters/fixtures/powershell-payment-provider-provisioner.ts', 'utf8'),
    readFile('scripts/phase10-azure-payment-test-state.ps1', 'utf8'),
    readFile('scripts/run-phase10-azure-dev-operator-matrix.ps1', 'utf8'),
    readFile('.github/workflows/phase10-azure-payment-matrix.yml', 'utf8'),
    readFile('automation/src/browser/payment-journey-runner.ts', 'utf8'),
    readFile('automation/src/orchestrator/payment-automation-executor.ts', 'utf8'),
  ]);
  assert.match(cli, /--all-active-tenants requires a complete headed Azure-dev Entra matrix with both Razorpay and OpenPay/);
  assert.match(cli, /providerFixtureCoverage = \{/);
  assert.match(cli, /restorationFailed = options\.requestedProviders\.length > 0/);
  assert.match(provisioner, /phase10-azure-payment-test-state\.ps1/);
  assert.match(provisioner, /exact-azure-dev-entra-snapshot/);
  assert.match(provisioner, /stop the matrix before any charge/);
  assert.match(fixture, /'account','get-access-token','--resource','https:\/\/database\.windows\.net\//);
  assert.match(fixture, /HAS_PERMS_BY_NAME\(N'dbo\.Tenants', N'OBJECT', N'UPDATE', N'PaymentProviderCode', N'COLUMN'\)/);
  assert.match(fixture, /HAS_PERMS_BY_NAME\(N'payments\.PaymentProviders', N'OBJECT', N'UPDATE', N'Use3DSecure', N'COLUMN'\)/);
  assert.match(fixture, /UPDATE dbo\.Tenants SET PaymentProviderCode/);
  assert.match(fixture, /UPDATE payments\.PaymentProviders SET Use3DSecure/);
  assert.match(fixture, /\$rows = Invoke-RestMethod -Uri \$endpoint -Method Get -TimeoutSec 10/);
  assert.doesNotMatch(fixture, /\$rows = @\(Invoke-RestMethod -Uri \$endpoint/);
  assert.match(fixture, /New-Phase10FirewallLease/);
  assert.match(fixture, /Remove-Phase10FirewallLease/);
  assert.doesNotMatch(fixture, /sql-admin-password|SQL admin password|PaymentProviders--.*PrivateKey/);
  assert.match(localRunner, /Could not resolve the live Azure Container Apps environment domain/);
  assert.match(localRunner, /AuthPreflight/);
  assert.match(localRunner, /--provider','Razorpay','--provider','OpenPay/);
  assert.doesNotMatch(workflow, /--provider Razorpay|--provider OpenPay/);
  assert.match(journey, /retainOperatorSessionAfterAuthPreflight/);
  assert.match(journey, /No-charge Entra access and tenant-switch preflight passed; preserving this in-memory session/);
  assert.match(executor, /requiresSingleSessionPreflight/);
  assert.match(executor, /retainOperatorSessionAfterAuthPreflight: true/);
  assert.ok(executor.indexOf('if (requiresSingleSessionPreflight)') < executor.indexOf('for (const executionItem of runnableExecutionItems)'), 'Entra no-charge preflight must precede every provider fixture and payment case');
});

test('deployment parameter identity is recorded before the approval comparison for diagnosable failures', async () => {
  const workflow = await readFile('.github/workflows/phase10-deploy-orchestrator.yml', 'utf8');
  const identityOutput = workflow.indexOf('Calculated deployment parameter identity:');
  const identityComparison = workflow.indexOf('[[ "$calculated" == "$APPROVED_PARAMETER_IDENTITY" ]]');
  assert.notEqual(identityOutput, -1, 'the non-secret calculated identity must appear in the failed job summary');
  assert.ok(identityComparison > identityOutput, 'the calculated identity must be recorded before mismatch can fail the job');
  assert.match(workflow, /echo "Calculated deployment parameter identity: \$calculated"/);
  assert.match(workflow, /Calculated deployment parameter identity:.*\$calculated.*GITHUB_STEP_SUMMARY/);
});

test('reusable release verification carries explicit Functions activation into the approved identity', () => {
  assert.match(releaseInputVerifierSource, /activateExistingFunctionsTriggers:\s*process\.env\.ACTIVATE_EXISTING_FUNCTIONS_TRIGGERS === 'true'/);
  const missingActivationForwarding = auditAzureDeployContract({
    ...valid,
    infraDeployWorkflow: valid.infraDeployWorkflow.replaceAll('ACTIVATE_EXISTING_FUNCTIONS_TRIGGERS: ${{ inputs.activateExistingFunctionsTriggers }}', ''),
  });
  assert.match(missingActivationForwarding.failures.join('\n'), /release verification must bind the explicit Functions-trigger activation selection/);
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
  const whatIfStep = workflow.jobs.validate.steps.find((step) => step.name === 'What-If (subscription scope)');
  assert.ok(whatIfStep, 'dry-run must have a dedicated what-if step');
  assert.match(whatIfStep.run, /WHAT_IF_ACR_USERNAME='phase10-what-if-only'/);
  assert.match(whatIfStep.run, /WHAT_IF_ACR_PASSWORD='not-a-real-acr-credential-phase10-what-if'/);
  assert.match(whatIfStep.run, /--parameters acrRegistryUsername="\$WHAT_IF_ACR_USERNAME"/);
  assert.match(whatIfStep.run, /--parameters acrRegistryPassword="\$WHAT_IF_ACR_PASSWORD"/);
  assert.doesNotMatch(whatIfStep.run, /az acr token credential generate|acr_pull_token/,
    'dry-run must model registry-auth shape without creating or retrieving a real ACR token');
  const deploySteps = workflow.jobs.deploy.steps;
  assert.ok(deploySteps.some((step) => step.id === 'acr_pull_token'), 'ACR scoped-token mutation must be isolated to the deploy job');
  assert.match(orchestrator, /dry-run what-if path using prebuilt immutable release/);
  assert.doesNotMatch(orchestrator, /build-phase10-images\.yml/, 'orchestration must not build or publish images during validation');
});

test('Phase 10 what-if can expand dedicated Key Vault secrets and preserves ACA environment settings', async () => {
  const [mainTemplate, keyVaultTemplate, acaTemplate] = await Promise.all([
    readFile('infra/main.phase10.bicep', 'utf8'),
    readFile('infra/modules/keyvault.phase10.bicep', 'utf8'),
    readFile('infra/modules/aca-environment.phase10.bicep', 'utf8'),
  ]);
  assert.match(mainTemplate, /dedicatedTenantCodes:\s*baselineDedicatedTenantCodes/);
  assert.match(keyVaultTemplate, /param\s+dedicatedTenantCodes\s+array/);
  assert.match(keyVaultTemplate, /for\s+tenantCode\s+in\s+dedicatedTenantCodes/);
  assert.match(keyVaultTemplate, /dedicatedTenantConnectionStrings\[tenantCode\]/);
  assert.match(acaTemplate, /peerAuthentication:\s*\{\s*mtls:\s*\{\s*enabled:\s*false/s);
  assert.match(acaTemplate, /peerTrafficConfiguration:\s*\{\s*encryption:\s*\{\s*enabled:\s*false/s);
  assert.match(acaTemplate, /workloadProfiles:\s*\[\s*\{\s*name:\s*'Consumption'\s*workloadProfileType:\s*'Consumption'/s);
});

test('Key Vault updates preserve existing policies and add application policies explicitly', async () => {
  const [phase10Template, legacyTemplate, phase10Root, legacyRoot] = await Promise.all([
    readFile('infra/modules/keyvault.phase10.bicep', 'utf8'),
    readFile('infra/modules/keyvault.bicep', 'utf8'),
    readFile('infra/main.phase10.bicep', 'utf8'),
    readFile('infra/main.bicep', 'utf8'),
  ]);

  for (const [name, template] of [['Phase 10', phase10Template], ['legacy', legacyTemplate]]) {
    const vaultResource = template.match(/resource keyVault[\s\S]*?\r?\n}\r?\n/);
    assert.ok(vaultResource, `${name} Key Vault resource must be present`);
    assert.doesNotMatch(vaultResource[0], /accessPolicies:\s*\[\s*\]/,
      `${name} vault update must not clear existing access policies`);
    assert.match(template, /resource accessPolicies 'Microsoft\.KeyVault\/vaults\/accessPolicies@[^']+' = if[\s\S]*?name:\s*'add'/,
      `${name} app access policies must be managed through the additive child resource`);
    assert.match(template, /param\s+existingKeyVaultAccessPolicies\s+array/,
      `${name} must require a live access-policy snapshot`);
    assert.match(vaultResource[0], /accessPolicies:\s*existingKeyVaultAccessPolicies/,
      `${name} vault PUT must supply the preserved policy snapshot required by Azure`);
  }
  assert.match(phase10Root, /module keyVault[\s\S]*?existingKeyVaultAccessPolicies:\s*existingKeyVaultAccessPolicies/);
  assert.match(legacyRoot, /module keyVault[\s\S]*?existingKeyVaultAccessPolicies:\s*existingKeyVaultAccessPolicies/);
});

test('Phase 10 what-if and deployment pass a live Key Vault policy snapshot', async () => {
  const [mainTemplate, keyVaultTemplate, legacyMainTemplate, legacyKeyVaultTemplate, workflow] = await Promise.all([
    readFile('infra/main.phase10.bicep', 'utf8'),
    readFile('infra/modules/keyvault.phase10.bicep', 'utf8'),
    readFile('infra/main.bicep', 'utf8'),
    readFile('infra/modules/keyvault.bicep', 'utf8'),
    readFile('.github/workflows/infra-deploy.yml', 'utf8'),
  ]);
  assert.match(mainTemplate, /param\s+existingKeyVaultAccessPolicies\s+array\s*\n/);
  assert.match(mainTemplate, /module keyVault[\s\S]*?existingKeyVaultAccessPolicies:\s*existingKeyVaultAccessPolicies/);
  assert.match(keyVaultTemplate, /param\s+existingKeyVaultAccessPolicies\s+array\s*\n/);
  assert.match(keyVaultTemplate, /accessPolicies:\s*existingKeyVaultAccessPolicies/);
  assert.match(legacyMainTemplate, /param\s+existingKeyVaultAccessPolicies\s+array/);
  assert.match(legacyKeyVaultTemplate, /accessPolicies:\s*existingKeyVaultAccessPolicies/);
  assert.equal((workflow.match(/az keyvault show --name "\$KV_NAME" --query properties\.accessPolicies -o json/g) ?? []).length, 2,
    'both what-if and actual deployment must capture the live policy list');
  assert.equal((workflow.match(/grep -Eqi 'ResourceNotFound\|NotFound'/g) ?? []).length, 2,
    'only a confirmed missing vault may use an empty policy list');
  assert.equal((workflow.match(/Could not read Key Vault '\$KV_NAME' policy state; refusing/g) ?? []).length, 2,
    'permission or service errors must fail closed instead of treating an existing vault as empty');
  assert.equal((workflow.match(/existingKeyVaultAccessPolicies=@\$\{KEYVAULT_ACCESS_POLICIES_FILE\}/g) ?? []).length, 2,
    'both what-if and actual deployment must pass that policy snapshot');
  assert.equal((workflow.match(/normalize-phase10-keyvault-access-policies\.mjs/g) ?? []).length, 2,
    'both what-if and actual deployment must normalize nullable GET fields before ARM receives the snapshot');
});

test('Key Vault policy normalization removes only null optional fields and preserves all grants', () => {
  const snapshot = [{
    tenantId: 'tenant-id',
    objectId: 'principal-id',
    applicationId: null,
    permissions: { certificates: null, keys: null, secrets: ['get', 'list'], storage: null },
  }];
  const normalized = normalizeKeyVaultAccessPolicies(snapshot);
  assert.deepEqual(normalized, [{
    tenantId: 'tenant-id',
    objectId: 'principal-id',
    permissions: { secrets: ['get', 'list'] },
  }]);
  assert.equal(snapshot[0].applicationId, null, 'normalization must not mutate the caller snapshot');
  assert.equal(snapshot[0].permissions.secrets.length, 2, 'existing grants must be preserved');
});

test('Key Vault policy normalization rejects malformed snapshots instead of dropping grants', () => {
  assert.throws(() => normalizeKeyVaultAccessPolicies({}), /must be an array/);
  assert.throws(() => normalizeKeyVaultAccessPolicies([{ tenantId: 't', objectId: 'o', permissions: { secrets: 'get' } }]), /malformed permission list/);
  assert.throws(() => normalizeKeyVaultAccessPolicies([{ tenantId: 't', objectId: 'o', permissions: { unknown: [] } }]), /unknown permission category/);
});

test('Key Vault policy normalizer CLI writes a valid snapshot and rejects malformed input', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'phase10-kv-policy-'));
  const inputPath = path.join(directory, 'input.json');
  const outputPath = path.join(directory, 'output.json');
  const normalizerPath = fileURLToPath(new URL('../normalize-phase10-keyvault-access-policies.mjs', import.meta.url));
  try {
    await writeFile(inputPath, JSON.stringify([{
      tenantId: 'tenant-id', objectId: 'principal-id', applicationId: null,
      permissions: { certificates: null, keys: null, secrets: ['get'], storage: null },
    }]));
    execFileSync(process.execPath, [normalizerPath, inputPath, outputPath]);
    assert.deepEqual(JSON.parse(await readFile(outputPath, 'utf8')), [{
      tenantId: 'tenant-id', objectId: 'principal-id', permissions: { secrets: ['get'] },
    }]);

    await writeFile(inputPath, JSON.stringify([{ tenantId: 't', objectId: 'o', permissions: { secrets: 'get' } }]));
    assert.throws(
      () => execFileSync(process.execPath, [normalizerPath, inputPath, outputPath]),
      (error) => error.status === 1 && /malformed permission list/.test(error.stderr.toString()),
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('SQL admin Key Vault secret is controlled by the explicit SQL deployment switch', async () => {
  const [mainTemplate, keyVaultTemplate] = await Promise.all([
    readFile('infra/main.phase10.bicep', 'utf8'),
    readFile('infra/modules/keyvault.phase10.bicep', 'utf8'),
  ]);
  assert.match(mainTemplate, /module keyVault[\s\S]*?deploySql:\s*deploySql/,
    'top-level deploySql selection must reach the Key Vault module');
  assert.match(keyVaultTemplate, /param\s+deploySql\s+bool\s*=\s*false/);
  assert.match(keyVaultTemplate, /resource sqlAdminPasswordSecret[\s\S]*?= if \(deploySql\)/,
    'routine deployments with deploySql=false must not include the SQL password secret resource');
});

test('Service Bus IaC explicitly preserves the deployed entity defaults', async () => {
  const template = await readFile('infra/modules/servicebus.bicep', 'utf8');
  const resourceBlock = (name) => {
    const block = template.match(new RegExp(`resource ${name} [\\s\\S]*?\\r?\\n}\\r?\\n`));
    assert.ok(block, `Service Bus resource ${name} must be present`);
    return block[0];
  };

  for (const name of [
    'orderTopic', 'inventorySubscription', 'ordersPaymentStateSubscription',
    'notificationsSubscription', 'dlqTopic', 'dlqReplaySubscription',
    'replayRequestQueue', 'replayDrillRequestQueue',
  ]) {
    assert.match(resourceBlock(name), /autoDeleteOnIdle:\s*entityAutoDeleteOnIdle/,
      `${name} must retain Azure's non-expiring entity default`);
  }
  for (const name of ['replayRequestQueue', 'replayDrillRequestQueue']) {
    const block = resourceBlock(name);
    for (const property of [
      /duplicateDetectionHistoryTimeWindow:\s*'PT10M'/,
      /enablePartitioning:\s*false/,
      /lockDuration:\s*'PT1M'/,
      /maxMessageSizeInKilobytes:\s*256/,
      /maxSizeInMegabytes:\s*1024/,
      /requiresDuplicateDetection:\s*false/,
    ]) assert.match(block, property, `${name} must explicitly preserve queue defaults`);
  }
});
