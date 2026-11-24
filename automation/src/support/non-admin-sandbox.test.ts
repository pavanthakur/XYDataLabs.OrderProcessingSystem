import assert from "node:assert/strict";
import test from "node:test";
import { assertAssignedSandboxRoutes, assertNonAdminSandboxClaims } from "./non-admin-sandbox.js";

const identity = { objectId: "fixture-user", directoryId: "fixture-directory", apiClientId: "fixture-api" };
const claims = { oid: identity.objectId, tid: identity.directoryId, aud: `api://${identity.apiClientId}`,
  scp: "access_as_user", "extn.applicationTenantCode": "TenantB" };
const token = (payload: object) => `fixture.${Buffer.from(JSON.stringify(payload)).toString("base64url")}.fixture`;

test("only the pinned delegated non-admin tenant identity passes", () => {
  assert.doesNotThrow(() => assertNonAdminSandboxClaims(token(claims), "TenantB", identity));
  for (const changes of [
    { oid: "other-user" }, { tid: "other-directory" }, { aud: "other-app" }, { scp: "other_scope" },
    { "extn.applicationTenantCode": "TenantA" }, { roles: ["Platform-Admin"] }, { roles: ["phase10-operator"] }
  ]) {
    assert.throws(() => assertNonAdminSandboxClaims(token({ ...claims, ...changes }), "TenantB", identity), /no order was created/);
  }
  assert.throws(() => assertNonAdminSandboxClaims("malformed", "TenantB", identity), /no order was created/);
  assert.throws(() => assertNonAdminSandboxClaims(token({ ...claims, oid: "private-value", scp: "other_scope" }), "TenantB", identity),
    { message: "Non-admin identity checks failed: guest-account, delegated-scope; no order was created." });
});

test("provider drift, missing tenants and duplicate routes stop the assigned-provider plan", () => {
  const plan = [
    { tenantCode: "TenantA", paymentProviderCode: "Razorpay" },
    { tenantCode: "TenantB", paymentProviderCode: "Razorpay" },
    { tenantCode: "TenantC", paymentProviderCode: "OpenPay" }
  ];
  assert.doesNotThrow(() => assertAssignedSandboxRoutes(plan));
  assert.throws(() => assertAssignedSandboxRoutes(plan.slice(0, 2)), /routes differ/);
  assert.throws(() => assertAssignedSandboxRoutes([plan[0], plan[0], plan[2]]), /routes differ/);
  assert.throws(() => assertAssignedSandboxRoutes([...plan.slice(0, 2), { ...plan[2], paymentProviderCode: "Razorpay" }]), /routes differ/);
});
