import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const readRepoFile = (path) => readFile(new URL(`../../${path}`, import.meta.url), 'utf8');

test('both positive verifiers require tenant-scoped callback evidence independently of 3DS', async () => {
  for(const file of ['scripts/verify-payment-run-physical.ps1','scripts/verify-payment-run-azure.ps1']) {
    const script=await readRepoFile(file);
    const assignments=[...script.matchAll(/UiCallbackExpected\s*=\s*([^\r\n]+)/g)];
    assert.ok(assignments.length>0);
    assert.ok(assignments.every(match=>match[1].trim()==='$true'));
    assert.match(script,/\$uiMatches = @\(\$callback(?:Ui)?Events \| Where-Object \{ \$_\.Tenant -eq \$chargeEvent\.Tenant -and/);
  }
});

test('Azure SQL verifier keeps Key Vault auth as default and supports Entra token auth without SQL password retrieval', async () => {
  const script = await readRepoFile('scripts/verify-payment-run-azure.ps1');

  assert.match(script, /ValidateSet\('KeyVault', 'Entra'\)[\s\S]*\$SqlAuthenticationMode = 'KeyVault'/);
  assert.match(script, /az account get-access-token --resource https:\/\/database\.windows\.net\/ --query accessToken -o tsv/);
  assert.match(script, /\$connection\.AccessToken = \$script:SqlAccessToken/);
  assert.match(script, /if \(\$SqlAuthenticationMode -eq 'Entra'\)[\s\S]*?Acquire Azure SQL access token[\s\S]*?Discover tagged Azure SQL databases/);
  assert.match(script, /else \{[\s\S]*?Resolve sql-admin-password from Key Vault/);
  assert.match(script, /if \(\$script:SqlAuthenticationMode -eq 'KeyVault'\)[\s\S]*?Resolve \$providerPrivateKeyAlias from Key Vault/);
  assert.match(script, /tenant='\$tenantCode'/);
});

test('operator-assisted Entra verification explicitly selects Entra while normal hosted verification retains Key Vault mode', async () => {
  const executor = await readRepoFile('automation/src/orchestrator/payment-automation-executor.ts');
  const adapter = await readRepoFile('automation/src/verification/powershell-verification-adapter.ts');
  const contract = await readRepoFile('automation/src/contracts/verification-adapter.ts');

  assert.match(contract, /sqlAuthenticationMode\?: "entra" \| "key-vault"/);
  assert.match(executor, /sqlAuthenticationMode: options\.operatorAssistedEntra \? "entra" : "key-vault"/);
  assert.match(adapter, /request\.sqlAuthenticationMode === "entra"[\s\S]*?"-SqlAuthenticationMode", "Entra"/);
  assert.doesNotMatch(adapter, /"-SqlAuthenticationMode", "KeyVault"/);
});

test('provider payment ID fallback can recover the persisted order from API custom events when operation correlation is sparse', async () => {
  const script = await readRepoFile('scripts/verify-payment-run-azure.ps1');

  assert.match(script, /\$requestedTenantCode = \$TenantCode/);
  assert.match(script, /provider-payment-id-api-event-fallback/);
  assert.match(script, /if \(\(Get-CollectionCount -Value \$operationApiEvents\) -eq 0\)[\s\S]*?where chargeId in \(\$providerIdList\)[\s\S]*?project timestamp, operation_Id, tenant, customerOrderId, chargeId/);
  assert.match(script, /Where-Object Tenant -eq \$requestedTenantCode\.Trim\(\)/);
  assert.match(script, /Follow the provider-correlated[\s\S]*?tenant\/order key to read the matching shared or dedicated SQL row/);
});

test('Azure verifier accepts paired explicit UTC run windows and applies one window to all telemetry queries', async () => {
  const script = await readRepoFile('scripts/verify-payment-run-azure.ps1');
  assert.match(script, /StartedUtc and FinishedUtc must be supplied together/);
  assert.match(script, /FinishedUtc must be later than StartedUtc/);
  assert.match(script, /TelemetryTimeFilter = "timestamp between \(datetime\(\$telemetryWindowStartUtc\) \.\. datetime\(\$telemetryWindowEndUtc\)\)"/);
  assert.doesNotMatch(script, /startofday\(now\(\) \+ 330m\)/);
  assert.equal((script.match(/where \$\(\$script:TelemetryTimeFilter\)/g) ?? []).length, 12);
});
