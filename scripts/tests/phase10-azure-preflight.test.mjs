import test from 'node:test';
import assert from 'node:assert/strict';
import { assessAzurePreflight, hasEffectiveAction } from '../phase10-azure-preflight.mjs';

const subscriptionId = '11111111-1111-1111-1111-111111111111';
const tenantId = '22222222-2222-2222-2222-222222222222';
const providerStates = Object.fromEntries([
  'Microsoft.App', 'Microsoft.Cache', 'Microsoft.ContainerRegistry', 'Microsoft.Insights', 'Microsoft.KeyVault',
  'Microsoft.ManagedIdentity', 'Microsoft.OperationalInsights', 'Microsoft.ServiceBus', 'Microsoft.Sql',
  'Microsoft.Storage', 'Microsoft.Web',
].map((provider) => [provider, 'Registered']));

test('Azure preflight accepts matching identity, registered providers and narrowly granted role assignment action', () => {
  const permissions = { value: [{ actions: ['Microsoft.Authorization/roleAssignments/*'], notActions: [] }] };
  assert.equal(hasEffectiveAction(permissions), true);
  const result = assessAzurePreflight({
    expectedSubscriptionId: subscriptionId,
    expectedTenantId: tenantId,
    account: { id: subscriptionId, tenantId },
    targetScope: `/subscriptions/${subscriptionId}/resourceGroups/rg-orderprocessing-dev`,
    permissionResponse: permissions,
    providerStates,
  });
  assert.equal(result.status, 'PASS');
});

test('Azure preflight fails closed for wrong subscription, missing role-assignment write, and unregistered providers', () => {
  assert.equal(hasEffectiveAction({ value: [{ actions: ['*'], notActions: ['Microsoft.Authorization/roleAssignments/write'] }] }), false);
  const result = assessAzurePreflight({
    expectedSubscriptionId: subscriptionId,
    expectedTenantId: tenantId,
    account: { id: '33333333-3333-3333-3333-333333333333', tenantId },
    targetScope: `/subscriptions/${subscriptionId}`,
    permissionResponse: { value: [{ actions: ['Microsoft.Resources/*'], notActions: [] }] },
    providerStates: { ...providerStates, 'Microsoft.Storage': 'NotRegistered' },
  });
  assert.equal(result.status, 'FAIL');
  assert.deepEqual(result.checks.filter((check) => check.status === 'FAIL').map((check) => check.id), ['subscription', 'role-assignment-write', 'provider:Microsoft.Storage']);
});
