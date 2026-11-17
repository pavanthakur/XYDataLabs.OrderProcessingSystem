import { phase10ImageSetsMatch, validatePhase10ImageManifest } from "./phase10-images.js";
import type { Phase10ImageManifest } from "./phase10-images.js";
import { DOCKER_PACKET_STEPS } from "./phase10-report.js";

export type FollowupStatus = "PASS" | "FAIL" | "BLOCKED" | "NOT-RUN" | "DEFERRED";
export interface FollowupGate { id: string; status: FollowupStatus; detail: string }
export interface FollowupEvidence { id: string; path: string; sha256: string }
export interface LocalFollowupInput {
  e2e: { completion: "COMPLETE" | "INCOMPLETE"; completionStatus?: string; packet: unknown; summary: unknown; imageAfter: unknown };
  current: { imageManifest: unknown; foundation: unknown; functions: unknown; nfr: unknown; burst: unknown; outage: unknown; rollback: unknown };
  evidence: FollowupEvidence[];
}
export interface LocalFollowupReport {
  schema: "phase10-local-followup-v1";
  verdict: "FAIL" | "INCOMPLETE";
  candidate: { commit: string; worktree: "clean" | "dirty"; dirtyStatusSha256: string | null } | null;
  sourceRuns: { e2eRunId: string | null; e2eCommit: string | null; currentImageRunId: string | null };
  imageBinaryMatch: boolean | null;
  gates: FollowupGate[];
  evidence: FollowupEvidence[];
  limitations: string[];
}

function rec(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value)) : undefined;
}
function records(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value) ? value.map(rec).filter((item): item is Record<string, unknown> => !!item) : [];
}
function number(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}
function gate(id: string, pass: boolean, detail: string, fail = false): FollowupGate {
  return { id, status: pass ? "PASS" : fail ? "FAIL" : "BLOCKED", detail };
}
function imagesMatchByBinary(left: Phase10ImageManifest, right: Phase10ImageManifest): boolean {
  if (left.images.length !== right.images.length) return false;
  const a = new Map(left.images.map(item => [item.service, item]));
  const b = new Map(right.images.map(item => [item.service, item]));
  return a.size === 13 && b.size === 13 && [...a].every(([service, item]) => {
    const other = b.get(service);
    return !!other && item.imageId === other.imageId && item.imageReference === other.imageReference &&
      item.repositoryDigests.join("\n") === other.repositoryDigests.join("\n");
  });
}

export function reconcilePhase10LocalFollowup(input: LocalFollowupInput): LocalFollowupReport {
  const gates: FollowupGate[] = [];
  const summary = rec(input.e2e.summary);
  const e2eRunId = typeof summary?.runId === "string" ? summary.runId : null;
  const e2eProvenance = rec(summary?.gitProvenance);
  const e2eStart = rec(e2eProvenance?.start);
  const packet = rec(input.e2e.packet);
  const steps = records(packet?.steps);
  const sandbox = steps.filter(step => step.name === "sandbox-payments");
  const restoration = rec(packet?.restoration);
  const deferrals = Array.isArray(packet?.deferrals) ? packet.deferrals.map(String) : [];
  for (const name of DOCKER_PACKET_STEPS) {
    const matches = steps.filter(step => step.name === name);
    const status = matches.length === 1 ? matches[0].status : undefined;
    if (name === "order-continuation" && status === "failed") {
      gates.push({ id: "historical-e2e-order-continuation", status: "FAIL", detail: "Recorded step failed; a DW-023 deferral cannot hide an execution failure." });
    } else if (name === "order-continuation" && matches.length === 1 && deferrals.includes("DW-023") &&
        ["blocked", "deferred", "not-run"].includes(String(status))) {
      gates.push({ id: "historical-e2e-order-continuation", status: "DEFERRED", detail: `Recorded status=${String(status)} under DW-023; not a PASS.` });
    } else {
      gates.push(gate("historical-e2e-" + name, status === "passed",
        matches.length === 1 ? "recorded status=" + String(status) : "step missing or duplicated",
        status === "failed"));
    }
  }
  const e2eStepComplete = input.e2e.completion === "COMPLETE" && input.e2e.completionStatus === "passed" &&
    packet?.status === "passed" && sandbox.length === 1 && sandbox[0].status === "passed" &&
    restoration?.status === "passed" && restoration.allRestored === true && restoration.fixtureLockPresent === false;
  const e2eFailed = input.e2e.completionStatus === "failed" || packet?.status === "failed" ||
    sandbox.some(step => step.status === "failed") || restoration?.status === "failed" || restoration?.allRestored === false;
  gates.push(gate("historical-e2e-payment-and-restoration", e2eStepComplete,
    `completion=${input.e2e.completion}; sandbox=${sandbox.length === 1 ? String(sandbox[0].status) : "missing-or-duplicate"};` +
      ` restored=${restoration?.allRestored === true}; this remains bound to its recorded source revision.`, e2eFailed));


  const e2eImageResult = validatePhase10ImageManifest(input.e2e.imageAfter, e2eRunId ?? undefined, "after");
  const currentImageResult = validatePhase10ImageManifest(input.current.imageManifest, undefined, "after");
  const e2eManifest = e2eImageResult.status === "PASS" ? e2eImageResult.manifest : undefined;
  const currentManifest = currentImageResult.status === "PASS" ? currentImageResult.manifest : undefined;
  const imageBinaryMatch = e2eManifest && currentManifest ? imagesMatchByBinary(e2eManifest, currentManifest) : null;
  gates.push(gate("e2e-current-image-binary-match", imageBinaryMatch === true,
    imageBinaryMatch === true ? "All 13 image references, IDs and repository digests match; this is binary identity only, not source-candidate identity." :
      imageBinaryMatch === false ? "E2E and current Docker image binaries differ; historical payment proof cannot be reused for current images." :
        "One or both image manifests are missing or malformed." , imageBinaryMatch === false));

  const sourceSameAndClean = !!e2eStart && !!currentManifest && e2eStart.commit === currentManifest.candidate.commit &&
    e2eStart.worktree === "clean" && currentManifest.candidate.worktree === "clean";
  gates.push(gate("clean-single-source-candidate", sourceSameAndClean,
    `e2e=${String(e2eStart?.commit ?? "UNKNOWN")}/${String(e2eStart?.worktree ?? "UNKNOWN")};` +
      ` current=${String(currentManifest?.candidate.commit ?? "UNKNOWN")}/${String(currentManifest?.candidate.worktree ?? "UNKNOWN")}.`));

  const foundation = rec(input.current.foundation);
  const foundationResults = records(foundation?.results);
  const foundationPass = foundation?.status === "passed" && foundationResults.length > 0 &&
    foundationResults.every(item => item.status === "passed" && item.exitCode === 0);
  gates.push(gate("current-foundation-tests", foundationPass,
    `${foundationResults.filter(item => item.status === "passed").length}/${foundationResults.length} listed steps passed; worktree evidence remains separately scoped.`,
    foundation?.status === "failed" || foundationResults.some(item => item.status === "failed" || (number(item.exitCode) !== undefined && number(item.exitCode)! !== 0))));

  const functions = rec(input.current.functions);
  const functionsPass = functions?.status === "passed" && functions.approvalStatus === "processing-confirmed" &&
    functions.approvalOutcome === "approved" && functions.approvalReconciliationRequired === false &&
    functions.intake === "passed" && functions.replay === "passed" && functions.downstreamEffects === "passed";
  gates.push(gate("current-functions-replay", functionsPass,
    `status=${String(functions?.status ?? "UNKNOWN")}; approval=${String(functions?.approvalStatus ?? "UNKNOWN")};` +
      ` reconciliationRequired=${String(functions?.approvalReconciliationRequired ?? "UNKNOWN")}.`, functions?.status === "failed"));

  const nfr = rec(input.current.nfr);
  const categories = rec(nfr?.categories);
  const operational = rec(categories?.operational);
  const recoveryCategory = rec(categories?.recovery);
  const burst = rec(input.current.burst);
  const burstCounts = ["InventoryInboxCount", "NotificationsInboxCount", "InventoryEffectCount", "NotificationEffectCount"]
    .map(key => number(burst?.[key]));
  const burstPass = burst?.Status === "passed" && burst.ExpectedMessages === 100 && burstCounts.every(count => count === 100) &&
    number(burst.P95Seconds) !== undefined && number(burst.P95Seconds)! < 30;
  const outage = rec(input.current.outage);
  const outagePass = outage?.status === "passed" && outage?.messageCount === 100 && outage?.inventoryEffects === 100 &&
    outage?.notificationEffects === 100 && outage?.inventoryInbox === 100 && outage?.notificationsInbox === 100 &&
    outage?.lostMessages === 0 && outage?.duplicateEffects === 0 && number(outage?.p95Seconds) !== undefined &&
    number(outage?.p95Seconds)! < 30 && number(outage?.backlogRecoverySeconds) !== undefined &&
    number(outage?.backlogRecoverySeconds)! <= 1800 && outage?.restorationStatus === "passed" && outage?.environmentRestored === true;
  gates.push(gate("current-image-operational-and-outage", operational?.status === "passed" && burstPass && outagePass,
    `operational=${String(operational?.status ?? "UNKNOWN")}; burst100=${burstPass}; outage100=${outagePass}.`,
    operational?.status === "failed" || burst?.Status === "failed" || outage?.status === "failed" ||
      outage?.environmentRestored === false || outage?.restorationStatus === "failed"));

  const rollback = rec(input.current.rollback);
  const rollbackPass = rollback?.status === "passed" && rollback.rollbackObserved === true && rollback.currentImageRestored === true &&
    rollback.databaseRollback === false && typeof rollback.previousImageId === "string" && typeof rollback.currentImageId === "string" &&
    rollback.previousImageId !== rollback.currentImageId;
  gates.push(gate("current-image-rollback-and-restore", recoveryCategory?.status === "passed" && rollbackPass,
    `recoveryCategory=${String(recoveryCategory?.status ?? "UNKNOWN")}; rollback=${rollbackPass}.`,
    recoveryCategory?.status === "failed" || rollback?.status === "failed" || rollback?.currentImageRestored === false));

  const missingNfr = ["functional", "performance", "tenant", "payments", "security"]
    .filter(name => rec(categories?.[name])?.status !== "passed");
  const failedNfr = ["functional", "performance", "tenant", "payments", "security"]
    .some(name => rec(categories?.[name])?.status === "failed");
  gates.push(gate("full-current-image-nfr-categories", missingNfr.length === 0,
    missingNfr.length ? `Not proven in current NFR run: ${missingNfr.map(name => `${name}=${String(rec(categories?.[name])?.status ?? "missing")}`).join(", " )}.` :
      "All required NFR categories passed for current images.", failedNfr));
  gates.push({ id: "azure-acceptance", status: "NOT-RUN", detail: "Azure is excluded from this local follow-up report." });

  const anyFail = gates.some(item => item.status === "FAIL");
  return {
    schema: "phase10-local-followup-v1",
    verdict: anyFail ? "FAIL" : "INCOMPLETE",
    candidate: currentManifest?.candidate ?? null,
    sourceRuns: {
      e2eRunId,
      e2eCommit: typeof e2eStart?.commit === "string" ? e2eStart.commit : null,
      currentImageRunId: currentManifest?.runId ?? null
    },
    imageBinaryMatch,
    gates,
    evidence: input.evidence,
    limitations: [
      "This supplemental report does not alter or replace the sealed E2E, foundation, or NFR reports.",
      "Matching image IDs do not imply matching source revisions, test-runner revisions, environment configuration, or complete NFR coverage.",
      "An incomplete local report cannot certify Azure, L5-R, L6, fulfillment, installments, or unresolved-payment recovery."
    ]
  };
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]!);
}

export function renderPhase10LocalFollowupHtml(report: LocalFollowupReport, evidenceLinks: Map<string, string>): string {
  const rows = report.gates.map(item => `<tr><td>${escapeHtml(item.id)}</td><td>${item.status}</td><td>${escapeHtml(item.detail)}</td></tr>`).join("\n");
  const evidence = report.evidence.map(item => {
    const href = evidenceLinks.get(item.id);
    return `<li>${href ? `<a href="${escapeHtml(href)}">${escapeHtml(item.id)}</a>` : escapeHtml(item.id)} — SHA-256 ${escapeHtml(item.sha256)}</li>`;
  }).join("\n");
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Phase 10 local follow-up</title>
<style>body{font:15px system-ui,sans-serif;max-width:1100px;margin:2rem auto;padding:0 1rem;color:#172033}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ccd2dc;padding:.55rem;text-align:left}th{background:#eef2f7}.status{font-weight:700}</style></head><body>
<h1>Phase 10 local follow-up</h1><p class="status">Verdict: ${report.verdict} — this supplement cannot certify complete Phase 10 acceptance.</p>
<p>Candidate ${escapeHtml(report.candidate?.commit ?? "UNKNOWN")} (${report.candidate?.worktree ?? "UNKNOWN"}); E2E run ${escapeHtml(report.sourceRuns.e2eRunId ?? "UNKNOWN")} at ${escapeHtml(report.sourceRuns.e2eCommit ?? "UNKNOWN")}.</p>
<p>Current/E2E image-binary match: ${String(report.imageBinaryMatch)}. A match establishes image IDs only; see limitations below.</p>
<h2>Independent gates</h2><table><thead><tr><th>Gate</th><th>Status</th><th>Evidence interpretation</th></tr></thead><tbody>${rows}</tbody></table>
<h2>Source evidence (hashes bind these files as read)</h2><ul>${evidence}</ul>
<h2>Limitations</h2><ul>${report.limitations.map(item => `<li>${escapeHtml(item)}</li>`).join("\n")}</ul></body></html>\n`;
}
