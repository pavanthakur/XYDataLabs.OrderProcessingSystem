import assert from "node:assert/strict";
import { test } from "node:test";
import { PHASE10_DOCKER_SERVICES } from "./phase10-images.js";
import { DOCKER_PACKET_STEPS } from "./phase10-report.js";
import { reconcilePhase10LocalFollowup, renderPhase10LocalFollowupHtml } from "./phase10-local-followup.js";
import type { LocalFollowupInput } from "./phase10-local-followup.js";

const e2eCommit = "a".repeat(40);
const currentCommit = "b".repeat(40);
const imageManifest = (runId: string, commit: string, worktree: "clean" | "dirty", capturePoint: "before" | "after") => ({
  schema: "phase10-docker-image-identities-v1", runId, capturePoint,
  candidate: { commit, worktree, dirtyStatusSha256: worktree === "dirty" ? "c".repeat(64) : null }, buildLogsSha256: {},
  images: PHASE10_DOCKER_SERVICES.map((service, index) => ({ project: "xy-phase10", service,
    containerId: (index + 1).toString(16).padStart(12, "0"), imageReference: `local/${service}:test`,
    imageId: `sha256:${(index + 1).toString(16).padStart(64, "0")}`, repositoryDigests: [] }))
});

const base = (): LocalFollowupInput => ({
  e2e: {
    completion: "COMPLETE", completionStatus: "passed",
    summary: { runId: "phase10-docker-http-20261115-194923198", gitProvenance: { start: { commit: e2eCommit, worktree: "clean" } } },
    packet: { status: "passed", deferrals: ["DW-023"], restoration: { status: "passed", allRestored: true, fixtureLockPresent: false },
      steps: DOCKER_PACKET_STEPS.map(name => ({ name, status: name === "order-continuation" ? "deferred" : "passed" })) },
    imageAfter: imageManifest("phase10-docker-http-20261115-194923198", e2eCommit, "clean", "after")
  },
  current: {
    imageManifest: imageManifest("current-image-audit-p0", currentCommit, "dirty", "after"),
    foundation: { status: "passed", results: [{ status: "passed", exitCode: 0 }, { status: "passed", exitCode: 0 }] },
    functions: { status: "passed", approvalStatus: "processing-confirmed", approvalOutcome: "approved",
      approvalReconciliationRequired: false, intake: "passed", replay: "passed", downstreamEffects: "passed" },
    nfr: { status: "incomplete", categories: {
      functional: { status: "not-run" }, performance: { status: "not-run" }, tenant: { status: "not-run" },
      payments: { status: "not-run" }, security: { status: "not-run" }, operational: { status: "passed" }, recovery: { status: "passed" }
    } },
    burst: { Status: "passed", ExpectedMessages: 100, InventoryInboxCount: 100, NotificationsInboxCount: 100,
      InventoryEffectCount: 100, NotificationEffectCount: 100, P95Seconds: 3.9 },
    outage: { status: "passed", messageCount: 100, inventoryEffects: 100, notificationEffects: 100,
      inventoryInbox: 100, notificationsInbox: 100, lostMessages: 0, duplicateEffects: 0, p95Seconds: 8.6,
      backlogRecoverySeconds: 29, restorationStatus: "passed", environmentRestored: true },
    rollback: { status: "passed", rollbackObserved: true, currentImageRestored: true, databaseRollback: false,
      previousImageId: `sha256:${"d".repeat(64)}`, currentImageId: `sha256:${"e".repeat(64)}` }
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
  assert.equal(report.gates.find(item => item.id === "full-current-image-nfr-categories")?.status, "BLOCKED");
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

test("explicit failures remain FAIL across current evidence gates", () => {
  const cases: Array<{ gateId: string; mutate: (input: LocalFollowupInput) => void }> = [
    { gateId: "current-foundation-tests", mutate: input => { input.current.foundation = { status: "failed", results: [{ status: "failed", exitCode: 1 }] }; } },
    { gateId: "current-functions-replay", mutate: input => { input.current.functions = { status: "failed" }; } },
    { gateId: "current-image-operational-and-outage", mutate: input => {
      (input.current.nfr as { categories: Record<string, { status: string }> }).categories.operational.status = "failed";
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
