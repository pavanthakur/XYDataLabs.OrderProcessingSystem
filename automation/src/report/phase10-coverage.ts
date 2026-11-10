import type { EvidenceStatus } from "./phase10-report.js";
import { SaxesParser } from "saxes";

type Counts = { covered: number; total: number };
export type FrontendCoverage = {
  state: "MEASURED";
  lines: Counts;
  branches: Counts;
} | { state: "UNAVAILABLE" };
export type BackendCoverage = FrontendCoverage;

function object(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value)) : undefined;
}

function counts(value: unknown): Counts | undefined {
  const metric = object(value);
  const covered = metric?.covered;
  const total = metric?.total;
  if (typeof covered !== "number" || typeof total !== "number" ||
      !Number.isSafeInteger(covered) || !Number.isSafeInteger(total)) return undefined;
  if (total <= 0 || covered < 0 || covered > total) return undefined;
  return { covered, total };
}

export function parseFrontendCoverage(input: unknown, modifiedUtc: number | undefined,
  window: { startedUtc: string; finishedUtc: string } | null, runner: EvidenceStatus): FrontendCoverage {
  const unavailable: FrontendCoverage = { state: "UNAVAILABLE" };
  if (runner !== "PASS" || !window || modifiedUtc === undefined || !Number.isFinite(modifiedUtc)) return unavailable;
  const start = Date.parse(window.startedUtc);
  const end = Date.parse(window.finishedUtc);
  if (!Number.isFinite(start) || !Number.isFinite(end) || start > end ||
      modifiedUtc < start - 1000 || modifiedUtc > end + 1000) return unavailable;
  const total = object(object(input)?.total);
  const lines = counts(total?.lines);
  const branches = counts(total?.branches);
  return lines && branches ? { state: "MEASURED", lines, branches } : unavailable;
}

export function parseBackendCoverage(xml: string | undefined, modifiedUtc: number | undefined,
  window: { startedUtc: string; finishedUtc: string } | null, runner: EvidenceStatus): BackendCoverage {
  const unavailable: BackendCoverage = { state: "UNAVAILABLE" };
  if (!xml || runner !== "PASS" || !window || modifiedUtc === undefined || !Number.isFinite(modifiedUtc)) return unavailable;
  const start = Date.parse(window.startedUtc);
  const end = Date.parse(window.finishedUtc);
  if (!Number.isFinite(start) || !Number.isFinite(end) || start > end ||
      modifiedUtc < start - 1000 || modifiedUtc > end + 1000) return unavailable;
  let valid = true;
  let depth = 0;
  let rootCount = 0;
  let lines: Counts | undefined;
  let branches: Counts | undefined;
  const parser = new SaxesParser();
  parser.on("doctype", () => { valid = false; });
  parser.on("opentag", tag => {
    depth++;
    if (depth !== 1) return;
    rootCount++;
    if (tag.name !== "coverage") { valid = false; return; }
    const number = (name: string): number | undefined => {
      const value = tag.attributes[name];
      if (typeof value !== "string" || !/^\d+$/.test(value)) return undefined;
      const parsed = Number(value);
      return Number.isSafeInteger(parsed) ? parsed : undefined;
    };
    lines = counts({ covered: number("lines-covered"), total: number("lines-valid") });
    branches = counts({ covered: number("branches-covered"), total: number("branches-valid") });
  });
  parser.on("closetag", () => { depth--; });
  try { parser.write(xml).close(); } catch { return unavailable; }
  return valid && rootCount === 1 && lines && branches ? { state: "MEASURED", lines, branches } : unavailable;
}
