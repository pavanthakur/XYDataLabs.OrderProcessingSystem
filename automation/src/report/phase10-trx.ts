import { SaxesParser } from "saxes";
import { createHash } from "node:crypto";
import type { EvidenceStatus } from "./phase10-report.js";

export const FOUNDATION_TRX_PROJECTS = ["Domain", "Application", "API", "Gateway", "Architecture"] as const;
export type TrxProject = typeof FOUNDATION_TRX_PROJECTS[number];
export type TrxSuite = TrxProject | "Integration";
export type TestOutcome = "PASS" | "FAIL" | "NOT-EXECUTED" | "PENDING" | "TODO";
export const MAX_DISPLAYED_TEST_OUTCOMES = 100;
export interface TrxResult {
  project: TrxSuite;
  status: EvidenceStatus;
  counts: { total: number; passed: number; failed: number; skipped: number } | null;
  outcomes: TestOutcome[] | null;
  identities: { id: string; status: TestOutcome }[] | null;
}

const namespace = "http://microsoft.com/schemas/VisualStudio/TeamTest/2010";
const guid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function parseFoundationTrx(project: TrxSuite, xml: string | undefined, window: { startedUtc: string; finishedUtc: string } | null, checkStatus: EvidenceStatus): TrxResult {
  const unavailable: TrxResult = { project, status: "BLOCKED", counts: null, outcomes: null, identities: null };
  if (!xml || !window || (checkStatus !== "PASS" && checkStatus !== "FAIL")) return unavailable;
  const parser = new SaxesParser({ xmlns: true });
  const path: string[] = [];
  const executions = new Set<string>();
  const actual = { total: 0, passed: 0, failed: 0, skipped: 0 };
  const outcomes: TestOutcome[] = [];
  const identities: { id: string; status: TestOutcome }[] = [];
  let counters: Record<string, string> | undefined;
  let runStart: number | undefined;
  let runFinish: number | undefined;
  let summaryOutcome: string | undefined;
  let timesCount = 0;
  let summaryCount = 0;
  let resultsCount = 0;
  let valid = true;
  parser.on("doctype", () => { valid = false; });
  parser.on("opentag", tag => {
    path.push(tag.local);
    if (path.length === 1 && (tag.local !== "TestRun" || tag.uri !== namespace)) valid = false;
    if (path.length <= 3 && tag.uri !== namespace) valid = false;
    if (tag.uri !== namespace) return;
    const attr = (name: string): string | undefined => tag.attributes[name]?.value;
    const current = path.join("/");
    if (current === "TestRun/Times") {
      timesCount++;
      runStart = Date.parse(attr("start") ?? "");
      runFinish = Date.parse(attr("finish") ?? "");
    } else if (current === "TestRun/Results") {
      resultsCount++;
    } else if (current === "TestRun/ResultSummary") {
      summaryCount++;
      summaryOutcome = attr("outcome");
    } else if (current === "TestRun/ResultSummary/Counters") {
      if (counters) valid = false;
      counters = Object.fromEntries(Object.entries(tag.attributes).map(([name, value]) => [name, value.value]));
    } else if (current === "TestRun/Results/UnitTestResult") {
      const id = attr("executionId");
      const testName = attr("testName");
      if (!id || !guid.test(id) || executions.has(id.toLowerCase())) valid = false;
      else executions.add(id.toLowerCase());
      if (!testName) valid = false;
      actual.total++;
      let outcome: TestOutcome | undefined;
      switch (attr("outcome")) {
        case "Passed": actual.passed++; outcome = "PASS"; break;
        case "Failed": actual.failed++; outcome = "FAIL"; break;
        case "NotExecuted": actual.skipped++; outcome = "NOT-EXECUTED"; break;
        default: valid = false;
      }
      if (outcome) {
        if (outcomes.length < MAX_DISPLAYED_TEST_OUTCOMES) outcomes.push(outcome);
        if (testName) identities.push({
          id: `${project}:${createHash("sha256").update(testName, "utf8").digest("hex")}`,
          status: outcome
        });
      }
    } else if (path.length === 3 && path[0] === "TestRun" && path[1] === "Results") {
      valid = false;
    }
  });
  parser.on("closetag", () => { path.pop(); });
  try { parser.write(xml).close(); } catch { return unavailable; }
  const numeric = (key: string): number | undefined => {
    const value = counters?.[key];
    if (!value || !/^\d+$/.test(value)) return undefined;
    const number = Number(value);
    return Number.isSafeInteger(number) ? number : undefined;
  };
  const start = Date.parse(window.startedUtc);
  const finish = Date.parse(window.finishedUtc);
  if (!valid || timesCount !== 1 || summaryCount !== 1 || resultsCount !== 1 || actual.total === 0 ||
      runStart === undefined || runFinish === undefined || !Number.isFinite(runStart) || !Number.isFinite(runFinish) ||
      !Number.isFinite(start) || !Number.isFinite(finish) || runStart < start || runFinish > finish || runFinish < runStart ||
      numeric("total") !== actual.total || numeric("passed") !== actual.passed ||
      numeric("failed") !== actual.failed || numeric("notExecuted") !== actual.skipped ||
      numeric("executed") !== actual.passed + actual.failed ||
      ["error", "timeout", "aborted", "inconclusive", "passedButRunAborted", "notRunnable", "disconnected", "warning", "completed", "inProgress", "pending"]
        .some(key => counters?.[key] !== undefined && numeric(key) !== 0) ||
      !["Completed", "Failed"].includes(summaryOutcome ?? "") ||
      (summaryOutcome === "Completed" && actual.failed !== 0) ||
      (checkStatus === "PASS" && (actual.failed !== 0 || summaryOutcome !== "Completed")) ||
      (checkStatus === "FAIL" && actual.failed === 0 && summaryOutcome === "Completed")) return unavailable;
  return { project, status: actual.failed > 0 || summaryOutcome === "Failed" ? "FAIL" : actual.skipped > 0 ? "PARTIAL" : "PASS", counts: actual, outcomes, identities };
}
