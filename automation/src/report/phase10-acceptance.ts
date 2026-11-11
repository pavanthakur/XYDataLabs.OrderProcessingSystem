import { DOCKER_PACKET_STEPS } from "./phase10-report.js";
import { phase10ImageSetsMatch, validatePhase10ImageManifest } from "./phase10-images.js";
import type { Phase10ImageManifest } from "./phase10-images.js";

export const NFR_REQUIRED_CATEGORIES = ["functional", "performance", "tenant", "payments", "operational", "recovery", "security"] as const;
export const P95_LIMIT_SECONDS = 30;
export const REPLAY_VISIBILITY_LIMIT_SECONDS = 60;
export const RECOVERY_LIMIT_SECONDS = 1800;
export const BACKEND_COVERAGE_PROJECTS = 5;

export type GateStatus = "PASS" | "FAIL" | "BLOCKED" | "DEFERRED" | "NOT-RUN";
export type Verdict = "PASS" | "INCOMPLETE" | "FAIL";
export interface Gate { name: string; status: GateStatus; detail: string }
export interface AcceptanceInput {
  expectedCommit: string;
  e2e: { completion: "COMPLETE" | "INCOMPLETE"; completionStatus?: string; packet: unknown; summary: unknown;
    coverage: unknown; reportIssuesClean: boolean; imageBefore: unknown; imageAfter: unknown };
  nfr: { summary: unknown; outageDrill: unknown; replayProof: unknown; performanceProbe: unknown;
    imageBefore: unknown; imageAfter: unknown; imageRunId?: string };
}
export interface AcceptanceResult {
  schema: "phase10-local-acceptance-v1";
  scope: "non-azure-local";
  verdict: Verdict;
  expectedCommit: string;
  gates: Gate[];
  notCertified: string[];
}

function rec(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value)) : undefined;
}
function num(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}
function pick(source: Record<string, unknown> | undefined, name: string): unknown {
  if (!source) return undefined;
  const key = Object.keys(source).find(item => item.toLowerCase() === name.toLowerCase());
  return key === undefined ? undefined : source[key];
}
function gate(name: string, ok: boolean, detail: string, failure = false): Gate {
  return { name, status: ok ? "PASS" : failure ? "FAIL" : "BLOCKED", detail };
}
function cleanCommit(snapshot: unknown, expected: string): boolean {
  const value = rec(snapshot);
  return value?.commit === expected && value?.worktree === "clean";
}

function imagePair(valueBefore: unknown, valueAfter: unknown, runId: string | undefined, expectedCommit: string):
  { status: "PASS" | "FAIL" | "BLOCKED"; before?: Phase10ImageManifest; after?: Phase10ImageManifest; detail: string } {
  const before = validatePhase10ImageManifest(valueBefore, runId, "before");
  const after = validatePhase10ImageManifest(valueAfter, runId, "after");
  if (before.status !== "PASS" || after.status !== "PASS") return { status: "BLOCKED", detail: "One or both bound image manifests are missing or invalid." };
  if (before.manifest.candidate.commit !== expectedCommit || after.manifest.candidate.commit !== expectedCommit ||
      before.manifest.candidate.worktree !== "clean" || after.manifest.candidate.worktree !== "clean") {
    return { status: "BLOCKED", before: before.manifest, after: after.manifest, detail: "Image provenance is not the expected clean candidate." };
  }
  if (!phase10ImageSetsMatch(before.manifest, after.manifest)) {
    return { status: "FAIL", before: before.manifest, after: after.manifest, detail: "Service image identity changed during the run." };
  }
    return { status: "PASS", before: before.manifest, after: after.manifest, detail: "All 13 service image identities remained unchanged." };
}

export function reconcilePhase10Acceptance(input: AcceptanceInput): AcceptanceResult {
  const gates: Gate[] = [];
  const { e2e, nfr } = input;
  const packet = rec(e2e.packet);
  const summary = rec(e2e.summary);
  const e2eRunId = typeof summary?.runId === "string" ? summary.runId : undefined;
  const e2eImages = imagePair(e2e.imageBefore, e2e.imageAfter, e2eRunId, input.expectedCommit);
  gates.push({ name: "e2e-image-identities", status: e2eImages.status, detail: e2eImages.detail });

  gates.push(gate("e2e-sealed-completion", e2e.completion === "COMPLETE" && e2e.completionStatus === "passed",
    `completion=${e2e.completion}; status=${e2e.completionStatus ?? "UNKNOWN"}`, e2e.completionStatus === "failed"));

  const provenance = rec(summary?.gitProvenance);
  gates.push(gate("e2e-single-clean-candidate",
    cleanCommit(provenance?.start, input.expectedCommit) && cleanCommit(provenance?.finish, input.expectedCommit),
    "E2E start and finish must both record the expected commit with a clean worktree."));

  const steps = Array.isArray(packet?.steps) ? packet.steps.map(rec).filter((item): item is Record<string, unknown> => !!item) : [];
  const deferrals = Array.isArray(packet?.deferrals) ? packet.deferrals.map(String) : [];
  for (const name of DOCKER_PACKET_STEPS) {
    const matches = steps.filter(step => step.name === name);
    const status = matches.length === 1 ? String(matches[0].status) : "missing-or-duplicate";
    if (name === "order-continuation") {
      gates.push(status === "passed" ? { name: `e2e-${name}`, status: "PASS", detail: "passed" }
        : deferrals.includes("DW-023") ? { name: `e2e-${name}`, status: "DEFERRED", detail: `status=${status}; DW-023 deferral recorded; not a PASS` }
          : { name: `e2e-${name}`, status: "BLOCKED", detail: `status=${status}; no DW-023 deferral recorded` });
      continue;
    }
    gates.push(gate(`e2e-${name}`, status === "passed", `status=${status}`, status === "failed"));
  }

  const restoration = rec(packet?.restoration);
  gates.push(gate("e2e-restoration-and-storage",
    restoration?.allRestored === true && restoration?.fixtureLockPresent === false && packet?.storageExitCode === 0 && summary?.storageExitCode === 0,
    "Provider fixtures restored, no fixture lock, storage exit 0.", restoration?.allRestored === false));

  const coverage = rec(e2e.coverage);
  const backend = Array.isArray(coverage?.backend) ? coverage.backend.map(rec) : [];
  const measured = (value: unknown) => rec(value)?.state === "MEASURED";
  gates.push(gate("l5r-report-reconciled",
    e2e.reportIssuesClean && backend.length === BACKEND_COVERAGE_PROJECTS && backend.every(measured) &&
      measured(coverage?.frontend) && measured(coverage?.integration),
    "Sealed report lists no reconciliation issues and measured backend, frontend and integration coverage."));

  const nfrSummary = rec(nfr.summary);
  const nfrRunDirectory = typeof nfrSummary?.runDir === "string" ? nfrSummary.runDir.replace(/[\\/]+$/, "").split(/[\\/]/).at(-1) : undefined;
  const nfrImages = imagePair(nfr.imageBefore, nfr.imageAfter, nfr.imageRunId ?? nfrRunDirectory, input.expectedCommit);
  gates.push({ name: "nfr-image-identities", status: nfrImages.status, detail: nfrImages.detail });
  const crossImageMatch = e2eImages.status === "PASS" && nfrImages.status === "PASS" &&
    !!e2eImages.before && !!nfrImages.before && phase10ImageSetsMatch(e2eImages.before, nfrImages.before);
  const crossMismatch = e2eImages.status === "PASS" && nfrImages.status === "PASS" && !crossImageMatch;
  gates.push({ name: "e2e-nfr-image-consistency", status: crossImageMatch ? "PASS" : crossMismatch ? "FAIL" : "BLOCKED",
    detail: crossImageMatch ? "E2E and NFR used the same 13 local service image IDs." : crossMismatch
      ? "E2E and NFR used different service image identities despite matching source revision." : "Cannot compare E2E and NFR image identities." });
  const categories = rec(nfrSummary?.categories);
  const categoryStatuses = NFR_REQUIRED_CATEGORIES.map(name => `${name}=${String(rec(categories?.[name])?.status ?? "missing")}`);
  gates.push(gate("nfr-single-clean-candidate",
    nfrSummary?.commitSha === input.expectedCommit && nfrSummary?.worktreeAtStart === "clean" && nfrSummary?.worktreeAtFinish === "clean" &&
      nfrSummary?.commitShaAtFinish === input.expectedCommit,
    "NFR run must record the expected commit and a clean worktree at start and finish."));
  gates.push(gate("nfr-categories",
    nfrSummary?.status === "passed" && categoryStatuses.every(item => item.endsWith("=passed")),
    categoryStatuses.join("; "), nfrSummary?.status === "failed"));

  const probe = rec(nfr.performanceProbe);
  const expected = num(pick(probe, "ExpectedMessages"));
  const counts = ["InventoryInboxCount", "NotificationsInboxCount", "InventoryEffectCount", "NotificationEffectCount"].map(name => num(pick(probe, name)));
  const p95 = num(pick(probe, "P95Seconds"));
  gates.push(gate("nfr-100-message-burst",
    pick(probe, "Status") === "passed" && expected !== undefined && expected >= 100 && counts.every(count => count === expected) &&
      p95 !== undefined && p95 <= P95_LIMIT_SECONDS,
    `expected=${expected ?? "?"}; counts=${counts.join("/")}; p95=${p95 ?? "?"}s (limit ${P95_LIMIT_SECONDS}s)`));

  const replay = rec(nfr.replayProof);
  const replaySeconds = num(replay?.replayVisibilitySeconds);
  gates.push(gate("nfr-approved-replay-visibility",
    replay?.status === "passed" && replaySeconds !== undefined && replaySeconds <= REPLAY_VISIBILITY_LIMIT_SECONDS,
    `replayVisibilitySeconds=${replaySeconds ?? "?"} (limit ${REPLAY_VISIBILITY_LIMIT_SECONDS}s)`));

  const drill = rec(nfr.outageDrill);
  const recovery = num(drill?.backlogRecoverySeconds);
  gates.push(gate("nfr-consumer-outage-recovery",
    drill?.status === "passed" && drill?.lostMessages === 0 && drill?.duplicateEffects === 0 && recovery !== undefined &&
      recovery <= RECOVERY_LIMIT_SECONDS,
    `lost=${String(drill?.lostMessages ?? "?")}; duplicates=${String(drill?.duplicateEffects ?? "?")}; recoverySeconds=${recovery ?? "?"} (limit ${RECOVERY_LIMIT_SECONDS}s)`));

  const recoveryChecks = Array.isArray(rec(categories?.recovery)?.checks)
    ? (rec(categories?.recovery)?.checks as unknown[]).map(rec) : [];
  const passedCheck = (name: string) => recoveryChecks.some(check => check?.name === name && check?.status === "passed");
  gates.push(gate("nfr-rollback-executed-and-restored",
    passedCheck("Rollback inventory to previous image") && passedCheck("Restore inventory current image"),
    "Previous-image rollback and current-image restore both executed. Scope: single-service local image swap, not an ACA revision rollback."));

  gates.push({ name: "deferred-DW-023-order-continuation", status: "DEFERRED", detail: "Deferred to Phase 11; never counted as PASS." });
  gates.push({ name: "deferred-DW-024-provider-capability", status: "DEFERRED", detail: "Deferred to Phase 11; never counted as PASS." });
  gates.push({ name: "l6-ci-parity-and-azure", status: "NOT-RUN", detail: "Excluded from this scope; required before Phase 10 can be called complete." });

  const required = gates.filter(item => item.status !== "DEFERRED" && item.name !== "l6-ci-parity-and-azure");
  const verdict: Verdict = required.some(item => item.status === "FAIL") ? "FAIL"
    : required.every(item => item.status === "PASS") ? "PASS" : "INCOMPLETE";
  return { schema: "phase10-local-acceptance-v1", scope: "non-azure-local", verdict, expectedCommit: input.expectedCommit, gates,
    notCertified: ["fulfillment", "monetary installments", "unresolved-payment recovery", "Azure deployment", "L6 CI parity", "ACA revision rollback"] };
}
