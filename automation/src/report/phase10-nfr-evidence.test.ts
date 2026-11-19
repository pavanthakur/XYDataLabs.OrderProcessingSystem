import assert from "node:assert/strict";
import { test } from "node:test";
import { normalizePhase10NfrEvidence } from "./phase10-nfr-evidence.js";

const commit = "a".repeat(40);
const candidate = { commit, worktree: "clean" };
const services = ["azurite", "functions", "gateway", "inventory", "keycloak-local", "notifications", "orders", "payments", "redis", "servicebus-emulator", "servicebus-sql", "sql-server", "ui"];
const images = services.map((service, index) => ({ project: "xy-phase10", service, imageId: `sha256:${String(index + 1).padStart(64, "0")}` }));
const image = (capturePoint: string) => ({ schema: "phase10-docker-image-identities-v1", runId: "phase10-local-nfr-run", capturePoint, candidate, images });

function fixture() {
  const operationalChecks = ["Compose controls and running services", "Build NFR probe for operational-only lane",
    "100 message durable consumer burst", "Consumer outage backlog recovery drill"].map(name => ({ name, status: "passed" }));
  const recoveryChecks = ["Retained image digest evidence", "Rollback inventory to previous image", "Restore inventory current image"]
    .map(name => ({ name, status: "passed" }));
  return {
    summary: {
      status: "incomplete", commitSha: commit, commitShaAtFinish: commit, worktreeAtStart: "clean", worktreeAtFinish: "clean",
      selection: { mode: "operational-only", selectedCategories: ["operational", "recovery"],
        notSelectedCategories: ["functional", "performance", "tenant", "payments", "security"], dynamicPaymentMatrix: "not-selected" },
      paymentSettingsIntegrity: "not-selected",
      categories: {
        operational: { status: "passed", execution: "selected", checks: operationalChecks },
        recovery: { status: "passed", execution: "selected", checks: recoveryChecks }
      }
    },
    operationalSummary: { status: "passed", execution: "selected", checks: operationalChecks },
    recoverySummary: { status: "passed", execution: "selected", checks: recoveryChecks },
    recoveryDrill: { runId: "drill-1", status: "passed", messageCount: 100, backlogRecoverySeconds: 32.259,
      inventoryInbox: 100, notificationsInbox: 100, inventoryEffects: 100, notificationEffects: 100, p95Seconds: 9.87,
      lostMessages: 0, duplicateEffects: 0, probeStopped: true, environmentRestored: true,
      consumersRestoredExitCode: 0, consumersReadyAfterRestore: true, restorationStatus: "passed" },
    recoveryProbe: { RunId: "drill-1", Status: "passed", ExpectedMessages: 100, InventoryInboxCount: 100,
      NotificationsInboxCount: 100, InventoryEffectCount: 100, NotificationEffectCount: 100, P95Seconds: 9.87, CompletionSeconds: 33.657 },
    rollback: { status: "passed", sourceCommit: "b".repeat(40), comparedCandidateCommit: commit,
      previousImage: "registry/inventory:previous", previousImageId: `sha256:${"f".repeat(64)}`,
      currentImageId: images.find(item => item.service === "inventory")!.imageId,
      runningImageIdBefore: images.find(item => item.service === "inventory")!.imageId,
      relevantSourceChangesSinceBaseline: [], databaseRollback: false, rollbackObserved: true, currentImageRestored: true },
    burstLog: "Published 100 messages.\nObserved test: inbox=100/100, effects=100/100, p95=1.993s",
    nfrImageBefore: image("before"), nfrImageAfter: image("after"),
    parentGitProvenance: { start: { ...candidate, contentIdentity: "c".repeat(64) }, finish: { ...candidate, contentIdentity: "c".repeat(64) } },
    parentImageBefore: image("before"), parentImageAfter: image("after"), evidenceSha256: "d".repeat(64)
  };
}

test("operational/recovery NFR evidence is partial-profile PASS only when metrics and rollback reconcile", () => {
  const result = normalizePhase10NfrEvidence(fixture());
  assert.equal(result.overallStatus, "PARTIAL");
  assert.equal(result.selectedScopeStatus, "PASS");
  assert.equal(result.rollbackStatus, "PASS");
  assert.equal(result.burst.p95Seconds, 1.993);
  assert.equal(result.recovery.seconds, 32.259);
  assert.equal(result.recovery.lost, 0);
  assert.equal(result.replayStatus, "NOT-RUN");
  assert.deepEqual(result.issues, []);
});

test("NFR metrics, candidate mismatch, incomplete rollback and omitted required files fail closed", () => {
  const badMetrics = fixture();
  badMetrics.recoveryDrill.duplicateEffects = 1;
  assert.equal(normalizePhase10NfrEvidence(badMetrics).selectedScopeStatus, "BLOCKED");

  const wrongCandidate = fixture();
  wrongCandidate.summary.commitShaAtFinish = "e".repeat(40);
  assert.ok(normalizePhase10NfrEvidence(wrongCandidate).issues.some(issue => issue.includes("candidate")));

  const badRollback = fixture();
  badRollback.rollback.currentImageRestored = false;
  const result = normalizePhase10NfrEvidence(badRollback);
  assert.equal(result.rollbackStatus, "BLOCKED");
  assert.equal(result.selectedScopeStatus, "BLOCKED");

  const noBurst = fixture();
  noBurst.burstLog = undefined as unknown as string;
  assert.ok(normalizePhase10NfrEvidence(noBurst).issues.some(issue => issue.includes("burst")));

  const omittedCheck = fixture();
  omittedCheck.summary.categories.operational.checks.pop();
  omittedCheck.operationalSummary.checks.pop();
  assert.ok(normalizePhase10NfrEvidence(omittedCheck).issues.some(issue => issue.includes("summary does not reconcile")));
});

test("absent NFR evidence is NOT-RUN, not a pass", () => {
  assert.equal(normalizePhase10NfrEvidence().overallStatus, "NOT-RUN");
});
