import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROLE_ASSIGNMENT_WRITE = 'Microsoft.Authorization/roleAssignments/write';
const ROLE_ASSIGNMENT_ADMIN = 'Role Based Access Control Administrator';
const STORAGE_BLOB_DATA_OWNER_ID = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b';
const SERVICE_BUS_DATA_RECEIVER_ID = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0';
const SERVICE_BUS_DATA_SENDER_ID = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39';
const DEV_BOOTSTRAP_GUIDANCE = 'Run local 00b Dev Foundation Bootstrap (scripts/phase10-azure-dev-foundation-bootstrap.ps1) in Plan mode and review the result before retrying.';

export function buildBootstrapCondition(replayRunnerPrincipalId = '') {
  const storageRule = `(@ATTRIBUTE:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${STORAGE_BLOB_DATA_OWNER_ID}} AND @ATTRIBUTE:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'})`;
  const replayRule = replayRunnerPrincipalId
    ? `(@ATTRIBUTE:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${SERVICE_BUS_DATA_RECEIVER_ID}, ${SERVICE_BUS_DATA_SENDER_ID}} AND @ATTRIBUTE:PrincipalId] ForAnyOfAnyValues:GuidEquals {${replayRunnerPrincipalId}} AND @ATTRIBUTE:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'User'})`
    : '';
  const allowed = replayRule ? `(${storageRule} OR ${replayRule})` : storageRule;
  const writeRule = allowed.replaceAll('@ATTRIBUTE:', '@Request[Microsoft.Authorization/roleAssignments:');
  const deleteRule = allowed.replaceAll('@ATTRIBUTE:', '@Resource[Microsoft.Authorization/roleAssignments:');
  return `((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR ${writeRule}) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR ${deleteRule})`;
}

function actionMatches(pattern, action) {
  const escaped = String(pattern).replace(/[.+?^${}()|[\]\\]/g, '\\$&').replaceAll('*', '.*');
  return new RegExp(`^${escaped}$`, 'i').test(action);
}

export function hasRoleAssignmentWrite(permissionResponse) {
  return (permissionResponse?.value ?? []).some((grant) =>
    (grant.actions ?? []).some((pattern) => actionMatches(pattern, ROLE_ASSIGNMENT_WRITE))
    && !(grant.notActions ?? []).some((pattern) => actionMatches(pattern, ROLE_ASSIGNMENT_WRITE)));
}

function normalizeCondition(value) {
  return String(value ?? '').replace(/\s+/g, '').toLowerCase();
}

export function hasApprovedBootstrapAssignment(assignments, { principalId, scope, replayRunnerPrincipalId = '' }) {
  return (assignments ?? []).some((assignment) =>
    String(assignment.principalId ?? '').toLowerCase() === String(principalId ?? '').toLowerCase()
    && String(assignment.roleDefinitionName ?? '').toLowerCase() === ROLE_ASSIGNMENT_ADMIN.toLowerCase()
    && String(assignment.scope ?? '').toLowerCase() === String(scope ?? '').toLowerCase()
    && String(assignment.conditionVersion ?? '') === '2.0'
    && normalizeCondition(assignment.condition) === normalizeCondition(buildBootstrapCondition(replayRunnerPrincipalId)));
}

export function assessRbacBootstrap({ expectedSubscriptionId, expectedTenantId, expectedClientId, expectedPrincipalId, expectedReplayRunnerPrincipalId = '', account, targetScope, permissionResponse, assignments }) {
  const equalGuid = (left, right) => typeof left === 'string' && typeof right === 'string' && left.toLowerCase() === right.toLowerCase();
  const checks = [
    { id: 'subscription', status: equalGuid(account?.id, expectedSubscriptionId) ? 'PASS' : 'FAIL' },
    { id: 'directory', status: equalGuid(account?.tenantId, expectedTenantId) ? 'PASS' : 'FAIL' },
    { id: 'bootstrap-principal', status: equalGuid(account?.user?.name, expectedClientId) && account?.user?.type === 'servicePrincipal' ? 'PASS' : 'FAIL' },
    { id: 'role-assignment-write', status: hasRoleAssignmentWrite(permissionResponse) ? 'PASS' : 'FAIL', scope: targetScope },
    { id: 'exact-conditional-bootstrap-grant', status: hasApprovedBootstrapAssignment(assignments, { principalId: expectedPrincipalId, scope: targetScope, replayRunnerPrincipalId: expectedReplayRunnerPrincipalId }) ? 'PASS' : 'FAIL', scope: targetScope },
  ];
  return { schemaVersion: 1, status: checks.every((check) => check.status === 'PASS') ? 'PASS' : 'FAIL', checks };
}

function runAz(args) {
  try {
    return execFileSync('az', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch {
    throw new Error(`Azure RBAC bootstrap preflight command failed: az ${args[0]} ${args[1] ?? ''}`.trim());
  }
}

async function main() {
  const expectedSubscriptionId = process.env.AZURE_EXPECTED_SUBSCRIPTION_ID;
  const expectedTenantId = process.env.AZURE_EXPECTED_TENANT_ID;
  const expectedClientId = process.env.AZURE_RBAC_BOOTSTRAP_CLIENT_ID;
  const expectedPrincipalId = process.env.AZURE_RBAC_BOOTSTRAP_PRINCIPAL_OBJECT_ID;
  const expectedReplayRunnerPrincipalId = process.env.REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID ?? '';
  const resourceGroup = process.env.AZURE_TARGET_RESOURCE_GROUP;
  if (![expectedSubscriptionId, expectedTenantId, expectedClientId, expectedPrincipalId].every((value) => /^[0-9a-f-]{36}$/i.test(value ?? ''))
    || !/^rg-[a-z0-9-]+$/i.test(resourceGroup ?? '')
    || (expectedReplayRunnerPrincipalId && !/^[0-9a-f-]{36}$/i.test(expectedReplayRunnerPrincipalId))) {
    throw new Error('Expected subscription, directory, bootstrap principal, or target resource-group input is missing or malformed.');
  }

  const account = JSON.parse(runAz(['account', 'show', '--output', 'json']));
  if (account.id?.toLowerCase() !== expectedSubscriptionId.toLowerCase() || account.tenantId?.toLowerCase() !== expectedTenantId.toLowerCase()) {
    throw new Error('RBAC bootstrap OIDC session does not match the approved subscription and directory.');
  }

  if (runAz(['group', 'exists', '--name', resourceGroup, '--subscription', expectedSubscriptionId]).trim() !== 'true') {
    throw new Error(resourceGroup === 'rg-orderprocessing-dev'
      ? `Target resource group is missing; run 00a first. ${DEV_BOOTSTRAP_GUIDANCE}`
      : 'Target resource group is missing; create the environment foundation before RBAC bootstrap preflight.');
  }

  const targetScope = `/subscriptions/${expectedSubscriptionId}/resourceGroups/${resourceGroup}`;
  const permissionUrl = `https://management.azure.com${targetScope}/providers/Microsoft.Authorization/permissions?api-version=2015-07-01`;
  const permissionResponse = JSON.parse(runAz(['rest', '--method', 'get', '--url', permissionUrl, '--output', 'json']));
  const assignments = JSON.parse(runAz(['role', 'assignment', 'list', '--scope', targetScope, '--include-inherited', '--output', 'json']));
  const result = assessRbacBootstrap({ expectedSubscriptionId, expectedTenantId, expectedClientId, expectedPrincipalId, expectedReplayRunnerPrincipalId, account, targetScope, permissionResponse, assignments });
  const summary = [
    '## Phase 10 RBAC bootstrap identity preflight',
    '',
    '| Check | Result |',
    '|---|---|',
    ...result.checks.map(({ id, status }) => `| ${id} | ${status} |`),
    '',
    `Status: **${result.status}**. The preflight is read-only; it does not create role assignments. Scope: \`${targetScope}\`.`,
    '',
  ].join('\n');
  if (process.env.GITHUB_STEP_SUMMARY) {
    const fs = await import('node:fs/promises');
    await fs.appendFile(process.env.GITHUB_STEP_SUMMARY, summary);
  }
  console.log(`Azure RBAC bootstrap preflight: ${result.status} (${result.checks.filter((check) => check.status === 'PASS').length}/${result.checks.length} checks).`);
  if (result.status !== 'PASS') {
    if (resourceGroup === 'rg-orderprocessing-dev' && result.checks.some(({ id, status }) =>
      ['role-assignment-write', 'exact-conditional-bootstrap-grant'].includes(id) && status === 'FAIL')) {
      console.error(DEV_BOOTSTRAP_GUIDANCE);
    }
    process.exitCode = 1;
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => { console.error(`Azure RBAC bootstrap preflight failed: ${error.message}`); process.exitCode = 1; });
}
