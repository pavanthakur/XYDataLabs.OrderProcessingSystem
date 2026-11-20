import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { verifyStandalonePaymentEvidence } from "./phase10-standalone-payment.js";
import { PHASE10_DOCKER_SERVICES } from "./phase10-images.js";

const commit = "a".repeat(40);

function imageManifest(runId: string, capturePoint: "before" | "after") {
  return { schema: "phase10-docker-image-identities-v1", runId, capturePoint,
    candidate: { commit, worktree: "clean", dirtyStatusSha256: null }, buildLogsSha256: {},
    images: PHASE10_DOCKER_SERVICES.map((service, index) => ({ project: "xy-phase10", service,
      containerId: (index + 1).toString(16).padStart(12, "0"), imageReference: `local/${service}:dev`,
      imageId: `sha256:${(index + 1).toString(16).padStart(64, "0")}`, repositoryDigests: [] })) };
}

async function writeJson(root: string, relativePath: string, value: unknown): Promise<void> {
  const path = join(root, ...relativePath.split("/"));
  await mkdir(join(path, ".."), { recursive: true });
  await writeFile(path, JSON.stringify(value) + "\n");
}

async function createSealedFixture(root: string, kind: "deterministic" | "sandbox-positive" | "sandbox-negative"): Promise<void> {
  const runId = root.split(/[\\/]/).at(-1)!;
  const mode = kind === "deterministic" ? "deterministic" : "sandbox";
  const negative = kind === "sandbox-negative";
  const providers = negative ? ["Razorpay"] : ["Razorpay", "OpenPay"];
  const tenants = [{ tenant: "TenantA", status: "Active", tier: "SharedPool", providers: [
    { provider: "Razorpay", threeDs: false }, { provider: "OpenPay", threeDs: false }
  ] }];
  const seed = { status: "passed", scope: "docker-dev", activeTenantCount: 1, supportedProviders: ["Razorpay", "OpenPay"], tenants };
  const outcomes = negative ? ["expected-failure", "expected-cancelled"] : ["completed"];
  const rows: Record<string, unknown>[] = [];
  const groups: Record<string, unknown>[] = [];
  const matrixRoot = `payments/matrix-${kind}`;
  for (const provider of providers) for (const outcome of outcomes) {
    const caseRunId = `payment-automation-2026-11-20T12-01-${String(groups.length).padStart(2, "0")}-001Z`;
    const orderId = 100 + groups.length;
    const reference = "fbdf39bc-e1bc-48fc-9520-47848338aebd";
    const paymentId = `pay_${provider.toLowerCase()}_${orderId}`;
    const currency = provider === "Razorpay" ? "INR" : "MXN";
    const providerVerification = outcome === "expected-failure" ? "sandbox:failed"
      : outcome === "expected-cancelled" ? "checkout-dismissed:order-unpaid"
        : mode === "deterministic" ? "deterministic:completed" : "sandbox:completed";
    const row = { runId: caseRunId, tenantCode: "TenantA", paymentProvider: provider, adapterMode: mode,
      threeDsSetting: "disabled", observedChallenge: "not-presented", journeyOutcome: outcome,
      verificationOutcome: "passed", cleanupOutcome: "reset", executionEvidence: "fresh", orderId,
      orderReferenceId: reference, orderAmount: 200, orderCurrencyCode: currency, providerVerification,
      customerOrderId: `ORDER-${orderId}` };
    rows.push(row);
    const reportDirectory = `${matrixRoot}/${caseRunId}`;
    const caseDirectory = `${reportDirectory}/TenantA/${provider.toLowerCase()}`;
    const providerOrderId = `order_${orderId}`;
    const prefix = `PaymentProviderEvidence Provider=${provider} Simulation=${mode === "deterministic" ? "True" : "False"}`;
    const evidence = [`${prefix} Operation=create-charge ProviderPaymentId=${provider === "Razorpay" ? providerOrderId : paymentId}`];
    if (mode === "sandbox" && outcome !== "expected-cancelled") evidence.push(`${prefix} Operation=fetch-charge ProviderPaymentId=${paymentId}`);
    await writeJson(root, `${reportDirectory}/summary.json`, { runId: caseRunId });
    await writeJson(root, `${reportDirectory}/acceptance-validated-rows.json`, [row]);
    await writeJson(root, `${reportDirectory}/provider-dependencies.json`, { mode, evidence });
    await writeJson(root, `${reportDirectory}/${outcome === "completed" ? "positive" : "negative"}-sql-proof.json`, {
      tenantCode: "TenantA", orderId, status: "passed", expectedOutcome: outcome === "expected-failure" ? "failure" :
        outcome === "expected-cancelled" ? "cancelled" : "success", orderStatus: outcome === "completed" ? "Paid" : "Created",
      successfulCharges: outcome === "completed" ? 1 : 0, allAttempts: 1, failedAttempts: outcome === "expected-failure" ? 1 : 0,
      allPayinLogs: 1
    });
    const runPrefix = `fixture-${orderId}`;
    await writeJson(root, `${caseDirectory}/case-ledger.json`, { schemaVersion: 1, runtimeTarget: "docker-dev-http", runPrefix, tenantCode: "TenantA", provider,
      verification: "passed", restoration: "passed", mutation: outcome === "completed" ? "provider-confirmed" : "submission-started",
      anchors: { orderId, orderReferenceId: reference, amount: 200, currency, providerPaymentId: paymentId },
      row });
    if (outcome === "completed") {
      await writeJson(root, `${caseDirectory}/provider-confirmation.json`, { tenant: "TenantA", orderId,
        orderReferenceId: reference, amount: 200, currency, adapterMode: mode,
        confirmation: { paymentId, providerOrderId, status: "completed", remoteStatusConfirmed: true, isSuccess: true,
          providerAmount: 200, providerCurrency: currency } });
      await writeJson(root, `${reportDirectory}/TenantA-${provider.toLowerCase()}-verification-report.json`, {
        Checks: { confirmation: { Outcome: "PASS" } }, ChargeCorrelation: [{ Tenant: "TenantA", CustomerOrderId: `ORDER-${orderId}`,
          ChargeId: paymentId, InDb: true, UiCallbackLogged: true }]
      });
    }
    groups.push({ runId: caseRunId, runPrefix, rows: [row] });
  }
  if (mode === "sandbox") groups.push(negative ? { provider: "OpenPay", status: "blocked" }
    : { provider: "Razorpay", status: "blocked", threeDs: true });
  const summary = { mode, negative, status: "passed", caseCount: rows.length, expectedCaseCount: rows.length,
    coveragePassed: true, primaryPassed: true, skippedTenants: [], results: groups };
  await writeJson(root, `${matrixRoot}/summary.json`, summary);
  await writeJson(root, "seed-contract.json", seed);
  await writeJson(root, "restoration-contract.json", { ...seed, capturedUtc: "later" });
  await writeJson(root, "payment-run.json", { schema: "phase10-sealed-payment-run-v1", runId, matrix: kind, status: "passed", rawExitCode: 0 });
  await writeJson(root, "docker-image-identities-before.json", imageManifest(runId, "before"));
  await writeJson(root, "docker-image-identities-after.json", imageManifest(runId, "after"));
  const sha256: Record<string, string> = {};
  async function visit(dir: string, prefix = ""): Promise<void> {
    const { readdir } = await import("node:fs/promises");
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.isDirectory()) await visit(join(dir, entry.name), relative);
      else if (entry.name.endsWith(".json")) {
        const bytes = await (await import("node:fs/promises")).readFile(join(dir, entry.name));
        sha256[relative] = createHash("sha256").update(bytes).digest("hex");
      }
    }
  }
  await visit(root);
  await writeJson(root, "payment-evidence-seal.json", { schema: "phase10-payment-evidence-v1", runId, sha256 });
}

test("standalone payment verification accepts each complete sealed matrix and blocks tampering", async () => {
  const parent = await mkdtemp(join(tmpdir(), "phase10-payment-seal-"));
  try {
    for (const kind of ["deterministic", "sandbox-positive", "sandbox-negative"] as const) {
      const root = join(parent, `phase10-payment-${kind}`);
      await mkdir(root);
      await createSealedFixture(root, kind);
      assert.equal((await verifyStandalonePaymentEvidence(root, kind, commit))?.status, "PASS", kind);
      await writeFile(join(root, "payment-run.json"), "{}\n");
      assert.equal(await verifyStandalonePaymentEvidence(root, kind, commit), undefined, `${kind} tamper`);
    }
  } finally {
    await rm(parent, { recursive: true, force: true });
  }
});
