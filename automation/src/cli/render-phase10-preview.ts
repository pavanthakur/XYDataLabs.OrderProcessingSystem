import { lstat, open, readFile, readdir, realpath, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { normalizePhase10Packet, renderPhase10CoverageSummary, renderPhase10Report } from "../report/phase10-report.js";
import { phase10AutomationInventorySha256 } from "../report/phase10-automation.js";
import { hashAzureManifestFiles } from "../report/phase10-evidence-files.js";
import { FOUNDATION_TRX_PROJECTS } from "../report/phase10-trx.js";
import { normalizePaymentMatrix } from "../report/phase10-payment-matrix.js";
import type { PaymentMatrixKind } from "../report/phase10-payment-matrix.js";
import { normalizePhase10PersistenceEvidence } from "../report/phase10-persistence.js";
import { hashNfrEvidence, normalizePhase10NfrEvidence } from "../report/phase10-nfr-evidence.js";
import { normalizePhase10IdentityMatrix } from "../report/phase10-identity-matrix.js";
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

async function readPaymentMatrices(root: string, paymentSuite: unknown): Promise<ReturnType<typeof normalizePaymentMatrix>[]> {
  const paymentRoot = join(root, "payments");
  let directory: Awaited<ReturnType<typeof lstat>> | undefined;
  try { directory = await lstat(paymentRoot); }
  catch (error) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") return [];
    else throw error;
  }
  if (!directory.isDirectory() || directory.isSymbolicLink()) throw new Error("Payment evidence root must be a non-symlink directory.");
  const kinds: PaymentMatrixKind[] = [];
  const selected = paymentSuite === "both" ? ["deterministic", "sandbox-positive"] as const
    : paymentSuite === "deterministic" ? ["deterministic"] as const
      : paymentSuite === "sandbox" ? ["sandbox-positive"] as const : [];
  kinds.push(...selected);
  const discovered = new Map<PaymentMatrixKind, string[]>();
  for (const entry of await readdir(paymentRoot, { withFileTypes: true })) {
    const match = /^payment-acceptance-(deterministic|sandbox-negative|sandbox)-(\d+)$/.exec(entry.name);
    if (!match) continue;
    if (!entry.isDirectory() || entry.isSymbolicLink()) throw new Error("Payment matrix run entries must be non-symlink directories.");
    const kind: PaymentMatrixKind = match[1] === "deterministic" ? "deterministic"
      : match[1] === "sandbox-negative" ? "sandbox-negative" : "sandbox-positive";
    discovered.set(kind, [...(discovered.get(kind) ?? []), join(paymentRoot, entry.name)]);
  }
  for (const kind of ["deterministic", "sandbox-positive", "sandbox-negative"] as const) {
    if (discovered.has(kind) && !kinds.includes(kind)) kinds.push(kind);
  }
  const digest = (value: string | undefined) => value === undefined ? undefined
    : createHash("sha256").update(value, "utf8").digest("hex");
  return Promise.all(kinds.map(async kind => {
    const candidates = discovered.get(kind) ?? [];
    if (candidates.length !== 1) return normalizePaymentMatrix(kind, undefined, undefined);
    const path = candidates[0];
    const summaryText = await readText(path, "summary.json");
    const seedText = await readText(path, "seed-contract.json");
    const parse = (value: string | undefined): unknown => {
      if (value === undefined) return undefined;
      try { return JSON.parse(value) as unknown; } catch (error) { if (error instanceof SyntaxError) return undefined; throw error; }
    };
    return normalizePaymentMatrix(kind, parse(summaryText), parse(seedText), digest(summaryText), digest(seedText));
  }));
}

async function readPersistenceEvidence(root: string, parentSummary: unknown,
  parentImageBefore: unknown, parentImageAfter: unknown): Promise<ReturnType<typeof normalizePhase10PersistenceEvidence>> {
  const persistenceRoot = join(root, "persistence");
  let directory: Awaited<ReturnType<typeof lstat>> | undefined;
  try { directory = await lstat(persistenceRoot); }
  catch (error) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") return normalizePhase10PersistenceEvidence();
    throw error;
  }
  if (!directory.isDirectory() || directory.isSymbolicLink()) throw new Error("Persistence evidence root must be a non-symlink directory.");
  const [summaryText, beforeText, afterText, imageBeforeText, imageAfterText] = await Promise.all([
    readText(persistenceRoot, "summary.json"), readText(persistenceRoot, "before.json"), readText(persistenceRoot, "after.json"),
    readText(persistenceRoot, "docker-image-identities-before.json"), readText(persistenceRoot, "docker-image-identities-after.json")
  ]);
  const parse = (value: string | undefined): unknown => {
    if (value === undefined) return undefined;
    try { return JSON.parse(value) as unknown; } catch (error) { if (error instanceof SyntaxError) return undefined; throw error; }
  };
  const digest = (value: string | undefined) => value === undefined ? undefined : createHash("sha256").update(value, "utf8").digest("hex");
  return normalizePhase10PersistenceEvidence({
    summary: parse(summaryText), before: parse(beforeText), after: parse(afterText),
    beforeTextSha256: digest(beforeText), afterTextSha256: digest(afterText),
    imageBefore: parse(imageBeforeText), imageAfter: parse(imageAfterText),
    imageBeforeSha256: digest(imageBeforeText), imageAfterSha256: digest(imageAfterText),
    parentGitProvenance: (parentSummary as { gitProvenance?: unknown } | undefined)?.gitProvenance,
    parentImageBefore, parentImageAfter
  });
}

async function readNfrEvidence(nfrRunRoot: string | undefined, parentSummary: unknown,
  parentImageBefore: unknown, parentImageAfter: unknown): Promise<ReturnType<typeof normalizePhase10NfrEvidence>> {
  if (!nfrRunRoot) return normalizePhase10NfrEvidence();
  const nfrRoot = join(nfrRunRoot, "nfr");
  const [rootInfo, nfrInfo] = await Promise.all([lstat(nfrRunRoot), lstat(nfrRoot)]);
  if (!rootInfo.isDirectory() || rootInfo.isSymbolicLink() || !nfrInfo.isDirectory() || nfrInfo.isSymbolicLink()) {
    throw new Error("NFR evidence root and nfr child must be non-symlink directories.");
  }
  const names = ["summary.json", "operational-summary.json", "recovery-summary.json", "consumer-outage-drill.json",
    "consumer-outage-drill-probe.json", "rollback-evidence.json", "operational-100-message-durable-consumer-burst.log"];
  const [texts, nfrBeforeText, nfrAfterText] = await Promise.all([
    Promise.all(names.map(name => readText(nfrRoot, name))),
    readText(nfrRunRoot, "docker-image-identities-before.json"), readText(nfrRunRoot, "docker-image-identities-after.json")
  ]);
  const parse = (value: string | undefined): unknown => {
    if (value === undefined) return undefined;
    try { return JSON.parse(value) as unknown; } catch (error) { if (error instanceof SyntaxError) return undefined; throw error; }
  };
  const evidenceSha256 = hashNfrEvidence([...names.map((name, index) => ({ name, text: texts[index] })),
    { name: "docker-image-identities-before.json", text: nfrBeforeText },
    { name: "docker-image-identities-after.json", text: nfrAfterText }]);
  return normalizePhase10NfrEvidence({
    summary: parse(texts[0]), operationalSummary: parse(texts[1]), recoverySummary: parse(texts[2]),
    recoveryDrill: parse(texts[3]), recoveryProbe: parse(texts[4]), rollback: parse(texts[5]), burstLog: texts[6],
    nfrImageBefore: parse(nfrBeforeText), nfrImageAfter: parse(nfrAfterText),
    parentGitProvenance: (parentSummary as { gitProvenance?: unknown } | undefined)?.gitProvenance,
    parentImageBefore, parentImageAfter, evidenceSha256
  });
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
  let azureEvidenceRoot: string | undefined;
  let nfrEvidenceRoot: string | undefined;
  let outputDirectory: string | undefined;
  const runDirectory = args.shift();
  while (args.length) {
    const option = args.shift();
    const value = args.shift();
    if (!value || (option !== "--azure-evidence" && option !== "--nfr-evidence" && option !== "--output-directory")) {
      throw new Error("Usage: npm --prefix automation run report:phase10-preview -- <run-directory> [--output-directory <new-report-directory>] [--azure-evidence <artifact-directory>] [--nfr-evidence <run-artifact-directory>]");
    }
    if (option === "--azure-evidence") {
      if (azureEvidenceRoot) throw new Error("Azure evidence may be specified only once.");
      const info = await lstat(value);
      if (!info.isDirectory() || info.isSymbolicLink()) throw new Error("Azure evidence path must be a non-symlink directory.");
      azureEvidenceRoot = await realpath(value);
    } else if (option === "--nfr-evidence") {
      if (nfrEvidenceRoot) throw new Error("NFR evidence may be specified only once.");
      const info = await lstat(value);
      if (!info.isDirectory() || info.isSymbolicLink()) throw new Error("NFR evidence path must be a non-symlink directory.");
      nfrEvidenceRoot = await realpath(value);
    } else {
      if (outputDirectory) throw new Error("Report output directory may be specified only once.");
      const info = await lstat(value);
      if (!info.isDirectory() || info.isSymbolicLink()) throw new Error("Report output path must be an existing non-symlink directory.");
      outputDirectory = await realpath(value);
    }
  }
  if (!runDirectory) throw new Error("A Docker report run directory is required.");
  const info = await lstat(runDirectory);
  if (!info.isDirectory() || info.isSymbolicLink()) throw new Error("Run directory must be a non-symlink directory.");
  const root = await realpath(runDirectory);
  const azureIntegrity = azureEvidenceRoot ? await hashAzureManifestFiles(azureEvidenceRoot) : undefined;
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
  const dockerImageBefore = await readEvidence(root, "docker-image-identities-before.json");
  const dockerImageAfter = await readEvidence(root, "docker-image-identities-after.json");
  const persistenceEvidence = await readPersistenceEvidence(root, summary, dockerImageBefore, dockerImageAfter);
  const nfrEvidence = await readNfrEvidence(nfrEvidenceRoot, summary, dockerImageBefore, dockerImageAfter);
  let identitySummary: unknown;
  try {
    const identityRoot = join(root, "customer-directory");
    const identityDirectory = await lstat(identityRoot);
    if (!identityDirectory.isDirectory() || identityDirectory.isSymbolicLink()) {
      reportInputIssues.push("Tenant identity evidence directory is not a safe directory.");
    } else identitySummary = await readEvidence(identityRoot, "summary.json");
  } catch (error) {
    if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error;
  }
  const identityMatrix = normalizePhase10IdentityMatrix(identitySummary, await readEvidence(root, "seed-contract.json"));
  const report = normalizePhase10Packet(packet, summary, foundations, trx,
    { integrationTrx, integrationDuplicate, integrationCoverage, frontend, frontendCoverage, frontendCoverageModifiedUtc,
      backendCoverage, automation, automationInventorySha256, dotnetTests, reportInputIssues,
      paymentMatrices: await readPaymentMatrices(root, (summary as { paymentSuite?: unknown } | undefined)?.paymentSuite),
      dockerImageBefore, dockerImageAfter, persistenceEvidence, nfrEvidence, identityMatrix,
      azureEvidence: azureEvidenceRoot ? {
        evidenceManifest: azureIntegrity?.manifest,
        actualEvidenceFiles: azureIntegrity?.files,
        deployment: azureIntegrity?.evidence["deployment-identity.json"],
        runtime: azureIntegrity?.evidence["runtime-smoke.json"],
        identity: azureIntegrity?.evidence["identity.json"],
        payments: azureIntegrity?.evidence["payment-matrix-summary.json"],
        transport: azureIntegrity?.evidence["transport-smoke.json"],
        transportFunctions: azureIntegrity?.evidence["functions-replay.json"],
        recovery: azureIntegrity?.evidence["recovery-nfr.json"],
        rollback: azureIntegrity?.evidence["rollback.json"],
        restoration: azureIntegrity?.evidence["restoration.json"]
      } : undefined });
  const destination = outputDirectory ?? root;
  const output = join(destination, "phase10-preview.html");
  const indexOutput = join(destination, "index.html");
  const coverageOutput = join(destination, "phase10-coverage-summary.json");
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
