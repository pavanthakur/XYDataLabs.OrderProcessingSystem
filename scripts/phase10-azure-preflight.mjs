import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REQUIRED_ROLE_ASSIGNMENT_ACTION = 'Microsoft.Authorization/roleAssignments/write';
const REQUIRED_PROVIDERS = Object.freeze([
  'Microsoft.App',
  'Microsoft.Cache',
  'Microsoft.ContainerRegistry',
  'Microsoft.Insights',
  'Microsoft.KeyVault',
  'Microsoft.ManagedIdentity',
  'Microsoft.OperationalInsights',
  'Microsoft.ServiceBus',
  'Microsoft.Sql',
  'Microsoft.Storage',
  'Microsoft.Web',
]);

function actionMatches(pattern, action) {
  const escaped = String(pattern).replace(/[.+?^${}()|[\]\\]/g, '\\$&').replaceAll('*', '.*');
  return new RegExp(`^${escaped}$`, 'i').test(action);
}

export function hasEffectiveAction(permissionResponse, requiredAction = REQUIRED_ROLE_ASSIGNMENT_ACTION) {
  return (permissionResponse?.value ?? []).some((grant) => {
    const allowed = (grant.actions ?? []).some((pattern) => actionMatches(pattern, requiredAction));
    const excluded = (grant.notActions ?? []).some((pattern) => actionMatches(pattern, requiredAction));
    return allowed && !excluded;
  });
}

export function assessAzurePreflight({ expectedSubscriptionId, expectedTenantId, account, targetScope, permissionResponse, providerStates }) {
  const checks = [];
  const equalGuid = (left, right) => typeof left === 'string' && typeof right === 'string' && left.toLowerCase() === right.toLowerCase();
  checks.push({ id: 'subscription', status: equalGuid(account?.id, expectedSubscriptionId) ? 'PASS' : 'FAIL' });
  checks.push({ id: 'directory', status: equalGuid(account?.tenantId, expectedTenantId) ? 'PASS' : 'FAIL' });
  checks.push({ id: 'role-assignment-write', status: hasEffectiveAction(permissionResponse) ? 'PASS' : 'FAIL', scope: targetScope });
  for (const provider of REQUIRED_PROVIDERS) checks.push({ id: `provider:${provider}`, status: providerStates?.[provider] === 'Registered' ? 'PASS' : 'FAIL' });
  const failures = checks.filter((check) => check.status === 'FAIL');
  return { schemaVersion: 1, status: failures.length ? 'FAIL' : 'PASS', checks };
}

function runAz(args) {
  try {
    return execFileSync('az', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch {
    throw new Error(`Azure read-only preflight command failed: az ${args[0]} ${args[1] ?? ''}`.trim());
  }
}

async function main() {
  const expectedSubscriptionId = process.env.AZURE_EXPECTED_SUBSCRIPTION_ID;
  const expectedTenantId = process.env.AZURE_EXPECTED_TENANT_ID;
  const resourceGroup = process.env.AZURE_TARGET_RESOURCE_GROUP;
  if (!/^[0-9a-f-]{36}$/i.test(expectedSubscriptionId ?? '') || !/^[0-9a-f-]{36}$/i.test(expectedTenantId ?? '') || !/^rg-[a-z0-9-]+$/i.test(resourceGroup ?? '')) {
    throw new Error('Expected subscription, directory, or target resource-group input is missing or malformed.');
  }

  const account = JSON.parse(runAz(['account', 'show', '--output', 'json']));
  const groupExists = runAz(['group', 'exists', '--name', resourceGroup, '--subscription', expectedSubscriptionId]).trim() === 'true';
  const subscriptionScope = `/subscriptions/${expectedSubscriptionId}`;
  const targetScope = groupExists ? `${subscriptionScope}/resourceGroups/${resourceGroup}` : subscriptionScope;
  const permissionUrl = `https://management.azure.com${targetScope}/providers/Microsoft.Authorization/permissions?api-version=2015-07-01`;
  const permissionResponse = JSON.parse(runAz(['rest', '--method', 'get', '--url', permissionUrl, '--output', 'json']));
  const providerStates = {};
  for (const provider of REQUIRED_PROVIDERS) {
    try {
      providerStates[provider] = runAz(['provider', 'show', '--namespace', provider, '--subscription', expectedSubscriptionId, '--query', 'registrationState', '--output', 'tsv']).trim();
    } catch {
      providerStates[provider] = 'Unavailable';
    }
  }

  const result = assessAzurePreflight({ expectedSubscriptionId, expectedTenantId, account, targetScope, permissionResponse, providerStates });
  const lines = [
    '| Read-only prerequisite | Result |',
    '|---|---|',
    ...result.checks.map((check) => `| ${check.id} | ${check.status} |`),
  ];
  if (process.env.GITHUB_STEP_SUMMARY) {
    const fs = await import('node:fs/promises');
    await fs.appendFile(process.env.GITHUB_STEP_SUMMARY, `## Phase 10 Azure prerequisite preflight: ${result.status}\n\n${lines.join('\n')}\n\nRole-assignment permission is checked read-only at ${targetScope}; this workflow does not grant or elevate access.\n\n`);
  }
  console.log(`Azure prerequisite preflight: ${result.status} (${result.checks.filter((check) => check.status === 'PASS').length}/${result.checks.length} checks).`);
  if (result.status !== 'PASS') process.exitCode = 1;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => { console.error(`Azure prerequisite preflight failed: ${error.message}`); process.exitCode = 1; });
}
