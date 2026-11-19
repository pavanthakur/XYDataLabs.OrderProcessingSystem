import { createHash } from "node:crypto";
import { PHASE10_DOCKER_SERVICES } from "./phase10-images.js";
import type { EvidenceStatus } from "./phase10-report.js";

type JsonRecord = Record<string, unknown>;
type NfrCategory = "operational" | "recovery";
const EXPECTED_NFR_CHECKS: Record<NfrCategory, readonly string[]> = {
  operational: ["Compose controls and running services", "Build NFR probe for operational-only lane",
    "100 message durable consumer burst", "Consumer outage backlog recovery drill"],
  recovery: ["Retained image digest evidence", "Rollback inventory to previous image", "Restore inventory current image"]
};

export interface Phase10NfrEvidence {
  overallStatus: EvidenceStatus;
  selectedScopeStatus: EvidenceStatus;
  commit: string | null;
  selectedCategories: NfrCategory[];
  notSelectedCategories: string[];
  replayStatus: EvidenceStatus;
  replaySeconds: number | null;
  burst: { messages: number | null; inbox: number | null; effects: number | null; p95Seconds: number | null };
  recovery: { messages: number | null; seconds: number | null; lost: number | null; duplicateEffects: number | null };
  rollbackStatus: EvidenceStatus;
  evidenceSha256: string | null;
  issues: string[];
}

function record(value: unknown): JsonRecord | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : undefined;
}

function list(value: unknown): unknown[] | undefined { return Array.isArray(value) ? value : undefined; }

function cleanCommit(value: unknown): value is string { return typeof value === "string" && /^[a-f0-9]{40}$/i.test(value); }

function imageMap(value: unknown): Map<string, string> | undefined {
  const manifest = record(value);
  const images = list(manifest?.images);
  if (manifest?.schema !== "phase10-docker-image-identities-v1" || !images || images.length !== PHASE10_DOCKER_SERVICES.length) return undefined;
  const output = new Map<string, string>();
  for (const raw of images) {
    const image = record(raw);
    if (image?.project !== "xy-phase10" || typeof image.service !== "string" ||
        typeof image.imageId !== "string" || !/^sha256:[a-f0-9]{64}$/i.test(image.imageId) || output.has(image.service)) return undefined;
    output.set(image.service, image.imageId.toLowerCase());
  }
  return output.size === PHASE10_DOCKER_SERVICES.length && PHASE10_DOCKER_SERVICES.every(service => output.has(service)) ? output : undefined;
}

function sameImages(left: Map<string, string> | undefined, right: Map<string, string> | undefined): boolean {
  return Boolean(left && right && left.size === right.size && [...left].every(([key, value]) => right.get(key) === value));
}

function categoryPass(summary: unknown, category: NfrCategory, checkSummary: unknown): boolean {
  const root = record(summary);
  const categories = record(root?.categories);
  const item = record(categories?.[category]);
  const checkRoot = record(checkSummary);
  const checks = list(item?.checks);
  const emitted = list(checkRoot?.checks);
  if (item?.status !== "passed" || item.execution !== "selected" || checkRoot?.status !== "passed" ||
      checkRoot.execution !== "selected" || !checks || !emitted || checks.length === 0 || checks.length !== emitted.length) return false;
  const keys = (items: unknown[]) => items.map(raw => {
    const check = record(raw);
    return typeof check?.name === "string" && check.status === "passed" ? check.name : "";
  }).sort();
  const summaryNames = keys(checks);
  const emittedNames = keys(emitted);
  return summaryNames.every(Boolean) && new Set(summaryNames).size === summaryNames.length &&
    JSON.stringify(summaryNames) === JSON.stringify(emittedNames) &&
    JSON.stringify(summaryNames) === JSON.stringify([...EXPECTED_NFR_CHECKS[category]].sort());
}

export function normalizePhase10NfrEvidence(input?: {
  summary: unknown;
  operationalSummary: unknown;
  recoverySummary: unknown;
  recoveryDrill: unknown;
  recoveryProbe: unknown;
  rollback: unknown;
  burstLog: string | undefined;
  nfrImageBefore: unknown;
  nfrImageAfter: unknown;
  parentGitProvenance: unknown;
  parentImageBefore: unknown;
  parentImageAfter: unknown;
  evidenceSha256: string | undefined;
}): Phase10NfrEvidence {
  if (!input) return { overallStatus: "NOT-RUN", selectedScopeStatus: "NOT-RUN", commit: null,
    selectedCategories: [], notSelectedCategories: [], replayStatus: "NOT-RUN", replaySeconds: null,
    burst: { messages: null, inbox: null, effects: null, p95Seconds: null },
    recovery: { messages: null, seconds: null, lost: null, duplicateEffects: null }, rollbackStatus: "NOT-RUN", evidenceSha256: null, issues: [] };

  const issues: string[] = [];
  const summary = record(input.summary);
  const selection = record(summary?.selection);
  const parent = record(input.parentGitProvenance);
  const parentStart = record(parent?.start);
  const parentFinish = record(parent?.finish);
  const commit = cleanCommit(summary?.commitSha) && summary.commitShaAtFinish === summary.commitSha ? summary.commitSha : null;
  if (summary?.status !== "incomplete" || !commit || summary.worktreeAtStart !== "clean" || summary.worktreeAtFinish !== "clean" ||
      parentStart?.worktree !== "clean" || parentFinish?.worktree !== "clean" || commit !== parentStart?.commit || commit !== parentFinish?.commit) {
    issues.push("NFR evidence is not bound to the same clean candidate as the Docker run.");
  }
  const selected = list(selection?.selectedCategories) ?? [];
  const notSelected = list(selection?.notSelectedCategories) ?? [];
  if (selection?.mode !== "operational-only" || JSON.stringify([...selected].sort()) !== JSON.stringify(["operational", "recovery"]) ||
      selection.dynamicPaymentMatrix !== "not-selected" || !notSelected.includes("functional") || !notSelected.includes("performance") ||
      !notSelected.includes("tenant") || !notSelected.includes("payments") || !notSelected.includes("security") ||
      summary?.paymentSettingsIntegrity !== "not-selected") {
    issues.push("NFR selection is missing, contradictory or does not state the unrun categories.");
  }
  if (!categoryPass(summary, "operational", input.operationalSummary) || !categoryPass(summary, "recovery", input.recoverySummary)) {
    issues.push("Operational or recovery summary does not reconcile with selected category checks.");
  }
  const burstText = input.burstLog ?? "";
  const burstMatches = [...burstText.matchAll(/Observed\s+[^\r\n]+:\s*inbox=(\d+)\/(\d+),\s*effects=(\d+)\/(\d+),\s*p95=([\d.]+)s/gi)];
  const burst = burstMatches.length ? burstMatches[burstMatches.length - 1] : undefined;
  const burstMessages = burst ? Number(burst[2]) : null;
  const burstInbox = burst ? Number(burst[1]) : null;
  const burstEffects = burst ? Number(burst[3]) : null;
  const burstP95 = burst ? Number(burst[5]) : null;
  if (burstInbox !== 100 || burstMessages !== 100 || burstEffects !== 100 || Number(burst?.[4]) !== 100 ||
      burstP95 === null || !Number.isFinite(burstP95) || burstP95 >= 30) {
    issues.push("100-message operational burst does not prove 100 inbox/effects and P95 below 30 seconds.");
  }
  const drill = record(input.recoveryDrill);
  const probe = record(input.recoveryProbe);
  const recoveryMessages = drill?.messageCount;
  const recoverySeconds = drill?.backlogRecoverySeconds;
  const lost = drill?.lostMessages;
  const duplicateEffects = drill?.duplicateEffects;
  if (drill?.status !== "passed" || probe?.Status !== "passed" || drill.runId !== probe.RunId || recoveryMessages !== 100 ||
      drill.inventoryInbox !== 100 || drill.notificationsInbox !== 100 || drill.inventoryEffects !== 100 || drill.notificationEffects !== 100 ||
      probe.ExpectedMessages !== 100 || probe.InventoryInboxCount !== 100 || probe.NotificationsInboxCount !== 100 ||
      probe.InventoryEffectCount !== 100 || probe.NotificationEffectCount !== 100 ||
      typeof probe.P95Seconds !== "number" || probe.P95Seconds >= 30 || typeof drill.p95Seconds !== "number" || drill.p95Seconds >= 30 ||
      typeof recoverySeconds !== "number" || recoverySeconds <= 0 || recoverySeconds > 1800 ||
      probe.CompletionSeconds !== undefined && typeof probe.CompletionSeconds === "number" && probe.CompletionSeconds > 1800 ||
      lost !== 0 || duplicateEffects !== 0 || drill.probeStopped !== true || drill.environmentRestored !== true ||
      drill.consumersRestoredExitCode !== 0 || drill.consumersReadyAfterRestore !== true || drill.restorationStatus !== "passed") {
    issues.push("Consumer-outage recovery does not prove bounded complete effects, zero loss/duplicates and restoration.");
  }

  const rollback = record(input.rollback);
  const inventoryImages = imageMap(input.parentImageBefore);
  const currentInventoryImage = inventoryImages?.get("inventory");
  const rollbackPassed = rollback?.status === "passed" && rollback.comparedCandidateCommit === commit &&
    cleanCommit(rollback.sourceCommit) && typeof rollback.previousImage === "string" &&
    typeof rollback.previousImageId === "string" && /^sha256:[a-f0-9]{64}$/i.test(rollback.previousImageId) &&
    rollback.currentImageId === currentInventoryImage && rollback.runningImageIdBefore === currentInventoryImage &&
    rollback.rollbackObserved === true && rollback.currentImageRestored === true && rollback.databaseRollback === false &&
    Array.isArray(rollback.relevantSourceChangesSinceBaseline) && rollback.relevantSourceChangesSinceBaseline.length === 0;
  const rollbackStatus: EvidenceStatus = rollbackPassed ? "PASS" : rollback?.status === "failed" ? "FAIL" : "BLOCKED";
  if (!rollbackPassed) issues.push("Rollback evidence does not reconcile to the parent candidate and restored inventory image.");

  const nfrBefore = imageMap(input.nfrImageBefore);
  const nfrAfter = imageMap(input.nfrImageAfter);
  const parentAfter = imageMap(input.parentImageAfter);
  const nfrCandidateBefore = record(record(input.nfrImageBefore)?.candidate);
  const nfrCandidateAfter = record(record(input.nfrImageAfter)?.candidate);
  const nfrManifestBefore = record(input.nfrImageBefore);
  const nfrManifestAfter = record(input.nfrImageAfter);
  if (!sameImages(nfrBefore, nfrAfter) || !sameImages(nfrBefore, inventoryImages) || !sameImages(nfrAfter, parentAfter) ||
      nfrCandidateBefore?.commit !== commit || nfrCandidateAfter?.commit !== commit ||
      nfrCandidateBefore?.worktree !== "clean" || nfrCandidateAfter?.worktree !== "clean" ||
      nfrManifestBefore?.capturePoint !== "before" || nfrManifestAfter?.capturePoint !== "after" ||
      typeof nfrManifestBefore?.runId !== "string" || nfrManifestBefore.runId !== nfrManifestAfter?.runId) {
    issues.push("NFR image manifests are incomplete or do not match the Docker run images.");
  }
  if (!/^[a-f0-9]{64}$/i.test(input.evidenceSha256 ?? "")) issues.push("NFR evidence digest is missing or invalid.");
  const selectedScopeStatus: EvidenceStatus = issues.length ? "BLOCKED" : "PASS";
  return { overallStatus: "PARTIAL", selectedScopeStatus, commit: issues.length ? null : commit,
    selectedCategories: selected.filter((item): item is NfrCategory => item === "operational" || item === "recovery"),
    notSelectedCategories: notSelected.filter((item): item is string => typeof item === "string" && /^[a-z-]{2,32}$/.test(item)),
    replayStatus: "NOT-RUN", replaySeconds: null,
    burst: { messages: burstMessages, inbox: burstInbox, effects: burstEffects, p95Seconds: burstP95 },
    recovery: { messages: typeof recoveryMessages === "number" ? recoveryMessages : null,
      seconds: typeof recoverySeconds === "number" ? recoverySeconds : null,
      lost: typeof lost === "number" ? lost : null, duplicateEffects: typeof duplicateEffects === "number" ? duplicateEffects : null },
    rollbackStatus, evidenceSha256: issues.length ? null : input.evidenceSha256!.toLowerCase(), issues };
}

export function hashNfrEvidence(files: ReadonlyArray<{ name: string; text: string | undefined }>): string | undefined {
  if (files.some(file => file.text === undefined)) return undefined;
  const hash = createHash("sha256");
  for (const file of [...files].sort((left, right) => left.name.localeCompare(right.name))) {
    hash.update(file.name, "utf8").update("\0", "utf8").update(file.text!, "utf8").update("\0", "utf8");
  }
  return hash.digest("hex");
}
