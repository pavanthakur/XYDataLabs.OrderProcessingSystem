import { phase10ImageSetsMatch, validatePhase10ImageManifest } from "./phase10-images.js";
import type { Phase10ImageManifest } from "./phase10-images.js";
import { DOCKER_PACKET_STEPS } from "./phase10-report.js";
import type { Phase10WorktreeIdentity } from "./phase10-worktree-identity.js";

export type FollowupStatus = "PASS" | "FAIL" | "BLOCKED" | "NOT-RUN" | "DEFERRED";
export interface FollowupGate { id: string; status: FollowupStatus; detail: string }
export interface FollowupEvidence { id: string; path: string; sha256: string }
export interface LocalFollowupInput {
  e2e: { completion: "COMPLETE" | "INCOMPLETE"; completionStatus?: string; packet: unknown; summary: unknown; imageBefore?: unknown; imageAfter: unknown; restorationContract?: unknown };
  noPaymentReport?: { completion: "COMPLETE" | "INCOMPLETE"; completionStatus?: string; packet: unknown; summary: unknown; coverage: unknown };
  current: {
    imageManifest: unknown; sourceIdentity?: Phase10WorktreeIdentity; foundation: unknown; functions: unknown; nfr: unknown; burst: unknown; outage: unknown; rollback: unknown;
    paymentMatrices?: { deterministic?: unknown; sandboxPositive?: unknown; sandboxNegative?: unknown };
    paymentMatrixSource?: { summariesAndArtifactsNestedInE2e: boolean; caseArtifactsHashedAndCorrelated?: boolean };
    customerDirectoryRetry?: unknown;
    persistence?: { summary: unknown; before: unknown; after: unknown; imageBefore: unknown; imageAfter: unknown };
    operational?: { summary: unknown; imageManifest: unknown };
    replay?: { messaging: unknown; restoration: unknown; functions: unknown; imageManifest: unknown };
  };
  evidence: FollowupEvidence[];
}
export interface LocalFollowupReport {
  schema: "phase10-local-followup-v1";
  verdict: "FAIL" | "INCOMPLETE";
  candidate: { commit: string; worktree: "clean" | "dirty"; dirtyStatusSha256: string | null } | null;
  sourceRuns: { e2eRunId: string | null; e2eCommit: string | null; currentImageRunId: string | null };
  imageBinaryMatch: boolean | null;
  currentSourceIdentity: Phase10WorktreeIdentity | null;
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
function sameCandidate(left: Phase10ImageManifest, right: Phase10ImageManifest): boolean {
  return left.candidate.commit === right.candidate.commit && left.candidate.worktree === right.candidate.worktree &&
    left.candidate.dirtyStatusSha256 === right.candidate.dirtyStatusSha256 &&
    left.candidate.worktreeContentSha256 === right.candidate.worktreeContentSha256 &&
    (left.candidate.changedPaths ?? []).join("\n") === (right.candidate.changedPaths ?? []).join("\n");
}
function toolingOnlyPaths(paths: string[]): boolean {
  return paths.length > 0 && paths.every(path => path.startsWith("scripts/") || path.startsWith("automation/src/report/") ||
    path === "automation/src/cli/reconcile-phase10-local-followup.ts" || path.startsWith("automation/src/cli/reconcile-phase10-local-followup") ||
    path.startsWith("tools/Phase10.NfrProbe/") || path.startsWith("docs/") || path === "memories/repo/active-work.md");
}
function snapshotRows(value: unknown): string | undefined {
  if (!Array.isArray(value)) return undefined;
  return JSON.stringify(value);
}
function providerConfigurationMatches(e2eValue: unknown, currentValue: unknown): boolean {
  const e2e = rec(e2eValue);
  const current = rec(currentValue);
  if (e2e?.status !== "passed" || current?.schema !== "phase10-payment-settings-snapshot-v1") return false;
  const e2eTenants = records(e2e.tenants);
  const currentTenants = records(current.tenants);
  if (!e2eTenants.length || e2eTenants.length !== currentTenants.length) return false;
  return e2eTenants.every((tenant, index) => {
    const actual = currentTenants[index];
    if (!actual || tenant.tenant !== actual.code || tenant.status !== actual.status || tenant.tier !== actual.tier ||
        tenant.registryRoute !== actual.registryRoute || tenant.businessDatabase !== actual.businessDatabase) return false;
    const expectedProviders = records(tenant.providers).map(item => ({ provider: item.provider, threeDs: item.threeDs, production: item.nonProduction === true ? false : item.production })).sort((a, b) => String(a.provider).localeCompare(String(b.provider)));
    const actualProviders = records(actual.providers).map(item => ({ provider: item.provider, threeDs: item.threeDs, production: item.production })).sort((a, b) => String(a.provider).localeCompare(String(b.provider)));
    return JSON.stringify(expectedProviders) === JSON.stringify(actualProviders);
  });
}

function paymentMatrix(value: unknown): { summary?: Record<string, unknown>; groups: Record<string, unknown>[]; rows: Record<string, unknown>[] } {
  const summary = rec(value);
  const groups = records(summary?.results);
  return { summary, groups, rows: groups.flatMap(group => records(group.rows)) };
}

function positiveGroupsHavePhysicalVerification(groups: Record<string, unknown>[]): boolean {
  return groups.some(group => {
    if (group.rows === undefined || group.rows === null) return false;
    if (!Array.isArray(group.rows)) return true;
    return records(group.rows).length > 0 && (group.verificationSafety !== "established" ||
      typeof group.verificationSummary !== "string" || !group.verificationSummary.startsWith("Physical verification completed for "));
  });
}

function positivePaymentMatrixValid(value: unknown, expectedMode: "deterministic" | "sandbox"): boolean {
  const { summary, groups, rows } = paymentMatrix(value);
  if (!summary || summary.mode !== expectedMode || summary.acceptanceProfile !== "baseline" || summary.negative !== false ||
      summary.manualSmoke !== false || summary.status !== "passed" || summary.primaryPassed !== true || summary.coveragePassed !== true ||
      !Array.isArray(summary.skippedTenants) || summary.skippedTenants.length !== 0 || !Number.isInteger(summary.caseCount) ||
      summary.caseCount !== summary.expectedCaseCount || rows.length !== summary.caseCount || positiveGroupsHavePhysicalVerification(groups)) return false;
  const keys = new Set<string>();
  for (const row of rows) {
    const tenant = row.tenantCode;
    const provider = row.paymentProvider;
    const key = `${String(tenant)}|${String(provider)}`;
    if (typeof tenant !== "string" || !tenant || !["Razorpay", "OpenPay"].includes(String(provider)) || keys.has(key) ||
        row.journeyOutcome !== "completed" || row.verificationOutcome !== "passed" || row.cleanupOutcome !== "reset" ||
        row.executionEvidence !== "fresh" || row.adapterMode !== expectedMode || row.providerVerification !== `${expectedMode}:completed` ||
        typeof row.orderAmount !== "number" || row.orderAmount <= 0 ||
        row.orderCurrencyCode !== (provider === "Razorpay" ? "INR" : "MXN")) return false;
    keys.add(key);
  }
  const tenants = new Set(rows.map(row => String(row.tenantCode)));
  return tenants.size > 0 && rows.length === tenants.size * 2 && [...tenants].every(tenant =>
    keys.has(`${tenant}|Razorpay`) && keys.has(`${tenant}|OpenPay`));
}

function razorpayNegativeMatrixValid(value: unknown): boolean {
  const { summary, rows } = paymentMatrix(value);
  if (!summary || summary.mode !== "sandbox" || summary.acceptanceProfile !== "baseline" || summary.negative !== true ||
      summary.manualSmoke !== false || summary.status !== "passed" || summary.primaryPassed !== true || summary.coveragePassed !== true ||
      !Array.isArray(summary.skippedTenants) || summary.skippedTenants.length !== 0 || summary.caseCount !== summary.expectedCaseCount ||
      rows.length !== summary.caseCount) return false;
  const keys = new Set<string>();
  for (const row of rows) {
    const tenant = row.tenantCode;
    const outcome = row.journeyOutcome;
    const key = `${String(tenant)}|${String(outcome)}`;
    if (typeof tenant !== "string" || !tenant || !["expected-failure", "expected-cancelled"].includes(String(outcome)) || keys.has(key) ||
        row.paymentProvider !== "Razorpay" || row.verificationOutcome !== "passed" || row.cleanupOutcome !== "reset" ||
        row.executionEvidence !== "fresh" || row.adapterMode !== "sandbox" || row.orderCurrencyCode !== "INR" ||
        (outcome === "expected-failure" && row.providerVerification !== "sandbox:failed") ||
        (outcome === "expected-cancelled" && row.providerVerification !== "checkout-dismissed:order-unpaid")) return false;
    keys.add(key);
  }
  const tenants = new Set(rows.map(row => String(row.tenantCode)));
  return tenants.size > 0 && rows.length === tenants.size * 2 && [...tenants].every(tenant =>
    keys.has(`${tenant}|expected-failure`) && keys.has(`${tenant}|expected-cancelled`));
}

function paymentMatricesBoundToE2e(input: LocalFollowupInput): boolean {
  const matrices = input.current.paymentMatrices;
  const run = rec(input.e2e.summary);
  const packet = rec(input.e2e.packet);
  const steps = records(packet?.steps);
  const before = validatePhase10ImageManifest(input.e2e.imageBefore, typeof run?.runId === "string" ? run.runId : undefined, "before");
  const after = validatePhase10ImageManifest(input.e2e.imageAfter, typeof run?.runId === "string" ? run.runId : undefined, "after");
  const beforeManifest = before.status === "PASS" ? before.manifest : undefined;
  const afterManifest = after.status === "PASS" ? after.manifest : undefined;
  const start = typeof run?.startedUtc === "string" ? Date.parse(run.startedUtc) : Number.NaN;
  const finish = typeof run?.finishedUtc === "string" ? Date.parse(run.finishedUtc) : Number.NaN;
  const rows = [matrices?.deterministic, matrices?.sandboxPositive, matrices?.sandboxNegative]
    .flatMap(value => paymentMatrix(value).rows);
  const paymentStepsPassed = ["payments-deterministic", "sandbox-payments"].every(name => {
    const matching = steps.filter(step => step.name === name);
    return matching.length === 1 && matching[0].status === "passed";
  });
  const provenance = rec(run?.gitProvenance);
  const gitStart = rec(provenance?.start);
  const gitFinish = rec(provenance?.finish);
  return !!matrices && input.current.paymentMatrixSource?.summariesAndArtifactsNestedInE2e === true &&
    input.current.paymentMatrixSource.caseArtifactsHashedAndCorrelated === true &&
    input.e2e.completion === "COMPLETE" && input.e2e.completionStatus === "passed" &&
    run?.status === "passed" && run.paymentSuite === "both" && Number.isFinite(start) && Number.isFinite(finish) && start < finish &&
    paymentStepsPassed && gitStart?.commit === gitFinish?.commit && gitStart?.worktree === gitFinish?.worktree &&
    gitStart?.contentIdentity === gitFinish?.contentIdentity &&
    !!beforeManifest && !!afterManifest && sameCandidate(beforeManifest, afterManifest) && imagesMatchByBinary(beforeManifest, afterManifest) &&
    rows.length > 0 && rows.every(row => {
      const rowStart = typeof row.startedUtc === "string" ? Date.parse(row.startedUtc) : Number.NaN;
      const rowFinish = typeof row.finishedUtc === "string" ? Date.parse(row.finishedUtc) : Number.NaN;
      return Number.isFinite(rowStart) && Number.isFinite(rowFinish) && start <= rowStart && rowStart < rowFinish && rowFinish <= finish;
    });
}

function customerDirectoryRetryValid(value: unknown): boolean {
  const result = rec(value);
  const rows = records(result?.results);
  if (!result || !Array.isArray(result.results)) return false;
  const tenantUsers = ["TenantA", "TenantB", "TenantC"];
  const adminRows = rows.filter(row => row.account === "tenant-admin" && tenantUsers.includes(String(row.tenant)) &&
    row.status === "passed" && row.httpStatus === 200);
  const regularRows = rows.filter(row => typeof row.account === "string" && row.account.startsWith("tenant-") && row.account !== "tenant-admin");
  const expectedUsers = new Set(["tenant-a-user", "tenant-b-user", "tenant-c-user"]);
  const logout = rows.filter(row => row.scenario === "same-browser login/logout and cross-tab logout" && row.status === "passed");
  return adminRows.length === 3 && new Set(adminRows.map(row => row.tenant)).size === 3 &&
    regularRows.length === 3 && new Set(regularRows.map(row => row.account)).size === 3 &&
    regularRows.every(row => expectedUsers.has(String(row.account)) && row.status === "passed" && row.httpStatus === 200 &&
      row.deniedStatus === 403 && row.deniedTenant !== row.tenant) && logout.length === 1;
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
    if (name === "persistence" && status === "not-run") {
      gates.push({ id: "historical-e2e-persistence", status: "NOT-RUN", detail: "The sealed E2E packet did not run persistence; see the separate persistence evidence gate." });
    } else if (name === "order-continuation" && status === "failed") {
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

  const paymentMatrices = input.current.paymentMatrices;
  if (paymentMatrices) {
    const deterministicPassed = positivePaymentMatrixValid(paymentMatrices.deterministic, "deterministic");
    const sandboxPassed = positivePaymentMatrixValid(paymentMatrices.sandboxPositive, "sandbox");
    const razorpayNegativePassed = razorpayNegativeMatrixValid(paymentMatrices.sandboxNegative);
    gates.push(gate("supplemental-deterministic-payment-matrix", deterministicPassed,
      deterministicPassed ? "Fresh deterministic Razorpay and OpenPay journeys passed physical-order verification and fixture restoration for every covered tenant." :
        "Deterministic matrix is missing, incomplete, duplicated, simulated incorrectly, or contains an unverified/unclean case."));
    gates.push(gate("supplemental-sandbox-positive-payment-matrix", sandboxPassed,
      sandboxPassed ? "Fresh sandbox Razorpay and OpenPay journeys passed provider confirmation, physical-order verification and fixture restoration for every covered tenant." :
        "Sandbox positive matrix is missing, incomplete, simulated, duplicated, or contains an unverified/unclean case."));
    gates.push(gate("supplemental-razorpay-sandbox-negative-matrix", razorpayNegativePassed,
      razorpayNegativePassed ? "Razorpay decline and checkout-dismissal outcomes were verified for every covered tenant." :
        "Razorpay decline/cancellation matrix is missing, incomplete, or contains an unverified/unclean case."));
    const openPayNegativeUnavailable = rec(paymentMatrices.sandboxNegative)?.negativeSandboxAcceptance === "razorpay-passed-openpay-blocked";
    gates.push({ id: "openpay-sandbox-negative-capability", status: openPayNegativeUnavailable ? "BLOCKED" : "NOT-RUN",
      detail: "OpenPay sandbox challenge rejection/cancellation behavior remains unsupported or unverified; it is not counted as PASS." });
    const matrixSourceBound = paymentMatricesBoundToE2e(input);
    gates.push({ id: "payment-matrix-source-image-binding", status: matrixSourceBound ? "PASS" : "BLOCKED",
      detail: matrixSourceBound
        ? "Each payment summary and case-level ledger, provider confirmation/dependency trace, SQL proof, and verification report is hashed, correlated to its row, and contained in the sealed E2E run's unchanged source/image envelope."
        : "Payment evidence is blocked unless every case-level ledger, provider confirmation/dependency trace, SQL proof, and verification report is hashed, correlated to its row, and contained in the sealed E2E envelope." });
  }
  if (input.current.customerDirectoryRetry !== undefined) {
    const retryPassed = customerDirectoryRetryValid(input.current.customerDirectoryRetry);
    gates.push(gate("supplemental-customer-directory-identity-retry", retryPassed,
      retryPassed ? "Isolated browser retry passed admin switching across A/B/C, regular-user tenant isolation with 403 denials, and same-browser logout." :
        "Isolated customer-directory retry evidence is incomplete, duplicated, or contains an identity/isolation failure."));
  }


  const e2eImageResult = validatePhase10ImageManifest(input.e2e.imageAfter, e2eRunId ?? undefined, "after");
  const currentImageResult = validatePhase10ImageManifest(input.current.imageManifest, undefined, "after");
  const e2eManifest = e2eImageResult.status === "PASS" ? e2eImageResult.manifest : undefined;
  const currentManifest = currentImageResult.status === "PASS" ? currentImageResult.manifest : undefined;
  const imageBinaryMatch = e2eManifest && currentManifest ? imagesMatchByBinary(e2eManifest, currentManifest) : null;
  gates.push(gate("e2e-current-image-binary-match", imageBinaryMatch === true,
    imageBinaryMatch === true ? "All 13 image references, IDs and repository digests match; this is binary identity only, not source-candidate identity." :
      imageBinaryMatch === false ? "E2E and current Docker image binaries differ; historical payment proof cannot be reused for current images." :
        "One or both image manifests are missing or malformed." , imageBinaryMatch === false));

  const liveIdentity = input.current.sourceIdentity;
  const manifestCandidate = currentManifest?.candidate;
  const directCurrentSourceMatch = !!liveIdentity && !!manifestCandidate && liveIdentity.commit === manifestCandidate.commit &&
    liveIdentity.worktree === manifestCandidate.worktree && liveIdentity.dirtyStatusSha256 === manifestCandidate.dirtyStatusSha256 &&
    liveIdentity.worktreeContentSha256 === manifestCandidate.worktreeContentSha256 &&
    JSON.stringify(liveIdentity.changedPaths) === JSON.stringify(manifestCandidate.changedPaths);
  const committedSnapshot = liveIdentity?.committedSnapshot;
  const currentWorktreeChangesAreToolingOnly = !!liveIdentity &&
    (liveIdentity.worktree === "clean" || toolingOnlyPaths(liveIdentity.changedPaths));
  const committedSourceSnapshotMatchesImage = !!manifestCandidate && !!committedSnapshot && currentWorktreeChangesAreToolingOnly &&
    liveIdentity?.commit === committedSnapshot.commit && committedSnapshot.baseCommit === manifestCandidate.commit &&
    manifestCandidate.worktree === "dirty" && committedSnapshot.worktreeContentSha256 === manifestCandidate.worktreeContentSha256 &&
    JSON.stringify(committedSnapshot.changedPaths) === JSON.stringify(manifestCandidate.changedPaths) &&
    toolingOnlyPaths(committedSnapshot.changedPaths);
  // A clean image candidate remains source-compatible when the current checkout
  // differs only in allowlisted test/reporting tools. Runtime/application changes
  // remain blocked, and the report retains the dirty-worktree identity.
  const cleanImageWithToolingOverlay = !!manifestCandidate && !!liveIdentity && manifestCandidate.worktree === "clean" &&
    liveIdentity.commit === manifestCandidate.commit && liveIdentity.worktree === "dirty" &&
    toolingOnlyPaths(liveIdentity.changedPaths);
  const cleanImageWithCommittedToolingOverlay = !!manifestCandidate && !!committedSnapshot && manifestCandidate.worktree === "clean" &&
    liveIdentity?.commit === committedSnapshot.commit && committedSnapshot.baseCommit === manifestCandidate.commit &&
    toolingOnlyPaths(committedSnapshot.changedPaths);
  const currentSourceMatchesImage = directCurrentSourceMatch || committedSourceSnapshotMatchesImage || cleanImageWithToolingOverlay ||
    cleanImageWithCommittedToolingOverlay;
  gates.push(gate("current-checkout-image-candidate-identity", currentSourceMatchesImage,
    directCurrentSourceMatch ? "The reconciler's live Git worktree identity matches the source identity captured with the selected Docker image manifest." :
      committedSourceSnapshotMatchesImage ? "The selected image manifest's dirty source snapshot is reproduced exactly by the committed HEAD tree; any current uncommitted changes are tooling-only." :
      cleanImageWithToolingOverlay ? "The image was built from the current clean HEAD; the checkout differs only in allowlisted test/reporting tooling, and its dirty identity is retained." :
      cleanImageWithCommittedToolingOverlay ? "The image candidate is an ancestor of the current clean HEAD; intervening committed changes are confined to allowlisted test/reporting tooling." :
      `Live checkout=${liveIdentity?.commit ?? "UNKNOWN"}/${liveIdentity?.worktree ?? "UNKNOWN"}/${liveIdentity?.worktreeContentSha256 ?? "UNKNOWN"};` +
      ` image manifest=${manifestCandidate?.commit ?? "UNKNOWN"}/${manifestCandidate?.worktree ?? "UNKNOWN"}/${manifestCandidate?.worktreeContentSha256 ?? "UNKNOWN"}.`));

  const sourceSameAndClean = !!e2eStart && !!currentManifest && e2eStart.commit === currentManifest.candidate.commit &&
    e2eStart.worktree === "clean" && currentManifest.candidate.worktree === "clean";
  const exactE2eImageSourceSnapshot = !!e2eManifest && !!currentManifest && sameCandidate(e2eManifest, currentManifest);
  gates.push(gate("clean-single-source-candidate", sourceSameAndClean,
    `e2e=${String(e2eManifest?.candidate.commit ?? e2eStart?.commit ?? "UNKNOWN")}/${String(e2eManifest?.candidate.worktree ?? e2eStart?.worktree ?? "UNKNOWN")}/${String(e2eManifest?.candidate.worktreeContentSha256 ?? "UNKNOWN")};` +
      ` current=${String(currentManifest?.candidate.commit ?? "UNKNOWN")}/${String(currentManifest?.candidate.worktree ?? "UNKNOWN")}/${String(currentManifest?.candidate.worktreeContentSha256 ?? "UNKNOWN")};` +
      ` exactE2eToCurrentImageSnapshot=${exactE2eImageSourceSnapshot}.`));

  const changedPaths = currentManifest?.candidate.changedPaths ?? [];
  const dirtyIdentityAvailable = !!currentManifest && currentManifest.candidate.worktree === "dirty" &&
    /^[a-f0-9]{64}$/.test(currentManifest.candidate.worktreeContentSha256 ?? "") && changedPaths.length > 0;
  const toolingOnlyChanges = toolingOnlyPaths(changedPaths);
  const e2eCandidate = e2eManifest?.candidate;
  const e2eChangesAreToolingOnly = !!e2eCandidate && (e2eCandidate.worktree === "clean" ||
    (e2eCandidate.worktree === "dirty" && /^[a-f0-9]{64}$/.test(e2eCandidate.worktreeContentSha256 ?? "") &&
      toolingOnlyPaths(e2eCandidate.changedPaths ?? [])));
  const nfrRecord = rec(input.current.nfr);
  const settingsBefore = rec(nfrRecord?.paymentSettingsBefore);
  const settingsAfter = rec(nfrRecord?.paymentSettingsAfter);
  const settingsStable = nfrRecord?.paymentSettingsIntegrity === "passed" && !!settingsBefore && !!settingsAfter &&
    JSON.stringify(settingsBefore) === JSON.stringify(settingsAfter);
  const paymentConfigCompatible = settingsStable && providerConfigurationMatches(input.e2e.restorationContract, settingsBefore);
  const paymentCompatible = currentSourceMatchesImage && !!e2eStart && !!currentManifest && e2eStart.commit === currentManifest.candidate.commit &&
    imageBinaryMatch === true && e2eChangesAreToolingOnly &&
    (currentManifest.candidate.worktree === "clean" || (dirtyIdentityAvailable && toolingOnlyChanges)) && paymentConfigCompatible;
  gates.push(gate("historical-e2e-payment-compatibility", paymentCompatible,
    paymentCompatible ? "E2E source commit and all service images match; the content-addressed diff is tooling-only and current payment settings match the recorded baseline." :
      "Historical payment evidence cannot be reused: source/image identity, content-addressed tooling-only diff, or payment configuration compatibility is not fully proven."));

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
  const operationalEvidence = input.current.operational;
  const operationalSummary = rec(operationalEvidence?.summary);
  const operationalCategories = rec(operationalSummary?.categories);
  const operational = rec(operationalCategories?.operational);
  const recoveryCategory = rec(operationalCategories?.recovery);
  const operationalSelected = operational?.execution === "selected";
  const recoverySelected = recoveryCategory?.execution === "selected";
  const operationalImageResult = validatePhase10ImageManifest(operationalEvidence?.imageManifest, undefined, "after");
  const operationalManifest = operationalImageResult.status === "PASS" ? operationalImageResult.manifest : undefined;
  const operationalImageBound = !!currentManifest && !!operationalManifest && sameCandidate(currentManifest, operationalManifest) &&
    imagesMatchByBinary(currentManifest, operationalManifest);
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
  gates.push(gate("current-image-operational-and-outage", operational?.status === "passed" && operationalSelected && burstPass && outagePass && operationalImageBound,
    `operational=${String(operational?.status ?? "UNKNOWN")}; execution=${String(operational?.execution ?? "UNKNOWN")}; burst100=${burstPass}; outage100=${outagePass}; sameCandidateAndImages=${operationalImageBound}.`,
    operational?.status === "failed" || burst?.Status === "failed" || outage?.status === "failed" ||
      outage?.environmentRestored === false || outage?.restorationStatus === "failed"));

  const rollback = rec(input.current.rollback);
  const rollbackPass = rollback?.status === "passed" && rollback.rollbackObserved === true && rollback.currentImageRestored === true &&
    rollback.databaseRollback === false && typeof rollback.previousImageId === "string" && typeof rollback.currentImageId === "string" &&
    rollback.previousImageId !== rollback.currentImageId;
  gates.push(gate("current-image-rollback-and-restore", recoveryCategory?.status === "passed" && recoverySelected && rollbackPass && operationalImageBound,
    `recoveryCategory=${String(recoveryCategory?.status ?? "UNKNOWN")}; execution=${String(recoveryCategory?.execution ?? "UNKNOWN")}; rollback=${rollbackPass}; sameCandidateAndImages=${operationalImageBound}.`,
    recoveryCategory?.status === "failed" || rollback?.status === "failed" || rollback?.currentImageRestored === false));

  const persistence = input.current.persistence;
  const persistenceSummary = rec(persistence?.summary);
  const beforeRows = snapshotRows(persistence?.before);
  const afterRows = snapshotRows(persistence?.after);
  const persistenceBeforeImage = validatePhase10ImageManifest(persistence?.imageBefore, undefined, "before");
  const persistenceAfterImage = validatePhase10ImageManifest(persistence?.imageAfter, undefined, "after");
  const persistenceBeforeManifest = persistenceBeforeImage.status === "PASS" ? persistenceBeforeImage.manifest : undefined;
  const persistenceAfterManifest = persistenceAfterImage.status === "PASS" ? persistenceAfterImage.manifest : undefined;
  const persistenceBound = !!currentManifest && !!persistenceBeforeManifest && !!persistenceAfterManifest &&
    persistenceSummary?.status === "passed" && persistenceSummary.imageIdentitiesUnchanged === true &&
    persistenceSummary.disk === "G:\\DockerStorage\\DockerDesktopWSL" && typeof persistenceSummary.sqlVolume === "string" &&
    beforeRows !== undefined && beforeRows === afterRows && phase10ImageSetsMatch(persistenceBeforeManifest, persistenceAfterManifest) &&
    sameCandidate(currentManifest, persistenceAfterManifest) && imagesMatchByBinary(currentManifest, persistenceAfterManifest);
  gates.push(gate("current-image-persistence", persistenceBound,
    persistenceBound ? "Known tenant/order rows and SQL volume persisted across Docker Desktop restart; before/after image identities match the selected NFR candidate." :
      "Separate persistence evidence is missing, not run, or cannot be bound to unchanged before/after images and the selected NFR candidate.",
    persistenceSummary?.status === "failed"));
  const persistenceOutcomePass = !!persistenceSummary && persistenceSummary.status === "passed" &&
    persistenceSummary.imageIdentitiesUnchanged === true && persistenceSummary.disk === "G:\\DockerStorage\\DockerDesktopWSL" &&
    typeof persistenceSummary.sqlVolume === "string" && beforeRows !== undefined && beforeRows === afterRows &&
    persistenceBeforeImage.status === "PASS" && persistenceAfterImage.status === "PASS" &&
    phase10ImageSetsMatch(persistenceBeforeImage.manifest!, persistenceAfterImage.manifest!) &&
    imagesMatchByBinary(persistenceBeforeImage.manifest!, persistenceAfterImage.manifest!);
  gates.push(gate("supplemental-persistence-outcome", persistenceOutcomePass,
    persistenceOutcomePass ? "Known tenant/order rows survived the Docker Desktop restart on G:; the SQL volume and all service image binaries were unchanged." :
      "Persistence execution evidence is incomplete or indicates a data, volume, storage-location, or image change.", persistenceSummary?.status === "failed"));
  gates.push({ id: "persistence-source-image-binding", status: persistenceOutcomePass && persistenceBound ? "PASS" : "BLOCKED",
    detail: persistenceOutcomePass && persistenceBound ? "Persistence evidence is also bound to the selected source candidate and service images." :
      "Persistence outcome passed separately, but its source-candidate identity does not match the selected NFR evidence; do not claim same-candidate persistence acceptance." });

  const replay = input.current.replay;
  const messaging = rec(replay?.messaging);
  const replayRestoration = rec(replay?.restoration);
  const replayFunctions = rec(replay?.functions);
  const replayImageResult = validatePhase10ImageManifest(replay?.imageManifest, undefined, "after");
  const replayManifest = replayImageResult.status === "PASS" ? replayImageResult.manifest : undefined;
  const replayImageBound = !!currentManifest && !!replayManifest && sameCandidate(currentManifest, replayManifest) &&
    imagesMatchByBinary(currentManifest, replayManifest);
  const replayEffectPass = messaging?.Status === "passed" && typeof messaging.ExpectedMessages === "number" && messaging.ExpectedMessages > 0 &&
    [messaging.InventoryInboxCount, messaging.NotificationsInboxCount, messaging.InventoryEffectCount, messaging.NotificationEffectCount]
      .every(value => typeof value === "number" && value === messaging.ExpectedMessages) &&
    replayRestoration?.status === "passed" && replayRestoration.effectiveSettingMatches === true &&
    replayFunctions?.status === "passed" && replayFunctions.approvalSubmissionAttempts === 1 &&
    replayFunctions.approvalResubmitted === false && replayImageBound;
  gates.push(gate("current-image-replay", replayEffectPass,
    `messaging=${String(messaging?.Status ?? "UNKNOWN")}; restoration=${String(replayRestoration?.status ?? "UNKNOWN")};` +
      ` functions=${String(replayFunctions?.status ?? "UNKNOWN")}; sameCandidateAndImages=${replayImageBound}.` ,
    messaging?.Status === "failed" || replayRestoration?.status === "failed" || replayFunctions?.status === "failed"));

  const missingNfr = ["functional", "tenant", "security"].filter(name => rec(categories?.[name])?.status !== "passed");
  if (rec(categories?.payments)?.integrationStatus !== "passed" || !paymentCompatible) missingNfr.push("payments-integration-or-compatible-sandbox-evidence");
  if (!burstPass || !operationalImageBound || !operationalSelected) missingNfr.push("performance-evidence");
  const failedNfr = ["functional", "tenant", "security"].some(name => rec(categories?.[name])?.status === "failed") ||
    rec(categories?.payments)?.integrationStatus === "failed";
  gates.push(gate("full-current-image-nfr-categories", missingNfr.length === 0,
    missingNfr.length ? `Not proven for the selected candidate: ${missingNfr.join(", ")}.` :
      "Required current NFR categories and compatible historical sandbox evidence are independently proven.", failedNfr));

  const evidenceIds = input.evidence.map(item => item.id);
  const evidenceValid = evidenceIds.length === new Set(evidenceIds).size && input.evidence.every(item =>
    typeof item.id === "string" && !!item.id && typeof item.path === "string" && item.path.startsWith("TestResults/") &&
    !item.path.startsWith("/") && !/(^|\/)\.\.?($|\/)/.test(item.path) && /^[a-f0-9]{64}$/.test(item.sha256));
  gates.push(gate("source-evidence-integrity", evidenceValid,
    evidenceValid ? `${input.evidence.length} unique TestResults artifacts have canonical SHA-256 identities.` :
      "Evidence list has duplicate IDs, unsafe paths, or malformed SHA-256 values.", !evidenceValid));
  gates.push({ id: "azure-acceptance", status: "NOT-RUN", detail: "Azure is excluded from this local follow-up report." });

  const noPayment = input.noPaymentReport;
  if (noPayment) {
    const noPaymentSummary = rec(noPayment.summary);
    const noPaymentPacket = rec(noPayment.packet);
    const coverage = rec(noPayment.coverage);
    const noPaymentSteps = records(noPaymentPacket?.steps);
    const paymentSteps = ["payments-deterministic", "sandbox-payments"].map(name =>
      noPaymentSteps.filter(step => step.name === name));
    const identityStart = rec(rec(noPaymentSummary?.gitProvenance)?.start);
    const identityFinish = rec(rec(noPaymentSummary?.gitProvenance)?.finish);
    const valid = noPayment.completion === "COMPLETE" && noPayment.completionStatus === "partial" &&
      noPaymentSummary?.status === "partial" && noPaymentPacket?.status === "partial" &&
      typeof noPaymentSummary.runId === "string" && /^phase10-docker-http-\d{8}-\d{9}$/.test(noPaymentSummary.runId) &&
      noPaymentPacket.runRoot === noPaymentSummary.runRoot &&
      typeof noPaymentSummary.runRoot === "string" && noPaymentSummary.runRoot.replace(/[\\/]+$/, "").split(/[\\/]/).at(-1) === noPaymentSummary.runId &&
      noPaymentSummary.paymentSuite === "none" && coverage?.schema === "phase10-sanitized-coverage-v2" &&
      coverage.runId === noPaymentSummary.runId && coverage.provisional === false &&
      noPaymentSteps.length > 0 && !noPaymentSteps.some(step => step.status === "failed") &&
      paymentSteps.every(matches => matches.length === 1 && matches[0].status === "not-run") &&
      typeof identityStart?.contentIdentity === "string" && /^[a-f0-9]{64}$/.test(identityStart.contentIdentity) &&
      identityFinish?.contentIdentity === identityStart.contentIdentity;
    gates.push(gate("no-payment-report-finalization", valid,
      `completion=${noPayment.completion}/${String(noPayment.completionStatus ?? "UNKNOWN")}; runId=${String(noPaymentSummary?.runId ?? "UNKNOWN")}; coverageFinalized=${coverage?.provisional === false}; paymentStepsNotRun=${paymentSteps.every(matches => matches.length === 1 && matches[0].status === "not-run")}.`));
  }

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
    currentSourceIdentity: liveIdentity ?? null,
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
