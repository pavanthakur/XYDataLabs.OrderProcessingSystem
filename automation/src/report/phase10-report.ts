import { FOUNDATION_AUTOMATION_TEST_CHECKS, normalizeFoundationSummary } from "./phase10-foundations.js";
import type { FoundationReport } from "./phase10-foundations.js";
import { FOUNDATION_TRX_PROJECTS, MAX_DISPLAYED_TEST_OUTCOMES, parseFoundationTrx } from "./phase10-trx.js";
import type { TestOutcome, TrxProject, TrxSuite, TrxResult } from "./phase10-trx.js";
import { parseVitest } from "./phase10-vitest.js";
import type { VitestResult } from "./phase10-vitest.js";
import { parseBackendCoverage, parseFrontendCoverage } from "./phase10-coverage.js";
import type { BackendCoverage, FrontendCoverage } from "./phase10-coverage.js";
import { normalizeAutomationSuites, normalizeDiscoveredDotnetSuite } from "./phase10-automation.js";
import type { AutomationSuiteReport } from "./phase10-automation.js";
import { phase10ImageSetsMatch, validatePhase10ImageManifest } from "./phase10-images.js";
import type { Phase10ImageRecord } from "./phase10-images.js";

export const PHASE10_REPORT_VERSION = 14 as const;

// This inventory mirrors the Docker hook's final packet, not the complete L5-R suite inventory.
export const DOCKER_PACKET_STEPS = [
  "foundations", "smoke", "integration", "openpay-local-baseline",
  "baseline-validation", "customer-directory", "tenantc-routing-regression",
  "payments-deterministic", "sandbox-payments", "currency-order-entry",
  "order-continuation", "messaging-functions", "persistence", "provider-restoration"
] as const;

export type EvidenceStatus = "PASS" | "FAIL" | "SKIPPED" | "BLOCKED" | "DEFERRED" | "NOT-RUN" | "PARTIAL";
export type PacketStep = { name: string; status: EvidenceStatus; selection: "SELECTED" | "NOT-SELECTED" | "UNKNOWN" };
export type GitSnapshot = { commit: string | null; worktree: "CLEAN" | "DIRTY" | "UNKNOWN" };
export interface Phase10Report {
  version: typeof PHASE10_REPORT_VERSION;
  runId: string | null;
  packetStatus: EvidenceStatus;
  profile: "baseline" | "extended" | "UNKNOWN";
  paymentSuite: "sandbox" | "deterministic" | "both" | "UNKNOWN";
  startedUtc: string | null;
  finishedUtc: string | null;
  restoration: EvidenceStatus;
  storage: EvidenceStatus;
  foundations: FoundationReport;
  trx: TrxResult[];
  integration: TrxResult;
  integrationCoverage: BackendCoverage;
  frontend: VitestResult;
  frontendCoverage: FrontendCoverage;
  backendCoverage: { project: TrxProject; coverage: BackendCoverage }[];
  automation: AutomationSuiteReport[];
  dotnetTests: AutomationSuiteReport[];
  git: { start: GitSnapshot; finish: GitSnapshot };
  imageIdentities: { status: "PASS" | "FAIL" | "BLOCKED"; detail: string; services: Phase10ImageRecord[] };
  steps: PacketStep[];
  issues: string[];
  overall: "FAIL" | "BLOCKED";
}

function timestamp(value: unknown): string | null {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$/.test(value)) return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? new Date(parsed).toISOString() : null;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value))
    : undefined;
}

function status(value: unknown): EvidenceStatus | undefined {
  switch (value) {
    case "passed": return "PASS";
    case "failed": return "FAIL";
    case "skipped": return "SKIPPED";
    case "blocked": return "BLOCKED";
    case "deferred": return "DEFERRED";
    case "not-run": return "NOT-RUN";
    case "partial": case "running": return "PARTIAL";
    default: return undefined;
  }
}

function gitSnapshot(value: unknown): GitSnapshot {
  const snapshot = record(value);
  const commit = typeof snapshot?.commit === "string" && /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(snapshot.commit)
    ? snapshot.commit : null;
  const worktree = snapshot?.worktree === "clean" ? "CLEAN" : snapshot?.worktree === "dirty" ? "DIRTY" : "UNKNOWN";
  return { commit, worktree };
}

export function normalizePhase10Packet(packetInput: unknown, summaryInput: unknown, foundationInput?: unknown,
  trxInputs: Partial<Record<TrxProject, string>> = {}, additional?: { integrationTrx?: string; integrationDuplicate?: boolean; frontend?: unknown;
    frontendCoverage?: unknown; frontendCoverageModifiedUtc?: number; integrationCoverage?: { xml: string; modifiedUtc: number };
    backendCoverage?: Partial<Record<TrxProject, { xml: string; modifiedUtc: number }>>;
    automation?: Partial<Record<string, unknown>>; automationInventorySha256?: string;
    dotnetTests?: Partial<Record<TrxSuite, unknown>>; reportInputIssues?: string[];
    dockerImageBefore?: unknown; dockerImageAfter?: unknown }): Phase10Report {
  const issues: string[] = [];
  if (additional?.reportInputIssues?.length) issues.push(...additional.reportInputIssues);
  const packet = record(packetInput);
  const summary = record(summaryInput);
  const provenance = record(summary?.gitProvenance);
  const git = { start: gitSnapshot(provenance?.start), finish: gitSnapshot(provenance?.finish) };
  const packetStatus = status(packet?.status);
  const summaryStatus = status(summary?.status);
  if (!packet || !packetStatus || !Array.isArray(packet.steps)) issues.push("Acceptance packet missing or malformed.");
  if (!summary || !summaryStatus) issues.push("Run summary missing or malformed.");
  if (packetStatus && summaryStatus && packetStatus !== summaryStatus) issues.push("Packet and run summary statuses disagree.");
  if (typeof packet?.runRoot !== "string" || typeof summary?.runRoot !== "string") {
    issues.push("Packet and summary run identity cannot be reconciled.");
  } else if (packet.runRoot !== summary.runRoot) {
    issues.push("Packet and summary run paths disagree.");
  }
  const profile = summary?.acceptanceProfile === "baseline" || summary?.acceptanceProfile === "extended"
    ? summary.acceptanceProfile : "UNKNOWN";
  const paymentSuite = summary?.paymentSuite === "sandbox" || summary?.paymentSuite === "deterministic" || summary?.paymentSuite === "both"
    ? summary.paymentSuite : "UNKNOWN";
  if (profile === "UNKNOWN") issues.push("Acceptance profile missing or invalid.");
  if (paymentSuite === "UNKNOWN") issues.push("Payment suite selection missing or invalid.");
  const startedUtc = timestamp(summary?.startedUtc);
  const finishedUtc = timestamp(summary?.finishedUtc);
  if (!startedUtc || !finishedUtc || finishedUtc < startedUtc) issues.push("Run timestamps missing, invalid, or out of order.");
  const runId = typeof summary?.runId === "string" && /^phase10-docker-http-\d{8}-\d{9}$/.test(summary.runId)
    ? summary.runId : null;
  if (!runId) issues.push("Run ID missing or invalid.");
  const imageBefore = validatePhase10ImageManifest(additional?.dockerImageBefore, runId ?? undefined, "before");
  const imageAfter = validatePhase10ImageManifest(additional?.dockerImageAfter, runId ?? undefined, "after");
  let imageIdentities: Phase10Report["imageIdentities"] = { status: "BLOCKED", detail: "Image identity is missing or invalid.", services: [] };
  if (imageBefore.status === "PASS" && imageAfter.status === "PASS") {
    if (imageBefore.manifest.candidate.worktree !== "clean" || imageAfter.manifest.candidate.worktree !== "clean" ||
        imageBefore.manifest.candidate.commit !== imageAfter.manifest.candidate.commit ||
        (git.start.commit !== null && git.start.commit !== imageBefore.manifest.candidate.commit) ||
        (git.finish.commit !== null && git.finish.commit !== imageAfter.manifest.candidate.commit)) {
      imageIdentities = { status: "BLOCKED", detail: "Images match, but source revision/worktree provenance is not clean and aligned.", services: imageAfter.manifest.images };
    } else if (!phase10ImageSetsMatch(imageBefore.manifest, imageAfter.manifest)) {
      imageIdentities = { status: "FAIL", detail: "Service image identity changed during the run.", services: imageAfter.manifest.images };
    } else {
      imageIdentities = { status: "PASS", detail: "All 13 service image IDs match between start and finish for the recorded clean candidate.", services: imageAfter.manifest.images };
    }
  } else {
    issues.push("Docker image identity manifests are missing, malformed, or not bound to this run.");
  }

  const inputSteps: unknown[] = Array.isArray(packet?.steps) ? packet.steps : [];
  const steps = DOCKER_PACKET_STEPS.map((name): PacketStep => {
    const suite = name === "payments-deterministic" ? "deterministic"
      : name === "sandbox-payments" || name === "order-continuation" ? "sandbox" : null;
    const selection = suite === null || paymentSuite === "UNKNOWN" ? "UNKNOWN"
      : paymentSuite === "both" || paymentSuite === suite ? "SELECTED" : "NOT-SELECTED";
    const matches = inputSteps.map(record).filter(step => step?.name === name);
    if (matches.length > 1) {
      issues.push(`Duplicate step: ${name}.`);
      return { name, status: "BLOCKED", selection };
    }
    if (!matches.length) return { name, status: "NOT-RUN", selection };
    const value = status(matches[0]?.status);
    if (!value) {
      issues.push(`Invalid status for step: ${name}.`);
      return { name, status: "BLOCKED", selection };
    }
    if (selection === "NOT-SELECTED" && value !== "NOT-RUN" && value !== "SKIPPED") {
      issues.push(`Unselected step has evidence: ${name}.`);
    }
    return { name, status: value, selection };
  });
  if (packetStatus === "PASS" && steps.some(step =>
    (step.name === "payments-deterministic" || step.name === "sandbox-payments") &&
    step.selection === "SELECTED" && step.status !== "PASS")) {
    issues.push("Packet reports PASS with an incomplete or unsuccessful selected payment suite.");
  }
  if (inputSteps.some(step => !record(step) || typeof record(step)?.name !== "string")) {
    issues.push("Packet contains a malformed step.");
  }
  const hasFailedStep = inputSteps.some(step => status(record(step)?.status) === "FAIL");
  const foundations = normalizeFoundationSummary(foundationInput, startedUtc, finishedUtc);
  issues.push(...foundations.issues);
  const trx = FOUNDATION_TRX_PROJECTS.map(project => {
    const check = foundations.checks.find(item => item.name === `${project}-tests`);
    const result = parseFoundationTrx(project, trxInputs[project], check?.window ?? null, check?.status ?? "BLOCKED");
    if (result.status === "BLOCKED") issues.push(`TRX evidence missing, invalid, stale or inconsistent: ${project}.`);
    return result;
  });
  const integrationStep = steps.find(step => step.name === "integration");
  const runWindow = startedUtc && finishedUtc && startedUtc <= finishedUtc ? { startedUtc, finishedUtc } : null;
  const integration = parseFoundationTrx("Integration", additional?.integrationDuplicate ? undefined : additional?.integrationTrx,
    runWindow, integrationStep?.status ?? "BLOCKED");
  const integrationCoverage = parseBackendCoverage(additional?.integrationCoverage?.xml, additional?.integrationCoverage?.modifiedUtc,
    runWindow, integration.status);
  const frontendCheck = foundations.checks.find(item => item.name === "frontend-tests");
  const frontend = parseVitest(additional?.frontend, frontendCheck?.window ?? null, frontendCheck?.status ?? "BLOCKED");
  const frontendCoverage = parseFrontendCoverage(additional?.frontendCoverage, additional?.frontendCoverageModifiedUtc,
    frontendCheck?.window ?? null, frontend.status);
  const backendCoverage = FOUNDATION_TRX_PROJECTS.map(project => {
    const check = foundations.checks.find(item => item.name === `${project}-tests`);
    const result = trx.find(item => item.project === project);
    const input = additional?.backendCoverage?.[project];
    return { project, coverage: parseBackendCoverage(input?.xml, input?.modifiedUtc, check?.window ?? null, result?.status ?? "BLOCKED") };
  });
  const dotnetTests = FOUNDATION_TRX_PROJECTS.map(project => {
    const check = foundations.checks.find(item => item.name === `${project}-tests`);
    const result = trx.find(item => item.project === project)!;
    return normalizeDiscoveredDotnetSuite(additional?.dotnetTests?.[project], project, result, check?.window ?? null);
  });
  dotnetTests.push(normalizeDiscoveredDotnetSuite(additional?.dotnetTests?.Integration, "Integration", integration, runWindow));
  for (const suite of dotnetTests) {
    if (suite.status !== "PASS") issues.push(`Discovered .NET test inventory/result reconciliation is ${suite.status}: ${suite.id}.`);
  }
  const automation = normalizeAutomationSuites(additional?.automation ?? {}, additional?.automationInventorySha256 ?? "");
  for (const suite of automation) {
    if (suite.status !== "PASS") issues.push(`Automation test inventory/result reconciliation is ${suite.status}: ${suite.id}.`);
  }
  if (integration.status === "BLOCKED") issues.push("Integration TRX missing, duplicate, invalid, stale or inconsistent.");
  if (dotnetTests.find(suite => suite.id === "Integration-tests")?.status !== "PASS") {
    issues.push("Discovered integration test inventory does not exactly reconcile with TRX identities and outcomes.");
  }
  if (frontend.status === "BLOCKED") issues.push("Frontend structured results missing, invalid, stale or inconsistent.");
  if (steps.find(step => step.name === "foundations")?.status === "PASS" && foundations.hasFailure) {
    issues.push("Packet reports foundations PASS despite a failed foundation check.");
  }
  const restorationRecord = record(packet?.restoration);
  const restorationStatus = status(restorationRecord?.status);
  const restorationFailure = restorationStatus === "FAIL" || restorationRecord?.allRestored === false
    || restorationRecord?.fixtureLockPresent === true;
  const restoration: EvidenceStatus = restorationFailure ? "FAIL"
    : restorationStatus === "PASS" && restorationRecord?.allRestored === true && restorationRecord?.fixtureLockPresent === false
      ? "PASS" : "BLOCKED";
  if (restoration === "BLOCKED") issues.push("Restoration evidence missing or incomplete.");
  if (restorationStatus === "PASS" && restorationFailure) issues.push("Restoration evidence is contradictory.");
  const packetStorage = packet?.storageExitCode;
  const summaryStorage = summary?.storageExitCode;
  const validExit = (value: unknown): value is number => typeof value === "number" && Number.isInteger(value) && value >= 0;
  const storageFailure = (validExit(packetStorage) && packetStorage !== 0) || (validExit(summaryStorage) && summaryStorage !== 0);
  const storage: EvidenceStatus = storageFailure ? "FAIL"
    : packetStorage === 0 && summaryStorage === 0 ? "PASS" : "BLOCKED";
  if (!validExit(packetStorage) || !validExit(summaryStorage)) issues.push("Storage exit evidence missing or invalid.");
  if (validExit(packetStorage) && validExit(summaryStorage) && packetStorage !== summaryStorage) issues.push("Storage exit codes disagree.");
  if (packetStatus === "PASS" && hasFailedStep) {
    issues.push("Packet reports PASS despite a failed step.");
  }
  if (packetStatus === "PASS" && (restoration === "FAIL" || storage === "FAIL")) {
    issues.push("Packet reports PASS despite failed restoration or storage evidence.");
  }
  const overall = packetStatus === "FAIL" || summaryStatus === "FAIL" || hasFailedStep || foundations.hasFailure ||
    trx.some(result => result.status === "FAIL") || integration.status === "FAIL" || frontend.status === "FAIL" || restoration === "FAIL" || storage === "FAIL"
    ? "FAIL" : "BLOCKED";
  return { version: PHASE10_REPORT_VERSION, runId, packetStatus: packetStatus ?? "BLOCKED", profile, paymentSuite,
    startedUtc, finishedUtc, restoration, storage, foundations, trx, integration, integrationCoverage, frontend, frontendCoverage,
    backendCoverage, automation, dotnetTests, git, imageIdentities, steps, issues, overall };
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, character => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  })[character]!);
}

function statusSummary(items: readonly { status: EvidenceStatus }[]): string {
  const statuses: EvidenceStatus[] = ["PASS", "FAIL", "PARTIAL", "BLOCKED", "SKIPPED", "NOT-RUN", "DEFERRED"];
  return statuses.map(status => `${status}: ${items.filter(item => item.status === status).length}`).join("; ");
}

export function renderPhase10CoverageSummary(report: Phase10Report): string {
  const counts = (coverage: BackendCoverage) => coverage.state === "MEASURED"
    ? { state: coverage.state, lines: coverage.lines, branches: coverage.branches }
    : { state: "UNAVAILABLE" };
  return JSON.stringify({
    schema: "phase10-sanitized-coverage-v2",
    provisional: true,
    runId: report.runId,
    backend: report.backendCoverage.map(({ project, coverage }) => ({ project, ...counts(coverage) })),
    frontend: counts(report.frontendCoverage),
    backendBranchScope: "Coverlet XML root totals; detailed HTML may show only line-attached branches.",
    frontendScope: "Web app source; shared packages and deployed services excluded.",
    integration: counts(report.integrationCoverage),
    integrationScope: "Integration test process only; not merged with foundation coverage or deployed services."
  }, null, 2) + "\n";
}

export function renderPhase10Report(report: Phase10Report, coverageSummaryAvailable = false): string {
  const rows = report.steps.map(step => `<tr><td>${escapeHtml(step.name)}</td><td>${step.selection}</td><td>${step.status}</td></tr>`).join("\n");
  const issues = report.issues.map(issue => `<li>${escapeHtml(issue)}</li>`).join("\n");
  const foundationRows = report.foundations.checks.map(check => `<tr><td>${escapeHtml(check.name)}</td><td>${check.status}</td></tr>`).join("\n");
  const trxRows = [...report.trx, report.integration].map(result => `<tr><td>${result.project}</td><td>${result.status}</td><td>${result.counts?.total ?? "UNAVAILABLE"}</td><td>${result.counts?.passed ?? "UNAVAILABLE"}</td><td>${result.counts?.failed ?? "UNAVAILABLE"}</td><td>${result.counts?.skipped ?? "UNAVAILABLE"}</td></tr>`).join("\n");
  const testSources: { name: string; runnerStatus: EvidenceStatus; status: EvidenceStatus; total: number | null;
    outcomes: TestOutcome[] | null; identities?: { id: string; status: string }[] | null }[] = [
    ...report.trx.map(result => {
      const suite = report.dotnetTests.find(item => item.id === `${result.project}-tests`);
      return { name: `${result.project} foundation`, runnerStatus: report.foundations.checks.find(check => check.name === `${result.project}-tests`)?.status ?? "BLOCKED",
        status: suite?.status ?? result.status, total: suite?.observed ?? null,
        outcomes: suite ? suite.tests.map(item => item.status === "PASS" ? "PASS" as const
          : item.status === "FAIL" ? "FAIL" as const : item.status === "SKIPPED" ? "NOT-EXECUTED" as const : "PENDING" as const) : result.outcomes,
        identities: suite?.tests.map(item => ({ id: item.id, status: item.status })) };
    }),
    { name: "Frontend", runnerStatus: report.foundations.checks.find(check => check.name === "frontend-tests")?.status ?? "BLOCKED",
      status: report.frontend.status, total: report.frontend.counts?.total ?? null, outcomes: report.frontend.outcomes,
      identities: report.frontend.identities?.map(item => ({ id: item.id, status: item.status })) },
    { name: "Integration", runnerStatus: report.steps.find(step => step.name === "integration")?.status ?? "BLOCKED",
      status: report.integration.status, total: report.integration.counts?.total ?? null, outcomes: report.integration.outcomes },
    ...FOUNDATION_AUTOMATION_TEST_CHECKS.map(name => {
      const suite = report.automation.find(item => item.id === name);
      return { name, runnerStatus: report.foundations.checks.find(check => check.name === name)?.status ?? "BLOCKED",
        status: suite?.status ?? "BLOCKED",
        total: suite?.observed ?? null,
        outcomes: suite ? suite.tests.map(item => item.status === "PASS" ? "PASS" as const
          : item.status === "FAIL" ? "FAIL" as const : item.status === "SKIPPED" ? "NOT-EXECUTED" as const : "PENDING" as const) : null,
        identities: suite?.tests.map(item => ({ id: item.id, status: item.status })) };
    })
  ];
  const testSourceRows = testSources.map(source =>
    `<tr><td>${source.name}</td><td>${source.runnerStatus}</td><td>${source.status}</td><td>${source.total ?? "UNAVAILABLE"}</td></tr>`).join("\n");
  const individualOutcomes = testSources.map(source => source.outcomes === null || source.total === null
    ? `<details><summary>${source.name}: UNAVAILABLE</summary><p>No reconciled individual outcomes.</p></details>`
    : `<details><summary>${source.name}: showing ${source.outcomes.length} of ${source.total} outcomes</summary><ol>${source.identities
      ? source.identities.map(outcome => `<li>${escapeHtml(outcome.id)} — ${outcome.status}</li>`).join("")
      : source.outcomes.map(outcome => `<li>${outcome}</li>`).join("")}</ol></details>`).join("\n");
  const coverageRows = report.backendCoverage.map(({ project, coverage }) => coverage.state === "MEASURED"
    ? `<tr><td>${project}</td><td>${coverage.lines.covered}/${coverage.lines.total} (${(100 * coverage.lines.covered / coverage.lines.total).toFixed(2)}%)</td><td>${coverage.branches.covered}/${coverage.branches.total} (${(100 * coverage.branches.covered / coverage.branches.total).toFixed(2)}%)</td></tr>`
    : `<tr><td>${project}</td><td>UNAVAILABLE</td><td>UNAVAILABLE</td></tr>`).join("\n");
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Phase 10 report preview</title></head>
<body><h1>Phase 10 report preview</h1>
<p>Contract version: ${report.version}; Run ID: ${escapeHtml(report.runId ?? "UNKNOWN")}</p>
<p>Overall: ${report.overall}. This preview is incomplete and cannot certify L5-R, L5/L6 or a current revision.</p>
<p>Finalization: INCOMPLETE / UNVERIFIED in this static preview. All displayed statuses are provisional; verify the completion record separately before using run evidence.</p>
<p>Packet-reported status: ${report.packetStatus}. Image identity: ${report.imageIdentities.status} — ${escapeHtml(report.imageIdentities.detail)}</p>
<h2>Docker image identities</h2><p>Local image IDs identify the images observed by Docker; repository digests, when present, do not by themselves prove a registry publication. This preview is provisional and cannot certify acceptance.</p>
<table><thead><tr><th>Project / service</th><th>Image reference</th><th>Local image ID</th><th>Repository digests</th></tr></thead><tbody>${report.imageIdentities.services.map(image =>
    `<tr><td>${escapeHtml(image.project)}/${escapeHtml(image.service)}</td><td>${escapeHtml(image.imageReference)}</td><td>${escapeHtml(image.imageId)}</td><td>${escapeHtml(image.repositoryDigests.join(", ") || "Not available")}</td></tr>`
  ).join("\n") || '<tr><td colspan="4">UNKNOWN — no valid bound image manifests.</td></tr>'}</tbody></table>
<h2>Recorded Git provenance</h2>
<p>At start: ${report.git.start.commit ?? "UNKNOWN"}; worktree: ${report.git.start.worktree}.</p>
<p>At finish: ${report.git.finish.commit ?? "UNKNOWN"}; worktree: ${report.git.finish.worktree}.</p>
<p>These are Git observations only. They do not identify built or running images, prove the contents of a dirty worktree, or establish that files remained unchanged during the run.</p>
<p>Profile: ${report.profile}; payment suite: ${report.paymentSuite}; started: ${report.startedUtc ?? "UNKNOWN"}; finished: ${report.finishedUtc ?? "UNKNOWN"}.</p>
<p>Fixture restoration: ${report.restoration}; storage exit evidence: ${report.storage}.</p>
<p>Raw test names, durations, failure details, raw artifact links, integration expected-test discovery, and the complete Phase 10 inventory: NOT COLLECTED.</p>
${coverageSummaryAvailable ? '<p><a href="phase10-coverage-summary.json">Sanitized aggregate coverage summary (JSON)</a>. This file is provisional; verify the completion record before using it.</p>' : ''}
<h2>Inventory reconciliation</h2>
<p>Fixed inventory counts, not individual test totals or acceptance gates. Packet step selection is independent of status; NOT-SELECTED and UNKNOWN are not failures or proof of coverage. Duplicates are BLOCKED; failures in conflicting entries still affect the overall result.</p>
<p>Docker packet steps: ${report.steps.length}; ${statusSummary(report.steps)}.</p>
<p>Packet selection: SELECTED: ${report.steps.filter(step => step.selection === "SELECTED").length}; NOT-SELECTED: ${report.steps.filter(step => step.selection === "NOT-SELECTED").length}; UNKNOWN: ${report.steps.filter(step => step.selection === "UNKNOWN").length}.</p>
<p>Foundation runner checks: ${report.foundations.checks.length}; ${statusSummary(report.foundations.checks)}.</p>
<p>These inventories do not include every Phase 10 suite, test or independent gate and must not be added together.</p>
<h2>Docker packet steps</h2><p>Selection is shown only where the run summary records it; UNKNOWN does not mean optional.</p><table><thead><tr><th>Step</th><th>Selection</th><th>Status</th></tr></thead><tbody>${rows}</tbody></table>
<h2>Foundation checks</h2><p>These are runner checks, not individual test counts.</p><table><thead><tr><th>Check</th><th>Status</th></tr></thead><tbody>${foundationRows}</tbody></table>
<h2>Expected test-result sources</h2><p>These fixed sources are only a subset of Phase 10 suites. Six automation suites reconcile against a versioned expected-test inventory and stable hashed test IDs; inventory hash mismatch, missing, duplicate, unexpected or non-passing outcomes block that suite. The remaining sources reconcile recorded individual outcomes and counters but do not have a complete expected-test inventory; omitted tests cannot be detected from counts alone. Runner status is separate from result status.</p>
<p>Versioned automation cases: ${report.automation.reduce((sum, suite) => sum + suite.expected, 0)} expected; ${report.automation.reduce((sum, suite) => sum + (suite.observed ?? 0), 0)} observed. Inventory/result completeness is separate from whether the cases passed.</p>
<p>Discovered .NET cases: ${report.dotnetTests.reduce((sum, suite) => sum + suite.expected, 0)} expected; ${report.dotnetTests.reduce((sum, suite) => sum + (suite.observed ?? 0), 0)} observed across five foundation suites plus integration. IDs are hashes of discovered test names; raw names are not emitted.</p>
<p>Frontend cases: ${report.frontend.identities?.length ?? "UNAVAILABLE"} stable hashed identities; the Vitest reporter reconciles its collected case inventory with emitted outcomes.</p>
<table><thead><tr><th>Source</th><th>Runner status</th><th>Result status</th><th>Observed tests</th></tr></thead><tbody>${testSourceRows}</tbody></table>
<h3>Sanitized individual outcomes</h3><p>Automation test IDs are stable hashes, not test names. Other source outcomes remain anonymous input-order positions. At most ${MAX_DISPLAYED_TEST_OUTCOMES} outcomes per source are shown; counts remain for all reconciled results. UNAVAILABLE is not zero tests.</p>
${individualOutcomes}
<h2>Foundation TRX counts</h2><p>Counts are per project, not a complete run total. Time-window matching does not prove revision identity.</p><table><thead><tr><th>Project</th><th>Status</th><th>Total</th><th>Passed</th><th>Failed</th><th>Not executed</th></tr></thead><tbody>${trxRows}</tbody></table>
<h2>Backend foundation coverage</h2><p>Per test project, not a merged total; measured assemblies can overlap. Branch totals shown here are Coverlet XML root totals; detailed HTML counts only branches attached to source lines and may differ. Timestamp matching does not prove revision identity. No threshold or deployed-service coverage is implied.</p><table><thead><tr><th>Test project</th><th>Lines</th><th>Branches</th></tr></thead><tbody>${coverageRows}</tbody></table>
<h2>Integration TRX</h2><p>Status: ${report.integration.status}; total: ${report.integration.counts?.total ?? "UNAVAILABLE"}; passed: ${report.integration.counts?.passed ?? "UNAVAILABLE"}; failed: ${report.integration.counts?.failed ?? "UNAVAILABLE"}; not executed: ${report.integration.counts?.skipped ?? "UNAVAILABLE"}. Only the overall run window is available; this does not prove run or revision identity.</p>
<h2>Integration test-process coverage</h2>${report.integrationCoverage.state === "MEASURED"
    ? `<p>Lines: ${report.integrationCoverage.lines.covered}/${report.integrationCoverage.lines.total} (${(100 * report.integrationCoverage.lines.covered / report.integrationCoverage.lines.total).toFixed(2)}%); branches: ${report.integrationCoverage.branches.covered}/${report.integrationCoverage.branches.total} (${(100 * report.integrationCoverage.branches.covered / report.integrationCoverage.branches.total).toFixed(2)}%).</p>`
    : "<p>UNAVAILABLE: no valid same-window coverage for a passing integration run.</p>"}
<p>Test-process coverage only; not merged with foundation tests or deployed-service coverage. Run-window timestamps do not prove run or revision identity.</p>
<h2>Frontend Vitest</h2><p>Status: ${report.frontend.status}; total: ${report.frontend.counts?.total ?? "UNAVAILABLE"}; passed: ${report.frontend.counts?.passed ?? "UNAVAILABLE"}; failed: ${report.frontend.counts?.failed ?? "UNAVAILABLE"}; pending: ${report.frontend.counts?.pending ?? "UNAVAILABLE"}; todo: ${report.frontend.counts?.todo ?? "UNAVAILABLE"}.</p>
<h2>Frontend unit-test coverage</h2>${report.frontendCoverage.state === "MEASURED"
    ? `<p>Lines: ${report.frontendCoverage.lines.covered}/${report.frontendCoverage.lines.total} (${(100 * report.frontendCoverage.lines.covered / report.frontendCoverage.lines.total).toFixed(2)}%); branches: ${report.frontendCoverage.branches.covered}/${report.frontendCoverage.branches.total} (${(100 * report.frontendCoverage.branches.covered / report.frontendCoverage.branches.total).toFixed(2)}%).</p>`
    : "<p>UNAVAILABLE: no valid same-window coverage for a passing frontend test run.</p>"}
<p>Scope: web app source, excluding tests and declarations; no thresholds or deployment coverage are implied. Timestamp matching does not prove run or revision identity.</p>
<h2>Issues</h2><ul>${issues || "<li>None detected by this limited preview.</li>"}</ul>
</body></html>\n`;
}
