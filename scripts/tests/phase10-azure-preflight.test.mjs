import test from 'node:test';
import assert from 'node:assert/strict';
import { assessAzurePreflight } from '../phase10-azure-preflight.mjs';

const subscriptionId = '11111111-1111-1111-1111-111111111111';
const tenantId = '22222222-2222-2222-2222-222222222222';
const providerStates = Object.fromEntries([
  'Microsoft.App', 'Microsoft.Cache', 'Microsoft.ContainerRegistry', 'Microsoft.Insights', 'Microsoft.KeyVault',
  'Microsoft.ManagedIdentity', 'Microsoft.OperationalInsights', 'Microsoft.ServiceBus', 'Microsoft.Sql',
  'Microsoft.Storage', 'Microsoft.Web',
].map((provider) => [provider, 'Registered']));

test('Azure preflight accepts matching subscription, directory and registered providers without RBAC write permission', () => {
  const result = assessAzurePreflight({
    expectedSubscriptionId: subscriptionId,
    expectedTenantId: tenantId,
    account: { id: subscriptionId, tenantId },
    providerStates,
  });
  assert.equal(result.status, 'PASS');
});

test('Azure preflight fails closed for wrong subscription and unregistered providers', () => {
  const result = assessAzurePreflight({
    expectedSubscriptionId: subscriptionId,
    expectedTenantId: tenantId,
    account: { id: '33333333-3333-3333-3333-333333333333', tenantId },
    providerStates: { ...providerStates, 'Microsoft.Storage': 'NotRegistered' },
  });
  assert.equal(result.status, 'FAIL');
  assert.deepEqual(result.checks.filter((check) => check.status === 'FAIL').map((check) => check.id), ['subscription', 'provider:Microsoft.Storage']);
});
