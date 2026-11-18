import assert from "node:assert/strict";
import { test } from "node:test";
import { PHASE10_DOCKER_SERVICES } from "./phase10-images.js";
import { DOCKER_PACKET_STEPS } from "./phase10-report.js";
import { reconcilePhase10LocalFollowup, renderPhase10LocalFollowupHtml } from "./phase10-local-followup.js";
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
    summary: { runId: "phase10-docker-http-20261115-194923198", gitProvenance: { start: { commit: e2eCommit, worktree: "clean" } } },
    packet: { status: "passed", deferrals: ["DW-023"], restoration: { status: "passed", allRestored: true, fixtureLockPresent: false },
      steps: DOCKER_PACKET_STEPS.map(name => ({ name, status: name === "order-continuation" ? "deferred" : "passed" })) },
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
  input.current.persistence!.imageBefore = undefined;
  const report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "historical-e2e-persistence")?.status, "NOT-RUN");
  assert.equal(report.gates.find(item => item.id === "current-image-persistence")?.status, "BLOCKED");
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
  let report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "PASS");
  manifest.candidate.changedPaths = ["XYDataLabs.OrderProcessingSystem.API/Payments/PaymentController.cs"];
  report = reconcilePhase10LocalFollowup(input);
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "BLOCKED");

  const missingIdentity = base();
  const missingIdentityManifest = missingIdentity.current.imageManifest as ReturnType<typeof imageManifest>;
  missingIdentityManifest.candidate.worktreeContentSha256 = null;
  report = reconcilePhase10LocalFollowup(missingIdentity);
  assert.equal(report.gates.find(item => item.id === "historical-e2e-payment-compatibility")?.status, "BLOCKED");
  assert.equal(report.verdict, "INCOMPLETE");
});
