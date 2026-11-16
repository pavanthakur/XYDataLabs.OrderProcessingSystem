import assert from "node:assert/strict";
import { test } from "node:test";
import { approveDlqReplay } from "./dlq-replay-approval.js";

const quarantineId = "11111111-1111-4111-8111-111111111111";
const replayRequestId = "22222222-2222-4222-8222-222222222222";
const accessToken = (roles: string[]) => `header.${Buffer.from(JSON.stringify({ roles })).toString("base64url")}.signature`;
const approval = {
  quarantineId,
  replayRequestId,
  state: "Approved",
  approvedUtc: "2026-11-16T00:00:00Z",
  alreadyApproved: false
};

function response(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), { status, headers: { "content-type": "application/json" } });
}

test("posts one approval to the Azure dev API and returns only validated metadata", async () => {
  let calls = 0;
  const result = await approveDlqReplay({
    environment: "dev",
    apiBaseUrl: "https://api.dev.example.test/",
    tenantCode: "TenantA",
    quarantineId,
    accessToken: accessToken(["phase10-operator"]),
    fetchImpl: async (input, init) => {
      calls += 1;
      assert.equal(String(input), `https://api.dev.example.test/api/v1/admin/dlq/${quarantineId}/approve`);
      assert.equal(init?.method, "POST");
      assert.equal(new Headers(init?.headers).get("authorization"), `Bearer ${accessToken(["phase10-operator"])}`);
      assert.equal(new Headers(init?.headers).get("x-tenant-code"), "TenantA");
      return response(200, approval);
    }
  });
  assert.equal(calls, 1);
  assert.deepEqual(result, approval);
});

test("blocks wrong environment, missing role, malformed token, and invalid quarantine before network access", async () => {
  let calls = 0;
  const fetchImpl = async () => { calls += 1; return response(200, approval); };
  const base = { environment: "dev", apiBaseUrl: "https://api.dev.example.test/", tenantCode: "TenantA", quarantineId, accessToken: accessToken(["phase10-operator"]), fetchImpl };
  await assert.rejects(approveDlqReplay({ ...base, environment: "prod" }), /restricted to Azure dev/);
  await assert.rejects(approveDlqReplay({ ...base, accessToken: accessToken(["platform-admin"]) }), /no phase10-operator role claim/);
  await assert.rejects(approveDlqReplay({ ...base, accessToken: "not-a-jwt" }), /no phase10-operator role claim/);
  await assert.rejects(approveDlqReplay({ ...base, quarantineId: "not-a-guid" }), /valid quarantine ID/);
  assert.equal(calls, 0);
});

test("rejects non-HTTPS, credential-bearing, or path-qualified API origins before approval", async () => {
  let calls = 0;
  const base = { environment: "dev", tenantCode: "TenantA", quarantineId, accessToken: accessToken(["phase10-operator"]), fetchImpl: async () => { calls += 1; return response(200, approval); } };
  for (const apiBaseUrl of ["http://api.dev.example.test/", "https://user:pass@api.dev.example.test/", "https://api.dev.example.test/prefix"]) {
    await assert.rejects(approveDlqReplay({ ...base, apiBaseUrl }), /clean HTTPS API origin/);
  }
  assert.equal(calls, 0);
});

test("401/403 and missing quarantine fail without exposing response details", async () => {
  for (const [status, expected] of [[401, /401/], [403, /403/], [404, /not found/]] as const) {
    const secretResponse = "must-not-appear-in-error";
    await assert.rejects(approveDlqReplay({
      environment: "dev", apiBaseUrl: "https://api.dev.example.test/", tenantCode: "TenantA", quarantineId,
      accessToken: accessToken(["phase10-operator"]),
      fetchImpl: async () => response(status, { detail: secretResponse })
    }), error => {
      assert.match((error as Error).message, expected);
      assert.doesNotMatch((error as Error).message, /must-not-appear-in-error/);
      return true;
    });
  }
});

test("does not retry ambiguous approval failures and requires operator reconciliation", async () => {
  let calls = 0;
  await assert.rejects(approveDlqReplay({
    environment: "dev", apiBaseUrl: "https://api.dev.example.test/", tenantCode: "TenantA", quarantineId,
    accessToken: accessToken(["phase10-operator"]),
    fetchImpl: async () => { calls += 1; throw new Error("transport contains secret token"); }
  }), /not retried.*Reconcile/);
  assert.equal(calls, 1);
});

test("rejects malformed or mismatched success evidence rather than calling it approved", async () => {
  const badPayloads = [
    { ...approval, quarantineId: replayRequestId },
    { ...approval, replayRequestId: "not-a-guid" },
    { ...approval, state: "Rejected" },
    { ...approval, alreadyApproved: "false" },
    { ...approval, approvedUtc: "not-a-date" }
  ];
  for (const payload of badPayloads) {
    await assert.rejects(approveDlqReplay({
      environment: "dev", apiBaseUrl: "https://api.dev.example.test/", tenantCode: "TenantA", quarantineId,
      accessToken: accessToken(["phase10-operator"]), fetchImpl: async () => response(200, payload)
    }), /did not match the requested quarantine/);
  }
});
