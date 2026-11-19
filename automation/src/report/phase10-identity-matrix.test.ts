import test from "node:test";
import assert from "node:assert/strict";
import { normalizePhase10IdentityMatrix } from "./phase10-identity-matrix.js";

const seed = {
  status: "passed",
  activeTenantCount: 2,
  tenants: [
    { tenant: "TenantA", status: "Active" },
    { tenant: "TenantB", status: "Active" },
    { tenant: "DisabledTenant", status: "Inactive" }
  ]
};

function passingSummary(): { results: Array<Record<string, unknown>> } {
  return { results: [
    { account: "tenant-admin", tenant: "TenantA", status: "passed", httpStatus: 200, customerCount: 5 },
    { account: "tenant-admin", tenant: "TenantB", status: "passed", httpStatus: 200, customerCount: 4 },
    { account: "private-user-a", tenant: "TenantA", status: "passed", httpStatus: 200,
      deniedTenant: "TenantB", deniedStatus: 403, customerCount: 5 },
    { account: "private-user-b", tenant: "TenantB", status: "passed", httpStatus: 200,
      deniedTenant: "TenantA", deniedStatus: 403, customerCount: 4 },
    { scenario: "same-browser login/logout and cross-tab logout", status: "passed" }
  ] };
}

test("identity matrix derives admin, assigned-user, cross-tenant denial and logout expectations from active tenants", () => {
  const report = normalizePhase10IdentityMatrix(passingSummary(), seed);
  assert.equal(report.status, "PASS");
  assert.equal(report.expected, 5);
  assert.equal(report.observed, 5);
  assert.deepEqual(report.cases.map(item => item.role), ["platform-admin", "platform-admin", "tenant-user", "tenant-user", "logout"]);
  assert.deepEqual(report.cases.filter(item => item.role === "tenant-user").map(item => item.deniedHttpStatus), [403, 403]);
  assert.equal(JSON.stringify(report).includes("private-user"), false, "account names must not be emitted");
});

test("missing, duplicate, unseeded or unsafe identity cases are blocked", () => {
  const summary = passingSummary();
  summary.results.pop();
  const missing = normalizePhase10IdentityMatrix(summary, seed);
  assert.equal(missing.status, "BLOCKED");
  assert.ok(missing.issues.some(issue => issue.includes("logout")));

  const duplicate = passingSummary();
  duplicate.results.push(duplicate.results[0]);
  assert.equal(normalizePhase10IdentityMatrix(duplicate, seed).status, "BLOCKED");

  const outside = passingSummary();
  outside.results[0] = { account: "tenant-admin", tenant: "UnknownTenant", status: "passed", httpStatus: 200, customerCount: 1 };
  assert.equal(normalizePhase10IdentityMatrix(outside, seed).status, "BLOCKED");

  const unsafeDenial = passingSummary();
  unsafeDenial.results[2] = { ...unsafeDenial.results[2] as object, deniedTenant: "DisabledTenant", deniedStatus: 403 };
  assert.equal(normalizePhase10IdentityMatrix(unsafeDenial, seed).status, "BLOCKED");
});

test("explicit identity failures remain FAIL and inconsistent active tenant metadata blocks", () => {
  const failure = passingSummary();
  failure.results[2] = { ...failure.results[2] as object, status: "failed", httpStatus: 403 };
  assert.equal(normalizePhase10IdentityMatrix(failure, seed).status, "FAIL");

  assert.equal(normalizePhase10IdentityMatrix(passingSummary(), { ...seed, activeTenantCount: 3 }).status, "BLOCKED");
  assert.equal(normalizePhase10IdentityMatrix(undefined, seed).status, "BLOCKED");
});
