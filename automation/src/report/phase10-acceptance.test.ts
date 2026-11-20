import assert from "node:assert/strict";
import { test } from "node:test";
import { DOCKER_PACKET_STEPS } from "./phase10-report.js";
import { NFR_REQUIRED_CATEGORIES, phase10PaymentConfigurationMatches, reconcilePhase10Acceptance } from "./phase10-acceptance.js";
import type { AcceptanceInput } from "./phase10-acceptance.js";
import type { Phase10ImageManifest } from "./phase10-images.js";

const commit = "a".repeat(40);
const snapshot = { commit, worktree: "clean" };
const imageServices = ["sql-server", "redis", "azurite", "servicebus-sql", "servicebus-emulator", "keycloak-local", "orders", "payments", "inventory", "notifications", "gateway", "ui", "functions"];
const imageManifest = (runId: string, capturePoint: "before" | "after"): Phase10ImageManifest => ({
  schema: "phase10-docker-image-identities-v1", runId, capturePoint,
  candidate: { commit, worktree: "clean", dirtyStatusSha256: null }, buildLogsSha256: {},
  images: imageServices.map((service, index) => ({ project: "xy-phase10", service,
    containerId: (index + 1).toString(16).padStart(12, "0"), imageReference: `local/${service}:dev`,
    imageId: `sha256:${(index + 1).toString(16).padStart(64, "0")}`, repositoryDigests: [] }))
});
const passing = (): AcceptanceInput => ({
  expectedCommit: commit,
  e2e: {
    completion: "COMPLETE", completionStatus: "passed", reportIssuesClean: true,
    summary: { runId: "phase10-docker-http-20261111-000000001", gitProvenance: { start: snapshot, finish: snapshot }, storageExitCode: 0 },
    packet: {
      storageExitCode: 0, deferrals: ["DW-023", "DW-024"],
      restoration: { allRestored: true, fixtureLockPresent: false },
      steps: DOCKER_PACKET_STEPS.map(name => ({ name, status: name === "order-continuation" ? "blocked" : "passed" }))
    },
    coverage: {
      backend: Array.from({ length: 5 }, () => ({ state: "MEASURED" })),
      frontend: { state: "MEASURED" }, integration: { state: "MEASURED" }
    },
    imageBefore: imageManifest("phase10-docker-http-20261111-000000001", "before"),
    imageAfter: imageManifest("phase10-docker-http-20261111-000000001", "after")
  },
  nfr: {
    sealVerified: true,
    summary: {
      status: "passed", commitSha: commit, commitShaAtFinish: commit, worktreeAtStart: "clean", worktreeAtFinish: "clean",
      runDir: "C:/results/phase10-docker-nfr-20261111-000000002",
      categories: Object.fromEntries(NFR_REQUIRED_CATEGORIES.map(name => [name, {
        status: "passed",
        checks: name === "recovery" ? [{ name: "Rollback inventory to previous image", status: "passed" },
          { name: "Restore inventory current image", status: "passed" }] : []
      }]))
    },
    performanceProbe: { Status: "passed", ExpectedMessages: 100, InventoryInboxCount: 100, NotificationsInboxCount: 100,
      InventoryEffectCount: 100, NotificationEffectCount: 100, P95Seconds: 1.9 },
    replayProof: { status: "passed", replayVisibilitySeconds: 4.2 },
    outageDrill: { status: "passed", lostMessages: 0, duplicateEffects: 0, backlogRecoverySeconds: 35 },
    imageBefore: imageManifest("phase10-docker-nfr-20261111-000000002", "before"),
    imageAfter: imageManifest("phase10-docker-nfr-20261111-000000002", "after"),
    imageRunId: "phase10-docker-nfr-20261111-000000002"
  }
});

test("otherwise passing results cannot substitute for the NFR evidence seal", () => {
  const input = passing();
  delete input.nfr.sealVerified;
  const result = reconcilePhase10Acceptance(input);
  assert.equal(result.gates.find(item => item.name === "nfr-run-evidence-seal")?.status, "BLOCKED");
  assert.equal(result.verdict, "INCOMPLETE");
  (input.nfr.summary as { status: string }).status = "failed";
  assert.equal(reconcilePhase10Acceptance(input).verdict, "FAIL");
});

test("full no-charge NFR needs a sealed linked matrix and never excuses a failed check", () => {
  const input = passing();
  const paymentRunId = "phase10-payments";
  input.payments = {
    completionStatus: "passed", configurationMatched: true,
    sandboxGates: { status: "passed", primaryPassed: true, results: [false, true].map(negative =>
      ({ negative, status: "passed", primaryPassed: true, rawExitCode: 0 })) },
    packet: structuredClone(input.e2e.packet),
    summary: { runId: paymentRunId, paymentSuite: "both", acceptanceProfile: "baseline", gitProvenance: { start: snapshot, finish: snapshot } },
    imageBefore: imageManifest(paymentRunId, "before"), imageAfter: imageManifest(paymentRunId, "after")
  };
  (input.e2e.summary as Record<string, unknown>).paymentSuite = "none";
  input.e2e.completionStatus = "partial";
  const steps = (input.e2e.packet as { steps: Array<{ name: string; status: string }> }).steps;
  for (const step of steps.filter(item => ["tenantc-routing-regression", "payments-deterministic", "sandbox-payments"].includes(item.name))) {
    step.status = "not-run";
  }
  input.nfr.settingsUnchanged = true;
  const nfr = input.nfr.summary as Record<string, unknown>;
  nfr.status = "incomplete";
  nfr.selection = { mode: "full", dynamicPaymentMatrix: "not-run-explicit", selectedCategories: [...NFR_REQUIRED_CATEGORIES] };
  nfr.paymentSettingsIntegrity = "passed";
  const categories = nfr.categories as Record<string, Record<string, unknown>>;
  for (const category of Object.values(categories)) category.execution = "selected";
  Object.assign(categories.payments, { status: "partial", integrationStatus: "passed", dynamicMatrixStatus: "not-run", checks: [
    { name: "Payment provider integration tests", status: "passed" },
    { name: "Dynamic provider payment matrix", status: "not-run" }
  ] });
  assert.equal(reconcilePhase10Acceptance(input).verdict, "PASS", JSON.stringify(reconcilePhase10Acceptance(input).gates));
  const missing = structuredClone(input); delete missing.payments;
  assert.equal(reconcilePhase10Acceptance(missing).verdict, "INCOMPLETE");
  const settings = structuredClone(input); settings.payments!.configurationMatched = false;
  assert.equal(reconcilePhase10Acceptance(settings).verdict, "INCOMPLETE");
  const images = structuredClone(input);
  (images.payments!.imageAfter as ReturnType<typeof imageManifest>).images[0].imageId = `sha256:${"b".repeat(64)}`;
  assert.equal(reconcilePhase10Acceptance(images).verdict, "INCOMPLETE");
  const missingNegative = structuredClone(input);
  (missingNegative.payments!.sandboxGates as { results: unknown[] }).results.pop();
  assert.equal(reconcilePhase10Acceptance(missingNegative).verdict, "INCOMPLETE");
  const failed = structuredClone(input);
  (failed.payments!.sandboxGates as { status: string }).status = "failed";
  assert.equal(reconcilePhase10Acceptance(failed).verdict, "FAIL");
  nfr.paymentSettingsIntegrity = "failed";
  assert.equal(reconcilePhase10Acceptance(input).verdict, "FAIL");
});

test("three standalone sealed payment matrices can satisfy the separate no-charge E2E payment gate", () => {
  const input = passing();
  (input.e2e.summary as Record<string, unknown>).paymentSuite = "none";
  input.e2e.completionStatus = "partial";
  const steps = (input.e2e.packet as { steps: Array<{ name: string; status: string }> }).steps;
  for (const step of steps.filter(item => ["payments-deterministic", "sandbox-payments"].includes(item.name))) step.status = "not-run";
  const nfr = input.nfr.summary as Record<string, unknown>;
  nfr.status = "incomplete";
  nfr.selection = { mode: "full", dynamicPaymentMatrix: "not-run-explicit", selectedCategories: [...NFR_REQUIRED_CATEGORIES] };
  nfr.paymentSettingsIntegrity = "passed";
  const categories = nfr.categories as Record<string, Record<string, unknown>>;
  for (const category of Object.values(categories)) category.execution = "selected";
  Object.assign(categories.payments, { status: "partial", integrationStatus: "passed", dynamicMatrixStatus: "not-run", checks: [
    { name: "Payment provider integration tests", status: "passed" }, { name: "Dynamic provider payment matrix", status: "not-run" }
  ] });
  input.nfr.settingsUnchanged = true;
  input.standalonePayments = (["deterministic", "sandbox-positive", "sandbox-negative"] as const).map(kind => ({
    kind, runId: "phase10-payment-standalone", status: "PASS" as const, configurationMatched: true,
    before: imageManifest("phase10-payment-standalone", "before"), after: imageManifest("phase10-payment-standalone", "after")
  }));
  const records = input.standalonePayments;
  assert.equal(reconcilePhase10Acceptance(input).verdict, "PASS");
  records.pop();
  assert.equal(reconcilePhase10Acceptance(input).verdict, "INCOMPLETE");
  records.push({ kind: "sandbox-negative", runId: "phase10-payment-standalone", status: "FAIL", configurationMatched: true,
    before: imageManifest("phase10-payment-standalone", "before"), after: imageManifest("phase10-payment-standalone", "after") });
  assert.equal(reconcilePhase10Acceptance(input).verdict, "FAIL");
});

test("provider configuration links require identical NFR snapshots and matching non-production baselines", () => {
  const tenant = { status: "Active", tier: "SharedPool", registryRoute: "Razorpay", businessDatabase: "Dev" };
  const before = { schema: "phase10-payment-settings-snapshot-v1", tenants: [
    { ...tenant, code: "TenantA", providers: [{ provider: "Razorpay", threeDs: false, production: false }] }
  ] };
  const baseline = { status: "passed", tenants: [{ ...tenant, tenant: "TenantA", providers: [{
    provider: "Razorpay", threeDs: false, nonProduction: true, merchantMatchesLocal: true, publicKeyMatchesLocal: true, privateKeyReferenceCorrect: true
  }] }] };
  assert.equal(phase10PaymentConfigurationMatches(before, structuredClone(before), baseline, baseline), true);
  const changed = structuredClone(baseline); changed.tenants[0].providers[0].threeDs = true;
  assert.equal(phase10PaymentConfigurationMatches(before, before, baseline, changed), false);
  assert.equal(phase10PaymentConfigurationMatches(before, { ...before, tenants: [] }, baseline, baseline), false);
});

test("a fully evidenced single-candidate run passes while deferrals and L6/Azure stay visible and uncounted", () => {
  const result = reconcilePhase10Acceptance(passing());
  assert.equal(result.verdict, "PASS");
  assert.equal(result.gates.find(item => item.name === "e2e-order-continuation")?.status, "DEFERRED");
  assert.equal(result.gates.find(item => item.name === "l6-ci-parity-and-azure")?.status, "NOT-RUN");
  assert.ok(result.notCertified.includes("Azure deployment"));
});

test("order continuation without a recorded DW-023 deferral blocks", () => {
  const input = passing();
  (input.e2e.packet as { deferrals: string[] }).deferrals = [];
  assert.equal(reconcilePhase10Acceptance(input).verdict, "INCOMPLETE");
});

test("an explicit order-continuation failure is not hidden by its DW-023 deferral", () => {
  const input = passing();
  const steps = (input.e2e.packet as { steps: { name: string; status: string }[] }).steps;
  steps.find(step => step.name === "order-continuation")!.status = "failed";
  const result = reconcilePhase10Acceptance(input);
  assert.equal(result.gates.find(item => item.name === "e2e-order-continuation")?.status, "FAIL");
  assert.equal(result.verdict, "FAIL");
});

test("a skipped, blocked or missing NFR category is never a pass", () => {
  for (const status of ["skipped", "blocked", "running"]) {
    const input = passing();
    const categories = (input.nfr.summary as { categories: Record<string, { status: string }> }).categories;
    categories.recovery.status = status;
    assert.equal(reconcilePhase10Acceptance(input).verdict, "INCOMPLETE", status);
  }
  const missing = passing();
  delete (missing.nfr.summary as { categories: Record<string, unknown> }).categories.operational;
  assert.equal(reconcilePhase10Acceptance(missing).verdict, "INCOMPLETE");
});

test("failures outrank incompleteness", () => {
  const input = passing();
  (input.nfr.summary as { status: string }).status = "failed";
  assert.equal(reconcilePhase10Acceptance(input).verdict, "FAIL");
  const step = passing();
  (step.e2e.packet as { steps: { name: string; status: string }[] }).steps[0].status = "failed";
  assert.equal(reconcilePhase10Acceptance(step).verdict, "FAIL");
});

test("different commit or dirty worktree on either run is rejected", () => {
  const other = passing();
  (other.e2e.summary as { gitProvenance: { finish: { commit: string } } }).gitProvenance.finish.commit = "b".repeat(40);
  assert.equal(reconcilePhase10Acceptance(other).verdict, "INCOMPLETE");
  const dirty = passing();
  (dirty.nfr.summary as { worktreeAtFinish: string }).worktreeAtFinish = "dirty";
  assert.equal(reconcilePhase10Acceptance(dirty).verdict, "INCOMPLETE");
  const absent = passing();
  delete (absent.nfr.summary as { worktreeAtStart?: string }).worktreeAtStart;
  assert.equal(reconcilePhase10Acceptance(absent).verdict, "INCOMPLETE");
});

test("same source SHA with different service image IDs fails cross-run reconciliation", () => {
  const input = passing();
  const changed = input.nfr.imageBefore as ReturnType<typeof imageManifest>;
  changed.images.find(image => image.service === "inventory")!.imageId = `sha256:${"f".repeat(64)}`;
  const changedAfter = input.nfr.imageAfter as ReturnType<typeof imageManifest>;
  changedAfter.images.find(image => image.service === "inventory")!.imageId = `sha256:${"f".repeat(64)}`;
  const result = reconcilePhase10Acceptance(input);
  assert.equal(result.gates.find(item => item.name === "e2e-nfr-image-consistency")?.status, "FAIL");
  assert.equal(result.verdict, "FAIL");
});

test("missing, duplicate, malformed, or dirty image evidence blocks the candidate", () => {
  for (const mutate of [
    (input: AcceptanceInput) => { input.e2e.imageBefore = undefined; },
    (input: AcceptanceInput) => { (input.e2e.imageAfter as ReturnType<typeof imageManifest>).images[1].service = "orders"; },
    (input: AcceptanceInput) => { (input.nfr.imageBefore as ReturnType<typeof imageManifest>).images[0].imageId = "not-an-image-id"; },
    (input: AcceptanceInput) => { (input.e2e.imageAfter as ReturnType<typeof imageManifest>).candidate.worktree = "dirty"; }
  ]) {
    const input = passing();
    mutate(input);
    assert.notEqual(reconcilePhase10Acceptance(input).verdict, "PASS");
  }
});

test("drill thresholds are enforced: replay 60s, recovery 30 minutes, no loss, no duplicates, P95 30s", () => {
  const cases: [string, (input: AcceptanceInput) => void][] = [
    ["replay too slow", input => { (input.nfr.replayProof as { replayVisibilitySeconds: number }).replayVisibilitySeconds = 61; }],
    ["recovery too slow", input => { (input.nfr.outageDrill as { backlogRecoverySeconds: number }).backlogRecoverySeconds = 1801; }],
    ["message lost", input => { (input.nfr.outageDrill as { lostMessages: number }).lostMessages = 1; }],
    ["duplicate effect", input => { (input.nfr.outageDrill as { duplicateEffects: number }).duplicateEffects = 1; }],
    ["p95 too high", input => { (input.nfr.performanceProbe as { P95Seconds: number }).P95Seconds = 31; }],
    ["burst short", input => { (input.nfr.performanceProbe as { InventoryEffectCount: number }).InventoryEffectCount = 99; }],
    ["no drill evidence", input => { input.nfr.outageDrill = undefined; }],
    ["no rollback evidence", input => {
      ((input.nfr.summary as { categories: { recovery: { checks: unknown[] } } }).categories.recovery.checks) = []; }]
  ];
  for (const [name, mutate] of cases) {
    const input = passing();
    mutate(input);
    assert.notEqual(reconcilePhase10Acceptance(input).verdict, "PASS", name);
  }
});

test("an unsealed, issue-bearing or coverage-less report blocks acceptance", () => {
  const unsealed = passing();
  unsealed.e2e.completion = "INCOMPLETE";
  assert.equal(reconcilePhase10Acceptance(unsealed).verdict, "INCOMPLETE");
  const issues = passing();
  issues.e2e.reportIssuesClean = false;
  assert.equal(reconcilePhase10Acceptance(issues).verdict, "INCOMPLETE");
  const coverage = passing();
  (coverage.e2e.coverage as { frontend: { state: string } }).frontend.state = "UNAVAILABLE";
  assert.equal(reconcilePhase10Acceptance(coverage).verdict, "INCOMPLETE");
});
