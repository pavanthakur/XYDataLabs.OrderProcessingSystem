import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { PHASE10_DOCKER_SERVICES, validatePhase10ImageManifest } from "./phase10-images.js";
import { DOCKER_PACKET_STEPS } from "./phase10-report.js";
import { reconcilePhase10LocalFollowup, renderPhase10LocalFollowupHtml } from "./phase10-local-followup.js";
import { capturePhase10CommittedSnapshotIdentity, capturePhase10WorktreeIdentity } from "./phase10-worktree-identity.js";
import type { LocalFollowupInput } from "./phase10-local-followup.js";

const e2eCommit = "a".repeat(40);
const currentCommit = e2eCommit;
const imageManifest = (runId: string, commit: string, worktree: "clean" | "dirty", capturePoint: "before" | "after") => ({
  schema: "phase10-docker-image-identities-v1", runId, capturePoint,
  candidate: { commit, worktree, dirtyStatusSha256: worktree === "dirty" ? "c".repeat(64) : null,
    worktreeContentSha256: worktree === "dirty" ? "d".repeat(64) : null, changedPaths: worktree === "dirty" ? ["scripts/report-tool.ps1"] : [] }, buildLogsSha256: {},
  images: PHASE10_DOCKER_SERVICES.map((service, index) => ({ project: "xy-phase10", service,
    containerId: (index + 1).toString(16).padStart(12, "0"), imageReference: `local/${service}:test`,
    imageId: `sha256:${(index + 1).toString(16).padStart(64, "0")}`, repositoryDigests: [] }))
});
const paymentSnapshot = () => ({ schema: "phase10-payment-settings-snapshot-v1", sqlMachine: "local", tenants: ["TenantA", "TenantB", "TenantC"].map((code, index) => ({
  id: index + 1, code, status: "Active", tier: index === 2 ? "Dedicated" : "SharedPool",
  registryRoute: index === 2 ? "OpenPay" : "Razorpay",
  businessDatabase: index === 2 ? "OrderProcessingSystem_TenantC_Dev" : "OrderProcessingSystem_Dev",
  businessRoute: index === 2 ? "OpenPay" : "Razorpay",
  providers: ["OpenPay", "Razorpay"].map((provider, providerIndex) => ({ id: index * 2 + providerIndex + 1, provider, threeDs: false, production: false }))
})) });

const base = (): LocalFollowupInput => ({
  e2e: {
    completion: "COMPLETE", completionStatus: "passed",
    summary: { runId: "phase10-docker-http-20261115-194923198", status: "passed", paymentSuite: "both",
      startedUtc: "2026-11-18T19:00:00.000Z", finishedUtc: "2026-11-18T20:00:00.000Z",
      gitProvenance: { start: { commit: e2eCommit, worktree: "clean", contentIdentity: "a".repeat(64) },
        finish: { commit: e2eCommit, worktree: "clean", contentIdentity: "a".repeat(64) } } },
    packet: { status: "passed", deferrals: ["DW-023"], restoration: { status: "passed", allRestored: true, fixtureLockPresent: false },
      steps: DOCKER_PACKET_STEPS.map(name => ({ name, status: name === "order-continuation" ? "deferred" : "passed" })) },
    imageBefore: imageManifest("phase10-docker-http-20261115-194923198", e2eCommit, "clean", "before"),
    imageAfter: imageManifest("phase10-docker-http-20261115-194923198", e2eCommit, "clean", "after"),
    restorationContract: { status: "passed", tenants: ["TenantA", "TenantB", "TenantC"].map((tenant, index) => ({
      tenant, status: "Active", tier: index === 2 ? "Dedicated" : "SharedPool",
      registryRoute: index === 2 ? "OpenPay" : "Razorpay",
      businessDatabase: index === 2 ? "OrderProcessingSystem_TenantC_Dev" : "OrderProcessingSystem_Dev",
      providers: ["OpenPay", "Razorpay"].map(provider => ({ provider, threeDs: false, nonProduction: true }))
    })) }
  },
  noPaymentReport: {
    completion: "COMPLETE", completionStatus: "partial",
    summary: { runId: "phase10-docker-http-20261118-001234567", runRoot: "TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261118-001234567",
      status: "partial", paymentSuite: "none", gitProvenance: { start: { contentIdentity: "a".repeat(64) }, finish: { contentIdentity: "a".repeat(64) } } },
    packet: { status: "partial", runRoot: "TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261118-001234567",
      steps: [{ name: "payments-deterministic", status: "not-run" }, { name: "sandbox-payments", status: "not-run" },
        { name: "foundations", status: "passed" }, { name: "integration", status: "passed" }] },
    coverage: { schema: "phase10-sanitized-coverage-v2", runId: "phase10-docker-http-20261118-001234567", provisional: false }
  },
  current: {
    imageManifest: imageManifest("current-image-audit-p0", currentCommit, "dirty", "after"),
    sourceIdentity: { commit: currentCommit, worktree: "dirty", dirtyStatusSha256: "c".repeat(64),
      worktreeContentSha256: "d".repeat(64), changedPaths: ["scripts/report-tool.ps1"] },
    foundation: { status: "passed", results: [{ status: "passed", exitCode: 0 }, { status: "passed", exitCode: 0 }] },
    functions: { status: "passed", approvalStatus: "processing-confirmed", approvalOutcome: "approved",
      approvalReconciliationRequired: false, intake: "passed", replay: "passed", downstreamEffects: "passed" },
    nfr: { status: "incomplete", paymentSettingsIntegrity: "passed",
      paymentSettingsBefore: paymentSnapshot(), paymentSettingsAfter: paymentSnapshot(),
      categories: {
        functional: { status: "passed" }, performance: { status: "not-run" }, tenant: { status: "passed" },
        payments: { status: "partial", integrationStatus: "passed", dynamicMatrixStatus: "not-run" },
        security: { status: "passed" }, operational: { status: "not-run" }, recovery: { status: "not-run" }
      } },
    burst: { Status: "passed", ExpectedMessages: 100, InventoryInboxCount: 100, NotificationsInboxCount: 100,
      InventoryEffectCount: 100, NotificationEffectCount: 100, P95Seconds: 3.9 },
    outage: { status: "passed", messageCount: 100, inventoryEffects: 100, notificationEffects: 100,
      inventoryInbox: 100, notificationsInbox: 100, lostMessages: 0, duplicateEffects: 0, p95Seconds: 8.6,
      backlogRecoverySeconds: 29, restorationStatus: "passed", environmentRestored: true },
    rollback: { status: "passed", rollbackObserved: true, currentImageRestored: true, databaseRollback: false,
      previousImageId: `sha256:${"d".repeat(64)}`, currentImageId: `sha256:${"e".repeat(64)}` },
    operational: { summary: { categories: { operational: { status: "passed", execution: "selected" }, recovery: { status: "passed", execution: "selected" } } },
      imageManifest: imageManifest("ops-run", currentCommit, "dirty", "after") },
    persistence: { summary: { status: "passed", imageIdentitiesUnchanged: true, disk: "G:\\DockerStorage\\DockerDesktopWSL", sqlVolume: "xy-phase10_phase10-sql-data" },
      before: [{ tenant: "TenantA", orderId: 1 }, { tenant: "TenantB", orderId: 2 }],
      after: [{ tenant: "TenantA", orderId: 1 }, { tenant: "TenantB", orderId: 2 }],
      imageBefore: imageManifest("persistence-run", currentCommit, "dirty", "before"),
      imageAfter: imageManifest("persistence-run", currentCommit, "dirty", "after") },
    replay: { messaging: { Status: "passed", ExpectedMessages: 3, InventoryInboxCount: 3, NotificationsInboxCount: 3, InventoryEffectCount: 3, NotificationEffectCount: 3 },
      restoration: { status: "passed", effectiveSettingMatches: true },
      functions: { status: "passed", approvalSubmissionAttempts: 1, approvalResubmitted: false }, imageManifest: imageManifest("replay-run", currentCommit, "dirty", "after") }
  },
  evidence: [{ id: "source-report", path: "TestResults/example/report.json", sha256: "f".repeat(64) }]
});

const paymentMatrix = (mode: "deterministic" | "sandbox", negative = false) => {
  const tenants = ["TenantA", "TenantB", "TenantC"];
  const rows = negative
    ? tenants.flatMap(tenant => ["expected-failure", "expected-cancelled"].map(journeyOutcome => ({
      tenantCode: tenant, paymentProvider: "Razorpay", journeyOutcome, verificationOutcome: "passed", cleanupOutcome: "reset",
      executionEvidence: "fresh", adapterMode: "sandbox", orderCurrencyCode: "INR",
      providerVerification: journeyOutcome === "expected-failure" ? "sandbox:failed" : "checkout-dismissed:order-unpaid", orderAmount: 200,
      startedUtc: "2026-11-18T19:30:00.000Z", finishedUtc: "2026-11-18T19:31:00.000Z"
    })))
    : tenants.flatMap(tenant => ["Razorpay", "OpenPay"].map(paymentProvider => ({
      tenantCode: tenant, paymentProvider, journeyOutcome: "completed", verificationOutcome: "passed", cleanupOutcome: "reset",
      executionEvidence: "fresh", adapterMode: mode, orderCurrencyCode: paymentProvider === "Razorpay" ? "INR" : "MXN",
      providerVerification: `${mode}:completed`, orderAmount: 200,
      startedUtc: "2026-11-18T19:30:00.000Z", finishedUtc: "2026-11-18T19:31:00.000Z"
    })));
  return {
    mode: negative ? "sandbox" : mode, acceptanceProfile: "baseline", negative, manualSmoke: false,
    caseCount: rows.length, expectedCaseCount: rows.length, coveragePassed: true, status: "passed", primaryPassed: true,
    capabilityAcceptance: negative ? "blocked" : "not-applicable",
    negativeSandboxAcceptance: negative ? "razorpay-passed-openpay-blocked" : "separate-suite", skippedTenants: [],
    results: [...rows.map(row => ({ rows: [row], verificationSafety: negative ? "unknown" : "established",
      verificationSummary: negative ? "Verification skipped." : `Physical verification completed for ${row.tenantCode}.` })), {}, {}, {}]
  };
};
const customerDirectoryRetry = () => ({ results: [
  ...["TenantA", "TenantB", "TenantC"].map(tenant => ({ account: "tenant-admin", tenant, status: "passed", httpStatus: 200 })),
  ...[["tenant-a-user", "TenantA", "TenantB"], ["tenant-b-user", "TenantB", "TenantA"], ["tenant-c-user", "TenantC", "TenantA"]]
    .map(([account, tenant, deniedTenant]) => ({ account, tenant, deniedTenant, status: "passed", httpStatus: 200, deniedStatus: 403 })),
  { scenario: "same-browser login/logout and cross-tab logout", status: "passed" }
] });

test("same image binaries permit scoped evidence reuse but never erase candidate/NFR incompleteness", () => {
  const report = reconcilePhase10LocalFollowup(base());
  assert.equal(report.verdict, "INCOMPLETE");
  assert.equal(report.imageBinaryMatch, true);
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-and-restoration")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "historical-e2e-persistence")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "historical-e2e-order-continuation")?.status, "DEFERRED");
  assert.equal(report.gates.find(item => item.id === "current-image-operational-and-outage")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "current-image-rollback-and-restore")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "current-image-persistence")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "current-image-replay")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "full-current-image-nfr-categories")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "clean-single-source-candidate")?.status, "BLOCKED");
  assert.equal(report.gates.find(item => item.id === "azure-acceptance")?.status, "NOT-RUN");
});

test("separately executed payment matrices are reported without overriding a failed parent E2E run", () => {
  const input = base();
  input.current.paymentMatrices = {
    deterministic: paymentMatrix("deterministic"), sandboxPositive: paymentMatrix("sandbox"),
    sandboxNegative: paymentMatrix("sandbox", true)
  };
  input.current.customerDirectoryRetry = customerDirectoryRetry();
  (input.e2e.packet as { status: string }).status = "failed";
  input.e2e.completionStatus = "failed";
  const report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "supplemental-deterministic-payment-matrix")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "supplemental-sandbox-positive-payment-matrix")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "supplemental-razorpay-sandbox-negative-matrix")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "openpay-sandbox-negative-capability")?.status, "BLOCKED");
  assert.equal(report.gates.find(item => item.id === "payment-matrix-source-image-binding")?.status, "BLOCKED");
  assert.equal(report.gates.find(item => item.id === "supplemental-customer-directory-identity-retry")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-and-restoration")?.status, "FAIL");
  assert.equal(report.verdict, "FAIL");
});

test("a sealed parent E2E envelope binds nested payment summaries to unchanged images and run time", () => {
  const input = base();
  input.current.paymentMatrices = {
    deterministic: paymentMatrix("deterministic"), sandboxPositive: paymentMatrix("sandbox"),
    sandboxNegative: paymentMatrix("sandbox", true)
  };
  input.current.paymentMatrixSource = { summariesAndArtifactsNestedInE2e: true, caseArtifactsHashedAndCorrelated: true };
  let report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "payment-matrix-source-image-binding")?.status, "PASS");

  const changedImage = base();
  changedImage.current.paymentMatrices = input.current.paymentMatrices;
  changedImage.current.paymentMatrixSource = input.current.paymentMatrixSource;
  (changedImage.e2e.imageBefore as ReturnType<typeof imageManifest>).images[0].imageId = `sha256:${"f".repeat(64)}`;
  report = reconcilePhase10LocalFollowup(changedImage);
  assert.equal(report.gates.find(item => item.id === "payment-matrix-source-image-binding")?.status, "BLOCKED");

  const missingCaseArtifacts = base();
  missingCaseArtifacts.current.paymentMatrices = input.current.paymentMatrices;
  missingCaseArtifacts.current.paymentMatrixSource = { summariesAndArtifactsNestedInE2e: true, caseArtifactsHashedAndCorrelated: false };
  report = reconcilePhase10LocalFollowup(missingCaseArtifacts);
  assert.equal(report.gates.find(item => item.id === "payment-matrix-source-image-binding")?.status, "BLOCKED");

  const outOfWindow = base();
  outOfWindow.current.paymentMatrices = input.current.paymentMatrices;
  outOfWindow.current.paymentMatrixSource = input.current.paymentMatrixSource;
  const matrix = outOfWindow.current.paymentMatrices!.sandboxPositive as { results: { rows: { finishedUtc: string }[] }[] };
  matrix.results[0].rows[0].finishedUtc = "2026-11-18T20:01:00.000Z";
  report = reconcilePhase10LocalFollowup(outOfWindow);
  assert.equal(report.gates.find(item => item.id === "payment-matrix-source-image-binding")?.status, "BLOCKED");
});

test("payment matrix reconciliation rejects missing tenant/provider rows and simulated sandbox evidence", () => {
  const input = base();
  const sandbox = paymentMatrix("sandbox");
  ((sandbox.results[0] as { rows: { adapterMode: string }[] }).rows[0]).adapterMode = "deterministic";
  input.current.paymentMatrices = {
    deterministic: paymentMatrix("deterministic"), sandboxPositive: sandbox,
    sandboxNegative: paymentMatrix("sandbox", true)
  };
  const report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "supplemental-sandbox-positive-payment-matrix")?.status, "BLOCKED");
  const incomplete = base();
  const deterministic = paymentMatrix("deterministic");
  (deterministic.results[0] as { rows: unknown[] }).rows.pop();
  incomplete.current.paymentMatrices = {
    deterministic, sandboxPositive: paymentMatrix("sandbox"), sandboxNegative: paymentMatrix("sandbox", true)
  };
  assert.equal(reconcilePhase10LocalFollowup(incomplete).gates.find(item => item.id === "supplemental-deterministic-payment-matrix")?.status, "BLOCKED");
});

test("image mismatch fails reuse of the historical payment evidence", () => {
  const input = base();
  (input.current.imageManifest as ReturnType<typeof imageManifest>).images[0].imageId = `sha256:${"f".repeat(64)}`;
  const report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.imageBinaryMatch, false);
  assert.equal(report.gates.find(item => item.id === "e2e-current-image-binary-match")?.status, "FAIL");
  assert.equal(report.verdict, "FAIL");
});

test("an explicit order-continuation failure is not hidden by the DW-023 deferral", () => {
  const input = base();
  const steps = (input.e2e.packet as { steps: { name: string; status: string }[] }).steps;
  steps.find(step => step.name === "order-continuation")!.status = "failed";
  const report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "historical-e2e-order-continuation")?.status, "FAIL");
  assert.equal(report.verdict, "FAIL");
});

test("failed lifecycle or rollback evidence cannot be reported as a current pass", () => {
  const input = base();
  input.current.functions = { status: "passed", approvalStatus: "pending-reconciliation", approvalOutcome: "approved",
    approvalReconciliationRequired: true, intake: "passed", replay: "passed", downstreamEffects: "passed" };
  input.current.rollback = { status: "passed", rollbackObserved: true, currentImageRestored: false, databaseRollback: false,
    previousImageId: `sha256:${"d".repeat(64)}`, currentImageId: `sha256:${"e".repeat(64)}` };
  const report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "current-functions-replay")?.status, "BLOCKED");
  assert.equal(report.gates.find(item => item.id === "current-image-rollback-and-restore")?.status, "FAIL");
  assert.equal(report.verdict, "FAIL");
});

test("operational pass with not-selected execution metadata is blocked as contradictory", () => {
  const input = base();
  (input.current.operational!.summary as { categories: Record<string, { status: string; execution?: string }> })
    .categories.operational.execution = "not-selected";
  const report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "current-image-operational-and-outage")?.status, "BLOCKED");
  assert.equal(report.gates.find(item => item.id === "full-current-image-nfr-categories")?.status, "BLOCKED");
  assert.equal(report.verdict, "INCOMPLETE");
});

test("no-payment reporting finalization requires canonical run identity and hashed final coverage", () => {
  const input = base();
  const report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "no-payment-report-finalization")?.status, "PASS");
  input.noPaymentReport!.coverage = { schema: "phase10-sanitized-coverage-v2", runId: "wrong", provisional: true };
  const invalid = reconcilePhase10LocalFollowup(input);
  assert.equal(invalid.gates.find(item => item.id === "no-payment-report-finalization")?.status, "BLOCKED");
});

test("explicit failures remain FAIL across current evidence gates", () => {
  const cases: Array<{ gateId: string; mutate: (input: LocalFollowupInput) => void }> = [
    { gateId: "current-foundation-tests", mutate: input => { input.current.foundation = { status: "failed", results: [{ status: "failed", exitCode: 1 }] }; } },
    { gateId: "current-functions-replay", mutate: input => { input.current.functions = { status: "failed" }; } },
    { gateId: "current-image-operational-and-outage", mutate: input => {
      (input.current.operational!.summary as { categories: Record<string, { status: string }> }).categories.operational.status = "failed";
    } },
    { gateId: "current-image-rollback-and-restore", mutate: input => { input.current.rollback = { status: "failed", currentImageRestored: false }; } },
    { gateId: "full-current-image-nfr-categories", mutate: input => {
      (input.current.nfr as { categories: Record<string, { status: string }> }).categories.functional.status = "failed";
    } },
    { gateId: "historical-e2e-payment-and-restoration", mutate: input => {
      (input.e2e.packet as { status: string }).status = "failed";
      input.e2e.completionStatus = "failed";
    } }
  ];
  for (const testCase of cases) {
    const input = base();
    testCase.mutate(input);
    const report = reconcilePhase10LocalFollowup(input);
    assert.equal(report.gates.find(item => item.id === testCase.gateId)?.status, "FAIL", testCase.gateId);
    assert.equal(report.verdict, "FAIL", testCase.gateId);
  }
});

test("HTML output escapes evidence-controlled values and shows incomplete scope", () => {
  const report = reconcilePhase10LocalFollowup(base());
  const html = renderPhase10LocalFollowupHtml(report, new Map([["source-report", "../../source.json?x=1&y=2"]]));
  assert.match(html, /Verdict: INCOMPLETE/);
  assert.match(html, /href="\.\.\/\.\.\/source\.json\?x=1&amp;y=2"/);
  assert.doesNotMatch(html, /<script>/i);
  assert.match(html, /matching image IDs do not imply matching source revisions/i);
});

test("separate historical persistence without candidate-bound images is not promoted to PASS", () => {
  const input = base();
  const steps = (input.e2e.packet as { steps: { name: string; status: string }[] }).steps;
  steps.find(step => step.name === "persistence")!.status = "not-run";
  const persistence = input.current.persistence as NonNullable<LocalFollowupInput["current"]["persistence"]>;
  (persistence.imageBefore as ReturnType<typeof imageManifest>).candidate.worktreeContentSha256 = "b".repeat(64);
  (persistence.imageAfter as ReturnType<typeof imageManifest>).candidate.worktreeContentSha256 = "b".repeat(64);
  const report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "historical-e2e-persistence")?.status, "NOT-RUN");
  assert.equal(report.gates.find(item => item.id === "current-image-persistence")?.status, "BLOCKED");
  assert.equal(report.gates.find(item => item.id === "supplemental-persistence-outcome")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "persistence-source-image-binding")?.status, "BLOCKED");
});

test("a recorded historical persistence failure remains FAIL even with a newer persistence pass", () => {
  const input = base();
  const steps = (input.e2e.packet as { steps: { name: string; status: string }[] }).steps;
  steps.find(step => step.name === "persistence")!.status = "failed";
  const report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "historical-e2e-persistence")?.status, "FAIL");
});

test("dirty tooling-only payment reuse requires content hash and unchanged provider configuration", () => {
  const input = base();
  const manifest = input.current.imageManifest as ReturnType<typeof imageManifest>;
  manifest.candidate.changedPaths = ["tools/Phase10.NfrProbe/FunctionsAcceptance.cs"];
  input.current.sourceIdentity!.changedPaths = [...manifest.candidate.changedPaths];
  let report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "PASS");
  manifest.candidate.changedPaths = ["memories/repo/active-work.md"];
  input.current.sourceIdentity!.changedPaths = [...manifest.candidate.changedPaths];
  report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "PASS");
  manifest.candidate.changedPaths = ["memories/repo/unreviewed-instructions.md"];
  input.current.sourceIdentity!.changedPaths = [...manifest.candidate.changedPaths];
  report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "BLOCKED");
  manifest.candidate.changedPaths = ["XYDataLabs.OrderProcessingSystem.API/Payments/PaymentController.cs"];
  input.current.sourceIdentity!.changedPaths = [...manifest.candidate.changedPaths];
  report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "BLOCKED");

  const missingIdentity = base();
  const missingIdentityManifest = missingIdentity.current.imageManifest as ReturnType<typeof imageManifest>;
  missingIdentityManifest.candidate.worktreeContentSha256 = null;
  report = reconcilePhase10LocalFollowup(missingIdentity);
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "BLOCKED");
  assert.equal(report.verdict, "INCOMPLETE");
});

test("payment compatibility is blocked when the live checkout differs from the image manifest identity", () => {
  const input = base();
  input.current.sourceIdentity!.worktreeContentSha256 = "e".repeat(64);
  const report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "current-checkout-image-candidate-identity")?.status, "BLOCKED");
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "BLOCKED");
  assert.equal(report.currentSourceIdentity?.worktreeContentSha256, "e".repeat(64));
});

test("clean image evidence accepts only a tooling-only checkout overlay", () => {
  const input = base();
  for (const value of [input.e2e.imageBefore, input.e2e.imageAfter, input.current.imageManifest]) {
    const manifest = value as ReturnType<typeof imageManifest>;
    manifest.candidate.worktree = "clean";
    manifest.candidate.dirtyStatusSha256 = null;
    manifest.candidate.worktreeContentSha256 = null;
    manifest.candidate.changedPaths = [];
  }
  input.current.sourceIdentity = { commit: e2eCommit, worktree: "dirty", dirtyStatusSha256: "c".repeat(64),
    worktreeContentSha256: "d".repeat(64), changedPaths: ["automation/src/report/phase10-images.ts"] };
  let report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "current-checkout-image-candidate-identity")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "PASS");

  input.current.sourceIdentity.changedPaths = ["XYDataLabs.OrderProcessingSystem.API/Payments/PaymentController.cs"];
  report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "current-checkout-image-candidate-identity")?.status, "BLOCKED");
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "BLOCKED");
});

test("clean image evidence remains compatible with a committed tooling-only descendant", () => {
  const input = base();
  for (const value of [input.e2e.imageBefore, input.e2e.imageAfter, input.current.imageManifest]) {
    const manifest = value as ReturnType<typeof imageManifest>;
    manifest.candidate.worktree = "clean";
    manifest.candidate.dirtyStatusSha256 = null;
    manifest.candidate.worktreeContentSha256 = null;
    manifest.candidate.changedPaths = [];
  }
  const descendant = "b".repeat(40);
  const changedPaths = ["automation/src/report/phase10-images.ts", "scripts/phase10-docker-image-evidence.ps1"];
  input.current.sourceIdentity = { commit: descendant, worktree: "clean", dirtyStatusSha256: null,
    worktreeContentSha256: null, changedPaths: [], committedSnapshot: {
      baseCommit: e2eCommit, commit: descendant, worktreeContentSha256: "d".repeat(64), changedPaths
    } };
  let report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "current-checkout-image-candidate-identity")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "PASS");

  input.current.sourceIdentity.committedSnapshot!.changedPaths = ["XYDataLabs.OrderProcessingSystem.API/Payments/PaymentController.cs"];
  report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "current-checkout-image-candidate-identity")?.status, "BLOCKED");
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "BLOCKED");
});

test("legacy clean image manifests normalize null changedPaths but dirty manifests reject it", () => {
  const clean = imageManifest("clean-run", e2eCommit, "clean", "after") as ReturnType<typeof imageManifest>;
  clean.candidate.changedPaths = null as unknown as string[];
  const cleanResult = validatePhase10ImageManifest(clean, "clean-run", "after");
  assert.equal(cleanResult.status, "PASS");
  if (cleanResult.status === "PASS") assert.deepEqual(cleanResult.manifest.candidate.changedPaths, []);

  const dirty = imageManifest("dirty-run", e2eCommit, "dirty", "after") as ReturnType<typeof imageManifest>;
  dirty.candidate.changedPaths = null as unknown as string[];
  assert.equal(validatePhase10ImageManifest(dirty, "dirty-run", "after").status, "BLOCKED");
});

test("committed source content equivalence allows tooling-only payment evidence reuse without claiming a clean run", () => {
  const input = base();
  const changedPaths = ["scripts/report-tool.ps1"];
  for (const candidateImage of [input.e2e.imageBefore, input.e2e.imageAfter, input.current.imageManifest]) {
    const candidate = (candidateImage as ReturnType<typeof imageManifest>).candidate;
    candidate.worktree = "dirty";
    candidate.dirtyStatusSha256 = "c".repeat(64);
    candidate.worktreeContentSha256 = "d".repeat(64);
    candidate.changedPaths = [...changedPaths];
  }
  const provenance = (input.e2e.summary as { gitProvenance: { start: Record<string, unknown>; finish: Record<string, unknown> } }).gitProvenance;
  provenance.start.worktree = "dirty";
  provenance.finish.worktree = "dirty";
  input.current.sourceIdentity = {
    commit: "b".repeat(40), worktree: "dirty", dirtyStatusSha256: "e".repeat(64),
    worktreeContentSha256: "f".repeat(64), changedPaths: ["memories/repo/active-work.md"],
    committedSnapshot: { baseCommit: e2eCommit, commit: "b".repeat(40), worktreeContentSha256: "d".repeat(64), changedPaths }
  };

  let report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "current-checkout-image-candidate-identity")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "PASS");
  assert.equal(report.gates.find(item => item.id === "clean-single-source-candidate")?.status, "BLOCKED");

  input.current.sourceIdentity.committedSnapshot!.worktreeContentSha256 = "9".repeat(64);
  report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "current-checkout-image-candidate-identity")?.status, "BLOCKED");
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "BLOCKED");
});

test("worktree identity includes current tracked and untracked contents", () => {
  const root = mkdtempSync(join(tmpdir(), "phase10-worktree-identity-"));
  try {
    execFileSync("git", ["init", "-q"], { cwd: root });
    execFileSync("git", ["config", "user.name", "Phase10 Test"], { cwd: root });
    execFileSync("git", ["config", "user.email", "phase10-test@example.invalid"], { cwd: root });
    writeFileSync(join(root, "tracked.txt"), "baseline\n");
    execFileSync("git", ["add", "tracked.txt"], { cwd: root });
    execFileSync("git", ["commit", "-q", "-m", "baseline"], { cwd: root });

    const clean = capturePhase10WorktreeIdentity(root);
    assert.equal(clean.worktree, "clean");
    assert.equal(clean.worktreeContentSha256, null);

    writeFileSync(join(root, "tracked.txt"), "changed\n");
    const trackedDirty = capturePhase10WorktreeIdentity(root);
    assert.equal(trackedDirty.worktree, "dirty");
    assert.equal(trackedDirty.changedPaths.join(","), "tracked.txt");
    assert.match(trackedDirty.worktreeContentSha256 ?? "", /^[a-f0-9]{64}$/);

    writeFileSync(join(root, "untracked.txt"), "new evidence\n");
    const withUntracked = capturePhase10WorktreeIdentity(root);
    assert.equal(withUntracked.changedPaths.join(","), "tracked.txt,untracked.txt");
    assert.notEqual(withUntracked.worktreeContentSha256, trackedDirty.worktreeContentSha256);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("committed source snapshot reproduces the exact pre-commit dirty content identity", () => {
  const root = mkdtempSync(join(tmpdir(), "phase10-committed-snapshot-"));
  try {
    execFileSync("git", ["init", "-q"], { cwd: root });
    execFileSync("git", ["config", "core.autocrlf", "true"], { cwd: root });
    execFileSync("git", ["config", "user.name", "Phase10 Test"], { cwd: root });
    execFileSync("git", ["config", "user.email", "phase10-test@example.invalid"], { cwd: root });
    writeFileSync(join(root, "tracked.txt"), "baseline\r\n");
    execFileSync("git", ["add", "tracked.txt"], { cwd: root });
    execFileSync("git", ["commit", "-q", "-m", "baseline"], { cwd: root });
    const baseCommit = execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();

    writeFileSync(join(root, "tracked.txt"), "tested content\r\n");
    writeFileSync(join(root, "new-file.txt"), "tested untracked content\r\n");
    const testedIdentity = capturePhase10WorktreeIdentity(root);
    assert.deepEqual(testedIdentity.changedPaths, ["new-file.txt", "tracked.txt"]);

    execFileSync("git", ["add", "tracked.txt", "new-file.txt"], { cwd: root });
    execFileSync("git", ["commit", "-q", "-m", "pin tested snapshot"], { cwd: root });
    const committedIdentity = capturePhase10CommittedSnapshotIdentity(root, baseCommit);

    assert.equal(committedIdentity.commit, execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim());
    assert.deepEqual(committedIdentity.changedPaths, testedIdentity.changedPaths);
    assert.equal(committedIdentity.worktreeContentSha256, testedIdentity.worktreeContentSha256);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
