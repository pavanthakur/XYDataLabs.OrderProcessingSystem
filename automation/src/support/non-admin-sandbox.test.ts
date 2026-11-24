import assert from "node:assert/strict";
import test from "node:test";
import { applicationTenantClaimType, assertAssignedSandboxRoutes, assertNonAdminSandboxClaims, mapNonAdminSandboxIdentities } from "./non-admin-sandbox.js";

const identity = { objectId: "11111111-1111-4111-8111-111111111111", directoryId: "22222222-2222-4222-8222-222222222222", apiClientId: "33333333-3333-4333-8333-333333333333", identityType: "member" as const };
const tenantClaimType = applicationTenantClaimType(identity.apiClientId);
const claims = { oid: identity.objectId, tid: identity.directoryId, aud: `api://${identity.apiClientId}`,
  scp: "access_as_user", [tenantClaimType]: "TenantB" };
const token = (payload: object) => `fixture.${Buffer.from(JSON.stringify(payload)).toString("base64url")}.fixture`;

test("only the pinned delegated non-admin tenant identity passes for guest and member accounts", () => {
  assert.doesNotThrow(() => assertNonAdminSandboxClaims(token(claims), "TenantB", identity));
  for (const changes of [
    { oid: "other-user" }, { tid: "other-directory" }, { aud: "other-app" }, { scp: "other_scope" },
    { [tenantClaimType]: "TenantA" }, { roles: ["Platform-Admin"] }, { roles: ["phase10-operator"] }
  ]) {
    assert.throws(() => assertNonAdminSandboxClaims(token({ ...claims, ...changes }), "TenantB", identity), /no order was created/);
  }
  assert.throws(() => assertNonAdminSandboxClaims("malformed", "TenantB", identity), /no order was created/);
  assert.throws(() => assertNonAdminSandboxClaims(token({ ...claims, oid: "private-value", scp: "other_scope" }), "TenantB", identity),
    { message: "Non-admin identity checks failed: account-object-id, delegated-scope; no order was created." });
  const guestIdentity = { ...identity, identityType: "guest" as const };
  assert.doesNotThrow(() => assertNonAdminSandboxClaims(token(claims), "TenantB", guestIdentity));
});

test("private non-admin manifests select exactly the requested guest or member identities", () => {
  const tenants = ["TenantA", "TenantB", "TenantC"];
  const base = {
    schemaVersion: 1, environment: "dev", directoryId: identity.directoryId, apiClientId: identity.apiClientId,
    users: tenants.map((tenantCode, index) => ({
      tenantCode,
      objectId: `44444444-4444-4444-8444-44444444444${index}`,
      email: `guest-${index}@example.test`,
      userPrincipalName: `member-${index}@example.test`
    }))
  };
  const guest = mapNonAdminSandboxIdentities(base, "guest");
  assert.equal(guest.TenantA.identityType, "guest");
  assert.equal(guest.TenantC.objectId, base.users[2].objectId);
  const member = mapNonAdminSandboxIdentities({ ...base, identityType: "member" }, "member");
  assert.equal(member.TenantB.identityType, "member");
  assert.equal(member.TenantB.objectId, base.users[1].objectId);
  assert.throws(() => mapNonAdminSandboxIdentities({ ...base, identityType: "member" }, "guest"), /does not match its private manifest/);
  assert.throws(() => mapNonAdminSandboxIdentities({ ...base, identityType: "member", users: base.users.map(({ tenantCode, objectId, email }) => ({ tenantCode, objectId, email })) }, "member"), /one distinct, complete identity/);
  assert.throws(() => mapNonAdminSandboxIdentities({ ...base, users: [base.users[0], base.users[0], base.users[2]] }, "guest"), /one distinct, complete identity/);
});

test("Entra application-tenant claim name is derived from the API client ID", () => {
  assert.equal(tenantClaimType, "extension_33333333333343338333333333333333_applicationTenantCode");
  assert.throws(() => applicationTenantClaimType("not-a-guid"), /valid API client ID/);
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
