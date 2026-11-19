import assert from "node:assert/strict";
import { test } from "node:test";
import { normalizePaymentMatrix } from "./phase10-payment-matrix.js";

const digest = "a".repeat(64);
const tenants = ["TenantA", "TenantB", "TenantC"].map((tenant, index) => ({
  tenant, status: "Active", tier: index === 2 ? "Dedicated" : "SharedPool",
  providers: [{ provider: "Razorpay", threeDs: false }, { provider: "OpenPay", threeDs: false }]
}));
const seed = { status: "passed", activeTenantCount: 3, supportedProviders: ["Razorpay", "OpenPay"], tenants };

function row(tenantCode: string, paymentProvider: string, runId: string, journeyOutcome = "completed", providerVerification = "sandbox:completed") {
  return {
    runId, tenantCode, paymentProvider, adapterMode: "sandbox", threeDsSetting: "disabled",
    observedChallenge: paymentProvider === "Razorpay" ? "presented" : "not-presented",
    journeyOutcome, verificationOutcome: "passed", cleanupOutcome: "reset", executionEvidence: "fresh",
    orderId: 101, orderReferenceId: "fbdf39bc-e1bc-48fc-9520-47848338aebd", orderAmount: 200,
    orderCurrencyCode: paymentProvider === "Razorpay" ? "INR" : "MXN",
    providerVerification, errorDetail: "SECRET_DO_NOT_RENDER"
  };
}

function runEntry(item: ReturnType<typeof row>, index: number) {
  const runId = `payment-automation-2026-11-20T00-00-${String(index).padStart(2, "0")}-000Z`;
  return { runId, rows: [{ ...item, runId }] };
}
const positives = tenants.flatMap(tenant => ["Razorpay", "OpenPay"].map(provider => ({ tenant: tenant.tenant, provider })))
  .map(({ tenant, provider }, index) => runEntry(row(tenant, provider, "pending"), index));
const negativeRows = tenants.flatMap(tenant => [
  { tenant: tenant.tenant, outcome: "expected-failure", verification: "sandbox:failed" },
  { tenant: tenant.tenant, outcome: "expected-cancelled", verification: "checkout-dismissed:order-unpaid" }
]).map((item, index) => runEntry(row(item.tenant, "Razorpay", "pending", item.outcome, item.verification), index));

test("positive payment matrix reconciles active tenants and providers, and ignores empty optional placeholders", () => {
  const summary = { mode: "sandbox", negative: false, status: "passed", caseCount: 6, expectedCaseCount: 6,
    coveragePassed: true, primaryPassed: true, skippedTenants: [], results: [...positives, { rows: [] }, { rows: [] }, { rows: [] }] };
  const result = normalizePaymentMatrix("sandbox-positive", summary, seed, digest, digest);
  assert.equal(result.status, "PASS");
  assert.equal(result.expected, 6);
  assert.equal(result.observed, 6);
  assert.equal(result.cases.length, 6);
  assert.ok(result.cases.every(item => item.status === "PASS"));
  assert.equal(JSON.stringify(result).includes("SECRET_DO_NOT_RENDER"), false);
});

test("negative coverage requires expected failure and cancellation for every active tenant", () => {
  const summary = { mode: "sandbox", negative: true, status: "passed", caseCount: 6, expectedCaseCount: 6,
    coveragePassed: true, primaryPassed: true, skippedTenants: [], results: negativeRows };
  const result = normalizePaymentMatrix("sandbox-negative", summary, seed, digest, digest);
  assert.equal(result.status, "PASS");
  assert.equal(result.expected, 6);
  assert.ok(result.cases.every(item => item.status === "PASS"));
});

test("missing, duplicate, unexpected, malformed and contradictory evidence never passes", () => {
  const summary = { mode: "sandbox", negative: false, status: "passed", caseCount: 6, expectedCaseCount: 6,
    coveragePassed: true, primaryPassed: true, skippedTenants: [], results: positives };
  const missing = normalizePaymentMatrix("sandbox-positive", { ...summary, results: positives.slice(1) }, seed, digest, digest);
  assert.equal(missing.status, "BLOCKED");
  assert.ok(missing.cases.some(item => item.status === "NOT-RUN"));

  const duplicate = normalizePaymentMatrix("sandbox-positive", { ...summary, results: [...positives, positives[0]] }, seed, digest, digest);
  assert.equal(duplicate.status, "BLOCKED");
  assert.ok(duplicate.issues.some(issue => issue.includes("duplicate")));

  const contradictory = normalizePaymentMatrix("deterministic", summary, seed, digest, digest);
  assert.equal(contradictory.status, "BLOCKED");

  const malformedSeed = normalizePaymentMatrix("sandbox-positive", summary, { ...seed, tenants: [] }, digest, digest);
  assert.equal(malformedSeed.status, "BLOCKED");

  const changedThreeDs = { ...seed, tenants: seed.tenants.map((tenant, index) => index === 0
    ? { ...tenant, providers: tenant.providers.map(provider => provider.provider === "Razorpay" ? { ...provider, threeDs: true } : provider) }
    : tenant) };
  const inconsistentThreeDs = normalizePaymentMatrix("sandbox-positive", summary, changedThreeDs, digest, digest);
  assert.equal(inconsistentThreeDs.status, "BLOCKED");
  assert.ok(inconsistentThreeDs.issues.some(issue => issue.includes("3DS")));

  const unsafeRow = row("<img src=x>", "Razorpay", "payment-automation-2026-11-20T00-00-00-000Z");
  const unsafe = normalizePaymentMatrix("sandbox-positive", { ...summary, results: [{ rows: [unsafeRow] }, ...positives.slice(1)] }, seed, digest, digest);
  assert.equal(unsafe.status, "BLOCKED");
  assert.equal(JSON.stringify(unsafe).includes("<img"), false);
});

test("provider, verification, cleanup and persisted order evidence are required", () => {
  const summary = { mode: "sandbox", negative: false, status: "passed", caseCount: 6, expectedCaseCount: 6,
    coveragePassed: true, primaryPassed: true, skippedTenants: [], results: positives.map((item, index) => index === 0
      ? { rows: [{ ...item.rows[0], verificationOutcome: "pending", cleanupOutcome: "unknown", orderId: null }] }
      : item) };
  const result = normalizePaymentMatrix("sandbox-positive", summary, seed, digest, digest);
  assert.equal(result.status, "BLOCKED");
  assert.equal(result.cases[0].status, "BLOCKED");
  assert.equal(result.cases[0].verification, "BLOCKED");
  assert.equal(result.cases[0].cleanup, "BLOCKED");
  assert.equal(result.cases[0].orderId, null);
});

test("missing evidence digests block otherwise successful cases", () => {
  const summary = { mode: "sandbox", negative: false, status: "passed", caseCount: 6, expectedCaseCount: 6,
    coveragePassed: true, primaryPassed: true, skippedTenants: [], results: positives };
  const result = normalizePaymentMatrix("sandbox-positive", summary, seed);
  assert.equal(result.status, "BLOCKED");
  assert.equal(result.summarySha256, null);
  assert.equal(result.seedContractSha256, null);
});

test("active-tenant count and skipped-tenant inventory must be explicit and consistent", () => {
  const summary = { mode: "sandbox", negative: false, status: "passed", caseCount: 6, expectedCaseCount: 6,
    coveragePassed: true, primaryPassed: true, skippedTenants: [], results: positives };
  assert.equal(normalizePaymentMatrix("sandbox-positive", summary, { ...seed, activeTenantCount: 4 }, digest, digest).status, "BLOCKED");
  assert.equal(normalizePaymentMatrix("sandbox-positive", { ...summary, skippedTenants: undefined }, seed, digest, digest).status, "BLOCKED");
  assert.equal(normalizePaymentMatrix("sandbox-positive", { ...summary, skippedTenants: ["TenantC"] }, seed, digest, digest).status, "BLOCKED");
});

test("authorization-only provider status cannot pass a positive payment case", () => {
  const summary = { mode: "sandbox", negative: false, status: "passed", caseCount: 6, expectedCaseCount: 6,
    coveragePassed: true, primaryPassed: true, skippedTenants: [], results: positives.map((item, index) => index === 0
      ? { rows: [{ ...item.rows[0], providerVerification: "sandbox:authorized" }] } : item) };
  const result = normalizePaymentMatrix("sandbox-positive", summary, seed, digest, digest);
  assert.equal(result.status, "BLOCKED");
  assert.equal(result.cases[0].status, "BLOCKED");
});

test("payment cases require unique matching nested runner IDs", () => {
  const summary = { mode: "sandbox", negative: false, status: "passed", caseCount: 6, expectedCaseCount: 6,
    coveragePassed: true, primaryPassed: true, skippedTenants: [], results: positives };
  const mismatch = structuredClone(summary);
  mismatch.results[0].rows[0].runId = "payment-automation-2026-11-20T00-00-59-000Z";
  const duplicate = structuredClone(summary);
  duplicate.results[1].runId = duplicate.results[0].runId;
  duplicate.results[1].rows[0].runId = duplicate.results[0].runId;
  assert.ok(normalizePaymentMatrix("sandbox-positive", mismatch, seed, digest, digest).issues.some(issue => issue.includes("run identity")));
  assert.ok(normalizePaymentMatrix("sandbox-positive", duplicate, seed, digest, digest).issues.some(issue => issue.includes("run identity")));
});

test("a passing case list cannot override a failed or missing primary runner verdict", () => {
  const summary = { mode: "sandbox", negative: false, status: "passed", caseCount: 6, expectedCaseCount: 6,
    coveragePassed: true, primaryPassed: true, skippedTenants: [], results: positives };
  const failedPrimary = normalizePaymentMatrix("sandbox-positive", { ...summary, primaryPassed: false }, seed, digest, digest);
  const missingPrimary = normalizePaymentMatrix("sandbox-positive", { ...summary, primaryPassed: undefined }, seed, digest, digest);
  assert.equal(failedPrimary.status, "BLOCKED");
  assert.equal(missingPrimary.status, "BLOCKED");
  assert.ok(failedPrimary.issues.some(issue => issue.includes("primary result")));
});
