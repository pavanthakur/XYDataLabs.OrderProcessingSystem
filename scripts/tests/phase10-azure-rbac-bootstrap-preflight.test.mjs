import test from 'node:test';
import assert from 'node:assert/strict';
import { assessRbacBootstrap, buildBootstrapCondition, hasApprovedBootstrapAssignment, hasRoleAssignmentWrite } from '../phase10-azure-rbac-bootstrap-preflight.mjs';

const subscriptionId = '11111111-1111-1111-1111-111111111111';
const tenantId = '22222222-2222-2222-2222-222222222222';
const clientId = '55555555-5555-5555-5555-555555555555';
const principalId = '33333333-3333-3333-3333-333333333333';
const scope = `/subscriptions/${subscriptionId}/resourceGroups/rg-orderprocessing-dev`;
const roleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b';
const condition = buildBootstrapCondition();
const grant = {
  principalId,
  roleDefinitionName: 'Role Based Access Control Administrator',
  scope,
  conditionVersion: '2.0',
  condition,
};

test('bootstrap preflight accepts exact identity, scope, role and constrained add/delete condition', () => {
  const permissions = { value: [{ actions: ['Microsoft.Authorization/roleAssignments/*'], notActions: [] }] };
  assert.equal(hasRoleAssignmentWrite(permissions), true);
  assert.equal(hasApprovedBootstrapAssignment([grant], { principalId, scope }), true);
  const result = assessRbacBootstrap({
    expectedSubscriptionId: subscriptionId,
    expectedTenantId: tenantId,
    expectedClientId: clientId,
    expectedPrincipalId: principalId,
    account: { id: subscriptionId, tenantId, user: { name: clientId, type: 'servicePrincipal' } },
    targetScope: scope,
    permissionResponse: permissions,
    assignments: [grant],
  });
  assert.equal(result.status, 'PASS');
});

test('bootstrap preflight rejects wrong principal, wider scope, changed role allowlist and missing delete restriction', () => {
  const invalidAssignments = [
    { ...grant, principalId: '44444444-4444-4444-4444-444444444444' },
    { ...grant, scope: `/subscriptions/${subscriptionId}` },
    { ...grant, condition: condition.replace(roleId, 'acdd72a7-3385-48ef-bd42-f606fba81ae7') },
    { ...grant, condition: condition.replace("ActionMatches{'Microsoft.Authorization/roleAssignments/delete'}", "ActionMatches{'not-a-delete-action'}") },
    { ...grant, conditionVersion: '1.0' },
  ];
  for (const assignment of invalidAssignments) {
    assert.equal(hasApprovedBootstrapAssignment([assignment], { principalId, scope }), false);
  }
});

test('bootstrap preflight fails when the effective write action is excluded', () => {
  assert.equal(hasRoleAssignmentWrite({ value: [{ actions: ['*'], notActions: ['Microsoft.Authorization/roleAssignments/write'] }] }), false);
});

test('bootstrap preflight rejects a different authenticated service principal', () => {
  const result = assessRbacBootstrap({
    expectedSubscriptionId: subscriptionId,
    expectedTenantId: tenantId,
    expectedClientId: clientId,
    expectedPrincipalId: principalId,
    account: { id: subscriptionId, tenantId, user: { name: '66666666-6666-6666-6666-666666666666', type: 'servicePrincipal' } },
    targetScope: scope,
    permissionResponse: { value: [{ actions: ['Microsoft.Authorization/roleAssignments/write'], notActions: [] }] },
    assignments: [grant],
  });
  assert.equal(result.status, 'FAIL');
  assert.deepEqual(result.checks.filter((check) => check.status === 'FAIL').map((check) => check.id), ['bootstrap-principal']);
});

test('replay bootstrap condition allows only the two Service Bus roles for the pinned user', () => {
  const runnerId = '77777777-7777-7777-7777-777777777777';
  const constrained = buildBootstrapCondition(runnerId);
  assert.match(constrained, /4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0, 69a216fc-b8fb-44d8-bc22-1f3c2cd27a39/);
  assert.match(constrained, new RegExp(`PrincipalId\\] ForAnyOfAnyValues:GuidEquals \\{${runnerId}\\}`));
  assert.match(constrained, /StringEqualsIgnoreCase \{'User'\}/);
  assert.match(constrained, /b7e6dc6d-f1e8-4753-8033-0f276bb0955b/);
  assert.equal(hasApprovedBootstrapAssignment([{ ...grant, condition: constrained }], { principalId, scope, replayRunnerPrincipalId: runnerId }), true);
  assert.equal(hasApprovedBootstrapAssignment([{ ...grant, condition: constrained }], { principalId, scope, replayRunnerPrincipalId: '88888888-8888-8888-8888-888888888888' }), false);
  assert.equal(hasApprovedBootstrapAssignment([{ ...grant, condition: constrained }], { principalId, scope }), false);
});
