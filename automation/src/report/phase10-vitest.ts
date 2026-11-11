import type { EvidenceStatus } from "./phase10-report.js";
import { MAX_DISPLAYED_TEST_OUTCOMES } from "./phase10-trx.js";
import type { TestOutcome } from "./phase10-trx.js";
import { createHash } from "node:crypto";

export interface VitestResult {
  status: EvidenceStatus;
  counts: { total: number; passed: number; failed: number; pending: number; todo: number } | null;
  outcomes: TestOutcome[] | null;
  identities: { id: string; status: TestOutcome }[] | null;
}

function object(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value)) : undefined;
}

export function parseVitest(input: unknown, window: { startedUtc: string; finishedUtc: string } | null, check: EvidenceStatus): VitestResult {
  const unavailable: VitestResult = { status: "BLOCKED", counts: null, outcomes: null, identities: null };
  const report = object(input);
  if (!report || !window || (check !== "PASS" && check !== "FAIL")) return unavailable;
  const start = Date.parse(window.startedUtc);
  const finish = Date.parse(window.finishedUtc);
  if (!Number.isFinite(start) || !Number.isFinite(finish) || start > finish ||
      typeof report.startTime !== "number" || !Number.isFinite(report.startTime) || report.startTime < start || report.startTime > finish) return unavailable;
  const counts = { total: 0, passed: 0, failed: 0, pending: 0, todo: 0 };
  const outcomes: TestOutcome[] = [];
  const addState = (state: unknown): boolean => {
    let outcome: TestOutcome;
    if (state === "passed") { counts.passed++; outcome = "PASS"; }
    else if (state === "failed") { counts.failed++; outcome = "FAIL"; }
    else if (state === "pending") { counts.pending++; outcome = "PENDING"; }
    else if (state === "todo") { counts.todo++; outcome = "TODO"; }
    else return false;
    counts.total++;
    if (outcomes.length < MAX_DISPLAYED_TEST_OUTCOMES) outcomes.push(outcome);
    return true;
  };
  if (report.schema === "phase10-vitest-sanitized-v1") {
    if (!Array.isArray(report.states) || typeof report.endTime !== "number" || !Number.isFinite(report.endTime) ||
        report.endTime < report.startTime || report.endTime > finish || typeof report.success !== "boolean" ||
        typeof report.interrupted !== "boolean" || report.interrupted) return unavailable;
    for (const state of report.states) {
      if (!addState(state)) return unavailable;
    }
    if (!counts.total || (report.success && counts.failed > 0) || (check === "PASS" && !report.success) ||
        (check === "FAIL" && report.success)) return unavailable;
    return { status: !report.success || counts.failed ? "FAIL" : counts.pending || counts.todo ? "PARTIAL" : "PASS", counts, outcomes, identities: null };
  }
  if (report.schema === "phase10-vitest-sanitized-v2") {
    if (!Array.isArray(report.states) || !Array.isArray(report.tests) || report.tests.length !== report.states.length ||
        typeof report.endTime !== "number" || !Number.isFinite(report.endTime) || report.endTime < report.startTime ||
        report.endTime > finish || typeof report.success !== "boolean" || typeof report.interrupted !== "boolean" ||
        report.interrupted || typeof report.inventorySha256 !== "string" || !/^[a-f0-9]{64}$/.test(report.inventorySha256)) return unavailable;
    const tests = report.tests.map(object);
    const ids = tests.map(item => item?.id);
    if (tests.some((item, index) => !item || typeof item.id !== "string" || !/^frontend:[a-f0-9]{64}$/.test(item.id) ||
        item.status !== (report.states as unknown[])[index]) || new Set(ids).size !== ids.length ||
        createHash("sha256").update([...ids].sort().join("\n"), "utf8").digest("hex") !== report.inventorySha256) return unavailable;
    for (const state of report.states as unknown[]) if (!addState(state)) return unavailable;
    if (!counts.total || (report.success && counts.failed > 0) || (check === "PASS" && !report.success) ||
        (check === "FAIL" && report.success)) return unavailable;
    const identities = tests.map(item => ({ id: item!.id as string, status: item!.status === "passed" ? "PASS" as const
      : item!.status === "failed" ? "FAIL" as const : item!.status === "todo" ? "TODO" as const
        : item!.status === "pending" || item!.status === "unfinished" ? "PENDING" as const : "PENDING" as const }));
    return { status: !report.success || counts.failed ? "FAIL" : counts.pending || counts.todo ? "PARTIAL" : "PASS", counts, outcomes, identities };
  }
  if (!Array.isArray(report.testResults)) return unavailable;
  for (const rawSuite of report.testResults) {
    const suite = object(rawSuite);
    if (!suite || !Array.isArray(suite.assertionResults) || !["passed", "failed", "pending"].includes(String(suite.status)) ||
        typeof suite.startTime !== "number" || typeof suite.endTime !== "number" ||
        !Number.isFinite(suite.startTime) || !Number.isFinite(suite.endTime) ||
        (suite.status === "failed" && report.success === true) ||
        suite.startTime < start || suite.endTime > finish || suite.startTime > suite.endTime) return unavailable;
    for (const rawTest of suite.assertionResults) {
      const state = object(rawTest)?.status;
      if (!addState(state)) return unavailable;
    }
  }
  if (!counts.total || report.numTotalTests !== counts.total || report.numPassedTests !== counts.passed ||
      report.numFailedTests !== counts.failed || report.numPendingTests !== counts.pending ||
      report.numTodoTests !== counts.todo || typeof report.success !== "boolean" ||
      (report.success && counts.failed > 0) || (check === "PASS" && !report.success) ||
      (check === "FAIL" && report.success)) return unavailable;
  return { status: !report.success || counts.failed ? "FAIL" : counts.pending || counts.todo ? "PARTIAL" : "PASS", counts, outcomes, identities: null };
}
