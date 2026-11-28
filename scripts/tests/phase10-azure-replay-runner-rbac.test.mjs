import test from 'node:test';
import assert from 'node:assert/strict';
import { planReplayRunnerRoleAssignments, SERVICE_BUS_DATA_RECEIVER_ROLE_ID, SERVICE_BUS_DATA_SENDER_ROLE_ID } from '../phase10-azure-replay-runner-rbac.mjs';

const input = {
  subscriptionId: '11111111-1111-1111-1111-111111111111',
  resourceGroup: 'rg-orderprocessing-dev',
  namespaceName: 'sb-orderprocessing-dev',
  queueName: 'dlq-replay-drill-requests-dev',
  topicName: 'order-events-dev',
  runnerPrincipalId: '22222222-2222-2222-2222-222222222222',
};

test('replay runner plan contains only exact dev queue receive and business topic send grants', () => {
  const plan = planReplayRunnerRoleAssignments(input);
  assert.deepEqual(plan.map(({ roleId, principalType, scope, purpose }) => ({ roleId, principalType, scope, purpose })), [
    {
      roleId: SERVICE_BUS_DATA_RECEIVER_ROLE_ID,
      principalType: 'User',
      scope: `/subscriptions/${input.subscriptionId}/resourceGroups/${input.resourceGroup}/providers/Microsoft.ServiceBus/namespaces/${input.namespaceName}/queues/${input.queueName}`,
      purpose: 'isolated-drill-queue-receive',
    },
    {
      roleId: SERVICE_BUS_DATA_SENDER_ROLE_ID,
      principalType: 'User',
      scope: `/subscriptions/${input.subscriptionId}/resourceGroups/${input.resourceGroup}/providers/Microsoft.ServiceBus/namespaces/${input.namespaceName}/topics/${input.topicName}`,
      purpose: 'business-topic-send',
    },
  ]);
  assert.ok(plan.every((entry) => entry.principalId === input.runnerPrincipalId));
});

test('replay runner plan fails closed for malformed IDs, non-dev scope, or unsafe entity names', () => {
  for (const invalid of [
    { ...input, subscriptionId: 'not-a-guid' },
    { ...input, runnerPrincipalId: 'not-a-guid' },
    { ...input, resourceGroup: 'rg-orderprocessing-prod' },
    { ...input, queueName: '../other-queue' },
    { ...input, topicName: '' },
  ]) assert.throws(() => planReplayRunnerRoleAssignments(invalid), /dev-only inputs/);
});

test('hosted CI includes replay-runner RBAC scope regression tests', async () => {
  const { readFile } = await import('node:fs/promises');
  const workflow = await readFile('.github/workflows/ci.yml', 'utf8');
  assert.match(workflow, /phase10-azure-replay-runner-rbac\.test\.mjs/);
});
