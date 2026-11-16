import assert from "node:assert/strict";
import test from "node:test";
import { validateLocalDlqApprovalResponse, validateLocalOperatorClaims } from "../../frontend/apps/web/scripts/phase10-local-dlq-approval-contract.mjs";

const quarantineId = "11111111-1111-4111-8111-111111111111";
const replayRequestId = "22222222-2222-4222-8222-222222222222";
const approvedUtc = "2026-11-16T10:00:00.000Z";

test("accepts only a fresh matching local approval response", () => {
  assert.deepEqual(validateLocalDlqApprovalResponse(quarantineId, {
    quarantineId: quarantineId.toUpperCase(), replayRequestId, state: "Approved", approvedUtc, alreadyApproved: false
  }), { quarantineId: quarantineId.toUpperCase(), replayRequestId, state: "Approved", approvedUtc, alreadyApproved: false });
});

test("rejects prior approval, mismatched IDs, invalid timestamps, and incomplete response", () => {
  const valid = { quarantineId, replayRequestId, state: "approved", approvedUtc, alreadyApproved: false };
  assert.throws(() => validateLocalDlqApprovalResponse(quarantineId, { ...valid, alreadyApproved: true }), /incomplete metadata/);
  assert.throws(() => validateLocalDlqApprovalResponse(quarantineId, { ...valid, quarantineId: replayRequestId }), /incomplete metadata/);
  assert.throws(() => validateLocalDlqApprovalResponse(quarantineId, { ...valid, approvedUtc: "invalid" }), /incomplete metadata/);
  assert.throws(() => validateLocalDlqApprovalResponse(quarantineId, null), /incomplete metadata/);
  assert.throws(() => validateLocalDlqApprovalResponse("not-a-guid", valid), /valid quarantine ID/);
});

test("requires the explicit operator role and tenant scope unless global access is explicitly claimed", () => {
  assert.throws(() => validateLocalOperatorClaims({ realm_access: { roles: ["platform-admin"] } }, "TenantA"), /lacks phase10-operator/);
  assert.throws(() => validateLocalOperatorClaims({ realm_access: { roles: ["phase10-operator"] }, tenant_code: "TenantA" }, "TenantB"), /not assigned/);
  assert.doesNotThrow(() => validateLocalOperatorClaims({ realm_access: { roles: ["phase10-operator"] }, tenant_code: "TenantA" }, "TenantA"));
  assert.doesNotThrow(() => validateLocalOperatorClaims({ realm_access: { roles: ["phase10-operator", "platform-admin"] } }, "TenantC"));
});
