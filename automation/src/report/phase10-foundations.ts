import type { EvidenceStatus } from "./phase10-report.js";

// Keep in sync with run-phase10-foundation-tests.ps1.
export const FOUNDATION_CHECKS = [
  "docker-safety", "fixture-regression", "dotnet-inventory-regression", "Domain-tests", "Application-tests",
  "API-tests", "Gateway-tests", "Architecture-tests", "frontend-tests",
  "frontend-typecheck", "automation-typecheck", "test-payment-evidence",
  "test-acceptance-coverage", "test-verification-polling", "test-callbacks",
  "test-callbacks-browser", "test-provider-challenges-browser", "messaging-probe-build"
] as const;

// These runner checks execute Node test suites but do not yet emit structured results.
export const FOUNDATION_AUTOMATION_TEST_CHECKS = [
  "test-payment-evidence", "test-acceptance-coverage", "test-verification-polling",
  "test-callbacks", "test-callbacks-browser", "test-provider-challenges-browser"
] as const;

export interface FoundationReport {
  checks: { name: string; status: EvidenceStatus; window: { startedUtc: string; finishedUtc: string } | null }[];
  issues: string[];
  hasFailure: boolean;
}

function object(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value)) : undefined;
}

function time(value: unknown): number | undefined {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$/.test(value)) return undefined;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

export function normalizeFoundationSummary(input: unknown, runStart: string | null, runEnd: string | null): FoundationReport {
  const summary = object(input);
  const results: unknown[] = Array.isArray(summary?.results) ? summary.results : [];
  const issues: string[] = [];
  if (!summary || !Array.isArray(summary.results) || !["passed", "failed"].includes(String(summary.status))) {
    issues.push("Foundation summary missing or malformed.");
  }
  const start = time(runStart);
  const end = time(runEnd);
  const validRunWindow = start !== undefined && end !== undefined && start <= end;
  if (!validRunWindow) issues.push("Foundation evidence cannot be matched to the run time window.");
  const entries = results.map(object);
  const hasFailure = summary?.status === "failed" || entries.some(entry =>
    entry?.status === "failed" || (typeof entry?.exitCode === "number" && Number.isInteger(entry.exitCode) && entry.exitCode !== 0));
  if (summary?.status === "passed" && hasFailure) issues.push("Foundation summary reports PASS despite a failed check.");
  if (entries.some(entry => !entry || typeof entry.name !== "string" || !FOUNDATION_CHECKS.some(name => name === entry.name))) {
    issues.push("Foundation summary contains an unknown or malformed check.");
  }
  const checks = FOUNDATION_CHECKS.map(name => {
    const matches = entries.filter(entry => entry?.name === name);
    if (matches.length === 0) return { name, status: "NOT-RUN" as const, window: null };
    if (matches.length !== 1) {
      issues.push(`Duplicate foundation check: ${name}.`);
      return { name, status: "BLOCKED" as const, window: null };
    }
    const entry = matches[0]!;
    const checkStart = time(entry.startedUtc);
    const checkEnd = time(entry.finishedUtc);
    const exitValid = typeof entry.exitCode === "number" && Number.isInteger(entry.exitCode);
    const consistent = exitValid && ((entry.status === "passed" && entry.exitCode === 0) ||
      (entry.status === "failed" && entry.exitCode !== 0));
    const inWindow = validRunWindow && checkStart !== undefined && checkEnd !== undefined &&
      checkStart >= start && checkEnd >= checkStart && checkEnd <= end;
    if (!consistent || !inWindow) {
      issues.push(`Invalid or out-of-run foundation evidence: ${name}.`);
      return { name, status: "BLOCKED" as const, window: null };
    }
    return { name, status: entry.status === "passed" ? "PASS" as const : "FAIL" as const,
      window: { startedUtc: new Date(checkStart).toISOString(), finishedUtc: new Date(checkEnd).toISOString() } };
  });
  if (summary?.status === "passed" && checks.some(check => check.status !== "PASS")) {
    issues.push("Foundation summary reports PASS with incomplete or invalid checks.");
  }
  return { checks, issues, hasFailure };
}
