import { createHash } from "node:crypto";
import inventory from "../../config/phase10-automation-test-inventory.json" with { type: "json" };
import type { EvidenceStatus } from "./phase10-report.js";

export type AutomationTestStatus = "PASS" | "FAIL" | "SKIPPED" | "BLOCKED";
export interface AutomationSuiteReport {
  id: string;
  status: EvidenceStatus;
  runnerStatus: EvidenceStatus;
  expected: number;
  observed: number | null;
  tests: { id: string; status: AutomationTestStatus }[];
}

export function normalizeDiscoveredDotnetSuite(input: unknown, project: string,
  trx: { status: EvidenceStatus; counts: { total: number; passed: number; failed: number; skipped: number } | null;
    identities?: { id: string; status: string }[] | null },
  window: { startedUtc: string; finishedUtc: string } | null): AutomationSuiteReport {
  const blocked = (): AutomationSuiteReport => ({ id: `${project}-tests`, status: "BLOCKED", runnerStatus: "BLOCKED",
    expected: 0, observed: null, tests: [] });
  if (!window || input === null || typeof input !== "object" || Array.isArray(input)) return blocked();
  const value = input as Record<string, unknown>;
  if (value.schema !== "phase10-dotnet-test-results-v1" || value.project !== project ||
      !Number.isInteger(value.runnerExitCode) || !Array.isArray(value.expectedIds) || !Array.isArray(value.tests) ||
      typeof value.assemblySha256 !== "string" || !/^[a-f0-9]{64}$/.test(value.assemblySha256) ||
      typeof value.inventorySha256 !== "string" || !/^[a-f0-9]{64}$/.test(value.inventorySha256) ||
      typeof value.startedUtc !== "string" || typeof value.finishedUtc !== "string" ||
      !Number.isFinite(Date.parse(value.startedUtc)) || !Number.isFinite(Date.parse(value.finishedUtc)) ||
      Date.parse(value.startedUtc) < Date.parse(window.startedUtc) || Date.parse(value.finishedUtc) > Date.parse(window.finishedUtc) ||
      Date.parse(value.finishedUtc) < Date.parse(value.startedUtc)) return blocked();
  const runnerStatus: EvidenceStatus = value.runnerExitCode === 0 ? "PASS" : "FAIL";
  const expected = value.expectedIds as unknown[];
  const testsRaw = value.tests as unknown[];
  const ids = expected.filter((id): id is string => typeof id === "string");
  const tests = testsRaw.map(item => item !== null && typeof item === "object" && !Array.isArray(item)
    ? item as Record<string, unknown> : undefined);
  const observedIds = tests.map(item => item?.id);
  const validExpected = ids.length === expected.length && ids.length > 0 &&
    new Set(ids).size === ids.length && ids.every(id => new RegExp(`^${project}:[a-f0-9]{64}$`).test(id));
  const expectedFingerprint = createHash("sha256").update([...ids].sort().join("\n"), "utf8").digest("hex");
  const validObserved = tests.length === ids.length && new Set(observedIds).size === observedIds.length &&
    ids.every(id => observedIds.filter(observed => observed === id).length === 1) &&
    tests.every(item => item && ["passed", "failed", "skipped"].includes(String(item.status)));
  const passed = tests.filter(item => item?.status === "passed").length;
  const failed = tests.filter(item => item?.status === "failed").length;
  const skipped = tests.filter(item => item?.status === "skipped").length;
  const countsMatch = trx.counts !== null && trx.counts.total === ids.length && trx.counts.passed === passed &&
    trx.counts.failed === failed && trx.counts.skipped === skipped;
  const trxIdentities = trx.identities ?? null;
  const trxIdentityIds = trxIdentities?.map(item => item.id) ?? [];
  const trxStatuses = new Map(trxIdentities?.map(item => [item.id, item.status]) ?? []);
  const identitiesMatch = trxIdentities !== null && trxIdentityIds.length === ids.length &&
    new Set(trxIdentityIds).size === trxIdentityIds.length && ids.every(id => trxStatuses.get(id) ===
      (tests.find(item => item?.id === id)?.status === "passed" ? "PASS"
        : tests.find(item => item?.id === id)?.status === "failed" ? "FAIL" : "NOT-EXECUTED"));
  const exact = validExpected && validObserved && identitiesMatch && expectedFingerprint === value.inventorySha256 && countsMatch &&
    value.expectedCount === ids.length && value.observedCount === tests.length && value.missingCount === 0 &&
    value.unexpectedCount === 0 && value.duplicateCount === 0;
  const complete = exact && value.complete === true && runnerStatus === "PASS" && failed === 0 && skipped === 0;
  const normalizedTests = ids.map(id => {
    const result = tests.find(item => item?.id === id);
    return { id, status: result?.status === "passed" ? "PASS" as const
      : result?.status === "failed" ? "FAIL" as const
        : result?.status === "skipped" ? "SKIPPED" as const : "BLOCKED" as const };
  });
  const anyFailure = runnerStatus === "FAIL" || failed > 0 || trx.status === "FAIL";
  const status: EvidenceStatus = complete ? "PASS" : anyFailure ? "FAIL"
    : exact && value.complete === false && skipped === ids.length ? "SKIPPED"
      : exact && value.complete === false && skipped > 0 ? "PARTIAL" : "BLOCKED";
  return { id: `${project}-tests`, status, runnerStatus, expected: ids.length,
    observed: Number.isInteger(value.observedCount) ? value.observedCount as number : null, tests: normalizedTests };
}

type SuiteInventory = { id: string; file: string; tests: string[] };
const suites = (inventory as { schema: string; suites: SuiteInventory[] }).suites;

export function phase10AutomationInventorySha256(raw: string): string {
  return createHash("sha256").update(raw, "utf8").digest("hex");
}

export function expectedAutomationTests(suiteId: string): { id: string; title: string }[] {
  const suite = suites.find(item => item.id === suiteId);
  if (!suite) return [];
  return suite.tests.map(title => {
    const hash = createHash("sha256").update(`${suiteId}::${title}`, "utf8").digest("hex").slice(0, 16);
    return { id: `${suiteId}:${hash}`, title };
  });
}

export function normalizeAutomationSuite(input: unknown, suiteId: string, inventorySha256: string): AutomationSuiteReport {
  const expected = expectedAutomationTests(suiteId);
  const blocked = (): AutomationSuiteReport => ({ id: suiteId, status: "BLOCKED", runnerStatus: "BLOCKED",
    expected: expected.length, observed: null, tests: expected.map(item => ({ id: item.id, status: "BLOCKED" })) });
  if (!expected.length || input === null || typeof input !== "object" || Array.isArray(input)) return blocked();
  const value = input as Record<string, unknown>;
  if (value.schema !== "phase10-automation-test-results-v1" || value.suiteId !== suiteId ||
      value.inventorySha256 !== inventorySha256 || !Number.isInteger(value.runnerExitCode) ||
      !Array.isArray(value.tests)) return blocked();
  const runnerStatus: EvidenceStatus = value.runnerExitCode === 0 ? "PASS" : "FAIL";
  const results = value.tests.map(item => item !== null && typeof item === "object" && !Array.isArray(item)
    ? item as Record<string, unknown> : undefined);
  const ids = results.map(item => item?.id);
  const validIds = ids.length === expected.length && new Set(ids).size === ids.length &&
    expected.every(item => ids.filter(id => id === item.id).length === 1);
  const validStatuses = results.every(item => item && ["passed", "failed", "skipped", "unavailable"].includes(String(item.status)));
  const reconciled = validIds && validStatuses && value.expectedCount === expected.length &&
    value.observedCount === expected.length && value.missingCount === 0 && value.unexpectedCount === 0 && value.duplicateCount === 0;
  const complete = reconciled && runnerStatus === "PASS" && results.every(item => item?.status === "passed");
  const tests = expected.map(item => {
    const match = results.find(result => result?.id === item.id);
    const testStatus: AutomationTestStatus = match?.status === "passed" ? "PASS"
      : match?.status === "failed" ? "FAIL" : match?.status === "skipped" ? "SKIPPED" : "BLOCKED";
    return { id: item.id, status: testStatus };
  });
  const anyFailure = runnerStatus === "FAIL" || tests.some(item => item.status === "FAIL");
  const statuses = tests.map(item => item.status);
  const status: EvidenceStatus = complete ? "PASS" : anyFailure ? "FAIL"
    : reconciled && value.complete === false && statuses.every(item => item === "SKIPPED") ? "SKIPPED"
      : reconciled && value.complete === false && statuses.some(item => item === "SKIPPED") ? "PARTIAL" : "BLOCKED";
  return { id: suiteId, status, runnerStatus,
    expected: expected.length, observed: Number.isInteger(value.observedCount) ? value.observedCount as number : null, tests };
}

export function normalizeAutomationSuites(inputs: Partial<Record<string, unknown>>, inventorySha256: string): AutomationSuiteReport[] {
  return suites.map(suite => normalizeAutomationSuite(inputs[suite.id], suite.id, inventorySha256));
}
