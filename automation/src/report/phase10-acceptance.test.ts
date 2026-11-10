import assert from "node:assert/strict";
import { test } from "node:test";
import { DOCKER_PACKET_STEPS } from "./phase10-report.js";
import { NFR_REQUIRED_CATEGORIES, reconcilePhase10Acceptance } from "./phase10-acceptance.js";
import type { AcceptanceInput } from "./phase10-acceptance.js";

const commit = "a".repeat(40);
const snapshot = { commit, worktree: "clean" };
const passing = (): AcceptanceInput => ({
  expectedCommit: commit,
  e2e: {
    completion: "COMPLETE", completionStatus: "passed", reportIssuesClean: true,
    summary: { gitProvenance: { start: snapshot, finish: snapshot }, storageExitCode: 0 },
    packet: {
      storageExitCode: 0, deferrals: ["DW-023", "DW-024"],
      restoration: { allRestored: true, fixtureLockPresent: false },
      steps: DOCKER_PACKET_STEPS.map(name => ({ name, status: name === "order-continuation" ? "blocked" : "passed" }))
    },
    coverage: {
      backend: Array.from({ length: 5 }, () => ({ state: "MEASURED" })),
      frontend: { state: "MEASURED" }, integration: { state: "MEASURED" }
    }
  },
  nfr: {
    summary: {
      status: "passed", commitSha: commit, commitShaAtFinish: commit, worktreeAtStart: "clean", worktreeAtFinish: "clean",
      categories: Object.fromEntries(NFR_REQUIRED_CATEGORIES.map(name => [name, {
        status: "passed",
        checks: name === "recovery" ? [{ name: "Rollback inventory to previous image", status: "passed" },
          { name: "Restore inventory current image", status: "passed" }] : []
      }]))
    },
    performanceProbe: { Status: "passed", ExpectedMessages: 100, InventoryInboxCount: 100, NotificationsInboxCount: 100,
      InventoryEffectCount: 100, NotificationEffectCount: 100, P95Seconds: 1.9 },
    replayProof: { status: "passed", replayVisibilitySeconds: 4.2 },
    outageDrill: { status: "passed", lostMessages: 0, duplicateEffects: 0, backlogRecoverySeconds: 35 }
  }
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
