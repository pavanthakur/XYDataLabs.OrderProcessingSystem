import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const SERVICE_BUS_DATA_RECEIVER_ROLE_ID = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0';
export const SERVICE_BUS_DATA_SENDER_ROLE_ID = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39';

export function planReplayRunnerRoleAssignments({ subscriptionId, resourceGroup, namespaceName, queueName, topicName, runnerPrincipalId }) {
  const guid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!guid.test(subscriptionId ?? '') || !guid.test(runnerPrincipalId ?? '')
    || !/^rg-orderprocessing-dev$/i.test(resourceGroup ?? '')
    || !/^[a-z0-9-]{3,50}$/i.test(namespaceName ?? '')
    || !/^[a-z0-9-]{1,260}$/i.test(queueName ?? '')
    || !/^[a-z0-9-]{1,260}$/i.test(topicName ?? '')) {
    throw new Error('Replay runner role plan has missing or invalid dev-only inputs.');
  }

  const base = `/subscriptions/${subscriptionId}/resourceGroups/${resourceGroup}/providers/Microsoft.ServiceBus/namespaces/${namespaceName}`;
  return [
    { roleId: SERVICE_BUS_DATA_RECEIVER_ROLE_ID, principalType: 'User', principalId: runnerPrincipalId, scope: `${base}/queues/${queueName}`, purpose: 'isolated-drill-queue-receive' },
    { roleId: SERVICE_BUS_DATA_SENDER_ROLE_ID, principalType: 'User', principalId: runnerPrincipalId, scope: `${base}/topics/${topicName}`, purpose: 'business-topic-send' },
  ];
}

function runAz(args) {
  try {
    return execFileSync('az', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch {
    throw new Error(`Replay runner RBAC command failed: az ${args.slice(0, 3).join(' ')}`);
  }
}

function readExactAssignment(scope, principalId, roleId) {
  const raw = runAz(['role', 'assignment', 'list', '--scope', scope, '--assignee-object-id', principalId, '--output', 'json', '--only-show-errors']);
  let assignments;
  try { assignments = JSON.parse(raw); } catch { throw new Error('Azure returned malformed role-assignment data.'); }
  return assignments.filter((item) => String(item.scope ?? '').toLowerCase() === scope.toLowerCase()
    && String(item.principalId ?? '').toLowerCase() === principalId.toLowerCase()
    && String(item.roleDefinitionId ?? '').toLowerCase().endsWith(roleId.toLowerCase())
    && String(item.principalType ?? '').toLowerCase() === 'user');
}

async function main() {
  const subscriptionId = process.env.AZURE_EXPECTED_SUBSCRIPTION_ID ?? '';
  const resourceGroup = process.env.AZURE_TARGET_RESOURCE_GROUP ?? '';
  const namespaceName = process.env.SERVICE_BUS_NAMESPACE_NAME ?? '';
  const queueName = process.env.REPLAY_DRILL_REQUEST_QUEUE_NAME ?? '';
  const topicName = process.env.ORDER_EVENTS_TOPIC_NAME ?? '';
  const runnerPrincipalId = process.env.REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID ?? '';
  const account = JSON.parse(runAz(['account', 'show', '--output', 'json']));
  if (account.id?.toLowerCase() !== subscriptionId.toLowerCase()) {
    throw new Error('Azure CLI is not authenticated to the approved subscription.');
  }

  const planned = planReplayRunnerRoleAssignments({ subscriptionId, resourceGroup, namespaceName, queueName, topicName, runnerPrincipalId });
  const queueScope = runAz(['servicebus', 'queue', 'show', '--resource-group', resourceGroup, '--namespace-name', namespaceName, '--name', queueName, '--query', 'id', '--output', 'tsv']).trim();
  const topicScope = runAz(['servicebus', 'topic', 'show', '--resource-group', resourceGroup, '--namespace-name', namespaceName, '--name', topicName, '--query', 'id', '--output', 'tsv']).trim();
  if (queueScope.toLowerCase() !== planned[0].scope.toLowerCase() || topicScope.toLowerCase() !== planned[1].scope.toLowerCase()) {
    throw new Error('Service Bus resource read-back does not match the exact dev queue/topic role scopes.');
  }
  const results = [];
  for (const grant of planned) {
    const existing = readExactAssignment(grant.scope, grant.principalId, grant.roleId);
    if (existing.length > 1) throw new Error(`Duplicate exact assignment detected for ${grant.purpose}; refusing mutation.`);
    let action = existing.length === 1 ? 'verified-existing' : 'created';
    if (existing.length === 0) {
      runAz(['role', 'assignment', 'create', '--assignee-object-id', grant.principalId, '--assignee-principal-type', grant.principalType, '--role', grant.roleId, '--scope', grant.scope, '--only-show-errors', '--output', 'json']);
    }
    const verified = readExactAssignment(grant.scope, grant.principalId, grant.roleId);
    if (verified.length !== 1) throw new Error(`Exact role assignment read-back failed for ${grant.purpose}.`);
    results.push({ purpose: grant.purpose, action, status: 'PASS' });
  }

  const table = ['## Phase 10 replay runner RBAC', '', '| Grant | Action | Result |', '|---|---|---|', ...results.map((entry) => `| ${entry.purpose} | ${entry.action} | ${entry.status} |`), '', 'Assignments are limited to the pinned user, dev replay queue and business topic. No role removals were attempted.', ''].join('\n');
  if (process.env.GITHUB_STEP_SUMMARY) {
    const fs = await import('node:fs/promises');
    await fs.appendFile(process.env.GITHUB_STEP_SUMMARY, table);
  }
  console.log(`Replay runner RBAC verified: ${results.length}/${planned.length} exact grants.`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => { console.error(`Replay runner RBAC setup failed: ${error.message}`); process.exitCode = 1; });
}
