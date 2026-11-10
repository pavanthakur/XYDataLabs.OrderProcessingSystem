import { lstat, open, readFile, readdir, realpath, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { normalizePhase10Packet, renderPhase10CoverageSummary, renderPhase10Report } from "../report/phase10-report.js";
import { phase10AutomationInventorySha256 } from "../report/phase10-automation.js";
import { FOUNDATION_TRX_PROJECTS } from "../report/phase10-trx.js";
import type { TrxProject, TrxSuite } from "../report/phase10-trx.js";

async function readText(root: string, name: string): Promise<string | undefined> {
  const path = join(root, name);
  try {
    const info = await lstat(path);
    if (!info.isFile() || info.isSymbolicLink() || info.size > 2 * 1024 * 1024) return undefined;
    return await readFile(path, "utf8");
  } catch (error) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") return undefined;
    throw error;
  }
}

async function readEvidence(root: string, name: string): Promise<unknown> {
  const text = await readText(root, name);
  if (text === undefined) return undefined;
  try { return JSON.parse(text) as unknown; } catch (error) {
    if (error instanceof SyntaxError) return undefined;
    throw error;
  }
}

async function readCollectorCoverage(root: string): Promise<{ xml: string; modifiedUtc: number } | undefined> {
  const directory = await lstat(root);
  if (!directory.isDirectory() || directory.isSymbolicLink()) return undefined;
  const entries = await readdir(root, { withFileTypes: true });
  const candidates: ({ xml: string; modifiedUtc: number } | null)[] = [];
  for (const entry of entries) {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(entry.name)) continue;
    if (!entry.isDirectory() || entry.isSymbolicLink()) {
      candidates.push(null);
      continue;
    }
    const resultRoot = join(root, entry.name);
    const info = await lstat(join(resultRoot, "coverage.cobertura.xml")).catch((error: unknown) => {
      if (error instanceof Error && "code" in error && error.code === "ENOENT") return undefined;
      throw error;
    });
    if (!info) continue;
    if (!info.isFile() || info.isSymbolicLink() || info.size > 2 * 1024 * 1024) {
      candidates.push(null);
      continue;
    }
    const xml = await readText(resultRoot, "coverage.cobertura.xml");
    candidates.push(xml === undefined ? null : { xml, modifiedUtc: info.mtimeMs });
  }
  return candidates.length === 1 && candidates[0] !== null ? candidates[0] : undefined;
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.length !== 1) throw new Error("Usage: npm --prefix automation run report:phase10-preview -- <run-directory>");
  const info = await lstat(args[0]);
  if (!info.isDirectory() || info.isSymbolicLink()) throw new Error("Run directory must be a non-symlink directory.");
  const root = await realpath(args[0]);
  const packet = await readEvidence(root, "acceptance-packet.json");
  const summary = await readEvidence(root, "run-summary.json");
  let foundations: unknown;
  let frontend: unknown;
  let frontendCoverage: unknown;
  let frontendCoverageModifiedUtc: number | undefined;
  let integrationTrx: string | undefined;
  let integrationDuplicate = false;
  let integrationCoverage: { xml: string; modifiedUtc: number } | undefined;
  const trx: Partial<Record<TrxProject, string>> = {};
  const backendCoverage: Partial<Record<TrxProject, { xml: string; modifiedUtc: number }>> = {};
  const dotnetTests: Partial<Record<TrxSuite, unknown>> = {};
  const inventoryPath = fileURLToPath(new URL("../../config/phase10-automation-test-inventory.json", import.meta.url));
  const inventoryText = await readFile(inventoryPath, "utf8");
  const automationInventorySha256 = phase10AutomationInventorySha256(inventoryText);
  let foundationsRoot = root;
  try {
    const candidate = join(root, "foundations");
    const info = await lstat(candidate);
    if (info.isDirectory() && !info.isSymbolicLink()) foundationsRoot = candidate;
  } catch (error) {
    if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error;
  }
  let automation: Partial<Record<string, unknown>> = {};
  const reportInputIssues: string[] = [];
  try {
    const automationRoot = join(foundationsRoot, "automation-tests");
    const directory = await lstat(automationRoot);
    if (directory.isDirectory() && !directory.isSymbolicLink()) {
      const inventory = JSON.parse(inventoryText) as { suites?: { id: string }[] };
      const expectedFiles = new Set((inventory.suites ?? []).map(suite => `${suite.id}.json`));
      for (const entry of await readdir(automationRoot)) if (!expectedFiles.has(entry)) reportInputIssues.push("Unexpected automation result artifact is present.");
      for (const suite of inventory.suites ?? []) automation[suite.id] = await readEvidence(automationRoot, `${suite.id}.json`);
    }
  } catch (error) {
    if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error;
  }
  try {
    const directory = await lstat(foundationsRoot);
    if (directory.isDirectory() && !directory.isSymbolicLink()) {
      const expectedTrx = new Set(FOUNDATION_TRX_PROJECTS.map(project => `${project}.trx`));
      for (const entry of await readdir(foundationsRoot)) {
        if (/\.trx$/i.test(entry) && !expectedTrx.has(entry)) reportInputIssues.push("Unexpected foundation TRX artifact is present.");
      }
      foundations = await readEvidence(foundationsRoot, "summary.json");
      frontend = await readEvidence(foundationsRoot, "frontend-vitest.json");
      try {
        const coverageRoot = join(foundationsRoot, "frontend-coverage");
        const coverageDirectory = await lstat(coverageRoot);
        if (coverageDirectory.isDirectory() && !coverageDirectory.isSymbolicLink()) {
          const coveragePath = join(coverageRoot, "coverage-summary.json");
          const coverageFile = await lstat(coveragePath);
          if (coverageFile.isFile() && !coverageFile.isSymbolicLink() && coverageFile.size <= 2 * 1024 * 1024) {
            frontendCoverage = await readEvidence(coverageRoot, "coverage-summary.json");
            frontendCoverageModifiedUtc = coverageFile.mtimeMs;
          }
        }
      } catch (error) {
        if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error;
      }
      for (const project of FOUNDATION_TRX_PROJECTS) {
        trx[project] = await readText(foundationsRoot, `${project}.trx`);
        try {
          const coverageRoot = join(foundationsRoot, "backend-coverage");
          const coverageDir = await lstat(coverageRoot);
          const projectRoot = join(coverageRoot, project);
          const projectDir = await lstat(projectRoot);
          if (!coverageDir.isDirectory() || coverageDir.isSymbolicLink() ||
              !projectDir.isDirectory() || projectDir.isSymbolicLink()) continue;
          backendCoverage[project] = await readCollectorCoverage(projectRoot);
        } catch (error) {
          if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error;
        }
      }
    }
  } catch (error) {
    if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error;
  }
  try {
    const dotnetRoot = join(foundationsRoot, "dotnet-tests");
    const directory = await lstat(dotnetRoot);
    if (directory.isDirectory() && !directory.isSymbolicLink()) {
      const expectedFiles = new Set(FOUNDATION_TRX_PROJECTS.map(project => `${project}.json`));
      for (const entry of await readdir(dotnetRoot)) if (!expectedFiles.has(entry)) reportInputIssues.push("Unexpected .NET result artifact is present.");
      for (const project of FOUNDATION_TRX_PROJECTS) dotnetTests[project] = await readEvidence(dotnetRoot, `${project}.json`);
    }
  } catch (error) {
    if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error;
  }
  try {
    const directory = await lstat(join(root, "integration"));
    if (directory.isDirectory() && !directory.isSymbolicLink()) {
      const integrationRoot = join(root, "integration");
      const integrationEntries = await readdir(integrationRoot);
      const allTrxEntries = integrationEntries.filter(name => /\.trx$/i.test(name));
      const entries = allTrxEntries.filter(name => /^integration-\d+\.trx$/i.test(name));
      integrationDuplicate = allTrxEntries.some(name => !/^integration-1\.trx$/i.test(name)) ||
        entries.length > 1 || (entries.length === 1 && entries[0] !== "integration-1.trx");
      if (integrationDuplicate) reportInputIssues.push("Unexpected or duplicate integration TRX artifact is present.");
      if (!integrationDuplicate && entries.length === 1) integrationTrx = await readText(join(root, "integration"), entries[0]);
      const inventoryFiles = integrationEntries.filter(name => /^integration-\d+\.json$/i.test(name));
      if (inventoryFiles.length > 1 || (inventoryFiles.length === 1 && inventoryFiles[0] !== "integration-1.json")) {
        reportInputIssues.push("Unexpected or duplicate integration inventory artifact is present.");
      }
      if (!integrationDuplicate && inventoryFiles.length === 1 && inventoryFiles[0] === "integration-1.json") {
        dotnetTests.Integration = await readEvidence(integrationRoot, "integration-1.json");
      }
      const coverageEntries = (await readdir(join(root, "integration"))).filter(name => /^coverage-\d+$/i.test(name));
      if (!integrationDuplicate && entries.length === 1 && coverageEntries.length === 1 && coverageEntries[0] === "coverage-1") {
        integrationCoverage = await readCollectorCoverage(join(root, "integration", "coverage-1"));
      }
    }
  } catch (error) {
    if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error;
  }
  const report = normalizePhase10Packet(packet, summary, foundations, trx,
    { integrationTrx, integrationDuplicate, integrationCoverage, frontend, frontendCoverage, frontendCoverageModifiedUtc,
      backendCoverage, automation, automationInventorySha256, dotnetTests, reportInputIssues });
  const output = join(root, "phase10-preview.html");
  const indexOutput = join(root, "index.html");
  const coverageOutput = join(root, "phase10-coverage-summary.json");
  const preview = await open(output, "wx");
  let index;
  try {
    index = await open(indexOutput, "wx");
    await writeFile(coverageOutput, renderPhase10CoverageSummary(report), { encoding: "utf8", flag: "wx" });
    const html = renderPhase10Report(report, true);
    await preview.writeFile(html, "utf8");
    await index.writeFile(html, "utf8");
  } finally {
    await preview.close();
    await index?.close();
  }
  console.log(`Offline report written: ${indexOutput} (preview alias: ${output}). Evidence status: ${report.overall}; this is not acceptance.`);
}

main().catch((error: unknown) => {
  console.error("Could not generate Phase 10 preview:", error instanceof Error ? error.message : "unknown error");
  process.exitCode = 1;
});
