import assert from "node:assert/strict";
import test from "node:test";
import { assertReplayApproverToken, type ReplayApproverTokenExpectation } from "./replay-approver-token.js";

const expected: ReplayApproverTokenExpectation = {
  objectId: "11111111-1111-4111-8111-111111111111",
  directoryId: "22222222-2222-4222-8222-222222222222",
  apiClientId: "33333333-3333-4333-8333-333333333333",
  tenantCode: "TenantA"
};
const token = (claims: Record<string, unknown>) => `header.${Buffer.from(JSON.stringify(claims)).toString("base64url")}.signature`;
const validClaims = {
  oid: expected.objectId, tid: expected.directoryId, aud: `api://${expected.apiClientId}`,
  scp: "access_as_user", roles: ["phase10-operator"], "extn.applicationTenantCode": "TenantA"
};

test("accepts only the pinned approver API token with TenantA and phase10-operator claims", () => {
  assert.doesNotThrow(() => assertReplayApproverToken(token({ ...validClaims, aud: `api://${expected.apiClientId}` }), expected));
});

test("rejects malformed and mismatched replay approver tokens without exposing claims", () => {
  assert.throws(() => assertReplayApproverToken("not-a-jwt", expected), /valid API access token/);
  for (const claims of [
    { ...validClaims, oid: "44444444-4444-4444-8444-444444444444" },
    { ...validClaims, tid: "44444444-4444-4444-8444-444444444444" },
    { ...validClaims, roles: ["platform-admin"] },
    { ...validClaims, roles: ["phase10-operator", "platform-admin"] },
    { ...validClaims, roles: ["phase10-operator", null] },
    { ...validClaims, roles: "phase10-operator" },
    { ...validClaims, roles: ["phase10-operator", "other-role"] },
    { ...validClaims, scp: "profile" },
    { ...validClaims, "extn.applicationTenantCode": "TenantB" }
  ]) assert.throws(() => assertReplayApproverToken(token(claims), expected), /no replay action was performed/);
});
