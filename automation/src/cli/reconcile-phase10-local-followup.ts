import { createHash } from "node:crypto";
import { lstat, mkdir, readFile, realpath, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { verifyPhase10Completion } from "../report/phase10-completion.js";
import { reconcilePhase10LocalFollowup, renderPhase10LocalFollowupHtml } from "../report/phase10-local-followup.js";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const testResultsRoot = resolve(repoRoot, "TestResults");
const maxJsonBytes = 2 * 1024 * 1024;
const loadedHashes = new Map<string, string>();

function inside(base: string, path: string): boolean {
  const rel = relative(base, path);
  return rel === "" || (rel !== ".." && !rel.startsWith(".." + sep) && !isAbsolute(rel));
}

async function safePath(path: string, directory = false): Promise<string> {
  const resolved = isAbsolute(path) ? resolve(path) : resolve(repoRoot, path);
  const real = await realpath(resolved);
  const lexicalBase = resolve(testResultsRoot);
  const base = await realpath(lexicalBase);
  if (!inside(lexicalBase, resolved)) throw new Error("Evidence paths must be under TestResults.");
  let cursor = lexicalBase;
  const relativeSegments = relative(lexicalBase, resolved).split(sep).filter(Boolean);
  for (const segment of relativeSegments) {
    cursor = join(cursor, segment);
    const part = await lstat(cursor);
    if (part.isSymbolicLink()) throw new Error("Evidence path components cannot be symlinks.");
  }
  const info = await lstat(resolved);
  if (!inside(base, real) || info.isSymbolicLink() || (directory ? !info.isDirectory() : !info.isFile())) {
    throw new Error("Evidence paths must be regular files/directories under TestResults (symlinks and escapes are rejected).");
  }
  if (!directory && info.size > maxJsonBytes) throw new Error("Evidence JSON exceeds the 2 MiB size limit.");
  return real;
}

async function json(path: string): Promise<unknown> {
  const real = await safePath(path);
  try {
    const bytes = await readFile(real);
    loadedHashes.set(real, createHash("sha256").update(bytes).digest("hex"));
    return JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, "")) as unknown;
  }
  catch (error) { if (error instanceof SyntaxError) throw new Error("Evidence JSON is malformed."); throw error; }
}

function relativeEvidence(path: string): string {
  return relative(repoRoot, path).split(sep).join("/");
}

async function evidence(id: string, path: string): Promise<{ id: string; path: string; sha256: string; realPath: string }> {
  const realPath = await safePath(path);
  const bytes = await readFile(realPath);
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  if (loadedHashes.has(realPath) && loadedHashes.get(realPath) !== sha256) throw new Error("Evidence changed while it was being reconciled.");
  return { id, path: relativeEvidence(realPath), sha256, realPath };
}

async function optionalEvidence(id: string, path: string): Promise<{ id: string; path: string; sha256: string; realPath: string } | undefined> {
  const resolved = isAbsolute(path) ? resolve(path) : resolve(repoRoot, path);
  try { await lstat(resolved); } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") return undefined;
    throw error;
  }
  return evidence(id, path);
}

async function optionalJson(path: string): Promise<unknown | undefined> {
  const resolved = isAbsolute(path) ? resolve(path) : resolve(repoRoot, path);
  try { await lstat(resolved); } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") return undefined;
    throw error;
  }
  return json(path);
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const option = (name: string) => { const index = args.indexOf(name); return index >= 0 ? args[index + 1] : undefined; };
  const e2eArg = option("--e2e");
  const foundationArg = option("--foundation");
  const functionsArg = option("--functions");
  const nfrArg = option("--nfr-root");
  const noPaymentReportArg = option("--no-payment-report");
  const imageArg = option("--image-manifest");
  const operationalRootArg = option("--operational-root");
  const operationalImageArg = option("--operational-image-manifest");
  const persistenceRootArg = option("--persistence-dir");
  const replayRootArg = option("--replay-dir");
  const replayImageArg = option("--replay-image-manifest");
  const outputArg = option("--out");
  if (!e2eArg || !foundationArg || !functionsArg || !nfrArg || !imageArg || !outputArg) {
    throw new Error("Usage: report:phase10-local-followup -- --e2e <run-dir> --no-payment-report <sealed-no-payment-run-dir> --foundation <summary.json> --functions <functions-proof.json> --nfr-root <selected-nfr-dir> --image-manifest <selected-nfr-after.json> --operational-root <ops-nfr-dir> --operational-image-manifest <ops-after.json> --persistence-dir <persistence-run-dir> --replay-dir <replay-evidence-dir> --replay-image-manifest <replay-after.json> --out <new-TestResults-dir>");
  }

  const e2eRoot = await safePath(e2eArg, true);
  const nfrRoot = await safePath(nfrArg, true);
  const noPaymentRoot = noPaymentReportArg ? await safePath(noPaymentReportArg, true) : undefined;
  const operationalRoot = operationalRootArg ? await safePath(operationalRootArg, true) : nfrRoot;
  const persistenceRoot = persistenceRootArg ? await safePath(persistenceRootArg, true) : undefined;
  const replayRoot = replayRootArg ? await safePath(replayRootArg, true) : undefined;
  const e2eFile = (name: string) => join(e2eRoot, name);
  const nfrFile = (name: string) => join(nfrRoot, name);
  const operationalFile = (name: string) => join(operationalRoot, name);
  const persistenceFile = (name: string) => persistenceRoot ? join(persistenceRoot, name) : undefined;
  const replayFile = (name: string) => replayRoot ? join(replayRoot, name) : undefined;
  const e2eCompletion = await verifyPhase10Completion(e2eRoot);
  const [packet, e2eSummary, e2eImage, restorationContract, foundation, functions, nfrRaw, burst, outage, rollback, currentImage,
    paymentSettingsBefore, paymentSettingsAfter, operationsSummary, operationsImage, persistenceSummary, persistenceBefore,
    persistenceAfter, persistenceImageBefore, persistenceImageAfter, replayMessaging, replayRestoration, replayFunctions, replayImage,
    noPaymentSummary, noPaymentPacket, noPaymentCoverage] = await Promise.all([
    json(e2eFile("acceptance-packet.json")), json(e2eFile("run-summary.json")), json(e2eFile("docker-image-identities-after.json")),
    json(e2eFile("restoration-contract.json")), json(foundationArg), json(functionsArg), json(nfrFile("summary.json")),
    optionalJson(operationalFile("operational-100-message-burst.json")), optionalJson(operationalFile("consumer-outage-drill.json")),
    optionalJson(operationalFile("rollback-evidence.json")), json(imageArg),
    optionalJson(nfrFile("payment-settings-before.json")), optionalJson(nfrFile("payment-settings-after.json")),
    optionalJson(operationalFile("summary.json")), operationalImageArg ? optionalJson(operationalImageArg) : Promise.resolve(undefined),
    persistenceFile("summary.json") ? optionalJson(persistenceFile("summary.json")!) : Promise.resolve(undefined),
    persistenceFile("before.json") ? optionalJson(persistenceFile("before.json")!) : Promise.resolve(undefined),
    persistenceFile("after.json") ? optionalJson(persistenceFile("after.json")!) : Promise.resolve(undefined),
    persistenceFile("docker-image-identities-before.json") ? optionalJson(persistenceFile("docker-image-identities-before.json")!) : Promise.resolve(undefined),
    persistenceFile("docker-image-identities-after.json") ? optionalJson(persistenceFile("docker-image-identities-after.json")!) : Promise.resolve(undefined),
    replayFile("messaging-proof.json") ? optionalJson(replayFile("messaging-proof.json")!) : Promise.resolve(undefined),
    replayFile("replay-restoration.json") ? optionalJson(replayFile("replay-restoration.json")!) : Promise.resolve(undefined),
    replayFile("functions-proof.json") ? optionalJson(replayFile("functions-proof.json")!) : Promise.resolve(undefined),
    replayImageArg ? optionalJson(replayImageArg) : Promise.resolve(undefined),
    noPaymentRoot ? optionalJson(join(noPaymentRoot, "run-summary.json")) : Promise.resolve(undefined),
    noPaymentRoot ? optionalJson(join(noPaymentRoot, "acceptance-packet.json")) : Promise.resolve(undefined),
    noPaymentRoot ? optionalJson(join(noPaymentRoot, "phase10-coverage-summary.json")) : Promise.resolve(undefined)
  ]);
  const nfrRecord = nfrRaw !== null && typeof nfrRaw === "object" && !Array.isArray(nfrRaw) ? nfrRaw as Record<string, unknown> : {};
  const nfr = { ...nfrRecord, paymentSettingsBefore, paymentSettingsAfter };
  const evidenceFiles = (await Promise.all([
    evidence("e2e-acceptance-packet", e2eFile("acceptance-packet.json")),
    evidence("e2e-run-summary", e2eFile("run-summary.json")),
    evidence("e2e-completion", e2eFile("phase10-completion.json")),
    evidence("e2e-image-manifest", e2eFile("docker-image-identities-after.json")),
    evidence("e2e-restoration-contract", e2eFile("restoration-contract.json")),
    evidence("current-foundation", foundationArg), evidence("current-functions", functionsArg),
    evidence("current-nfr-summary", nfrFile("summary.json")), evidence("current-image-manifest", imageArg),
    optionalEvidence("current-payment-settings-before", nfrFile("payment-settings-before.json")),
    optionalEvidence("current-payment-settings-after", nfrFile("payment-settings-after.json")),
    optionalEvidence("operational-nfr-summary", operationalFile("summary.json")),
    optionalEvidence("operational-burst", operationalFile("operational-100-message-burst.json")),
    optionalEvidence("operational-outage", operationalFile("consumer-outage-drill.json")),
    optionalEvidence("operational-rollback", operationalFile("rollback-evidence.json")),
    operationalImageArg ? optionalEvidence("operational-image-manifest", operationalImageArg) : Promise.resolve(undefined),
    ...(["summary.json", "before.json", "after.json", "docker-image-identities-before.json", "docker-image-identities-after.json"] as const)
      .map((name, index) => persistenceFile(name) ? optionalEvidence(`persistence-${index}`, persistenceFile(name)!) : Promise.resolve(undefined)),
    ...(["messaging-proof.json", "replay-restoration.json", "functions-proof.json"] as const)
      .map((name, index) => replayFile(name) ? optionalEvidence(`replay-${index}`, replayFile(name)!) : Promise.resolve(undefined)),
    replayImageArg ? optionalEvidence("replay-image-manifest", replayImageArg) : Promise.resolve(undefined),
    ...(noPaymentRoot ? await Promise.all(["run-summary.json", "acceptance-packet.json", "phase10-coverage-summary.json", "phase10-completion.json"]
      .map(name => optionalEvidence(`no-payment-report-${name}`, join(noPaymentRoot, name)))) : [])
  ])).filter((item): item is NonNullable<typeof item> => item !== undefined);
  const noPaymentCompletion = noPaymentRoot ? await verifyPhase10Completion(noPaymentRoot) : undefined;
  const noPaymentCompletionStatus = noPaymentCompletion?.state === "COMPLETE" ? noPaymentCompletion.status : undefined;
  const report = reconcilePhase10LocalFollowup({
    e2e: { completion: e2eCompletion.state,
      completionStatus: e2eCompletion.state === "COMPLETE" ? e2eCompletion.status : undefined,
      packet, summary: e2eSummary, imageAfter: e2eImage, restorationContract },
    noPaymentReport: noPaymentRoot ? { completion: noPaymentCompletion?.state ?? "INCOMPLETE", completionStatus: noPaymentCompletionStatus,
      packet: noPaymentPacket, summary: noPaymentSummary, coverage: noPaymentCoverage } : undefined,
    current: { imageManifest: currentImage, foundation, functions, nfr, burst, outage, rollback,
      operational: { summary: operationsSummary, imageManifest: operationsImage },
      persistence: { summary: persistenceSummary, before: persistenceBefore, after: persistenceAfter,
        imageBefore: persistenceImageBefore, imageAfter: persistenceImageAfter },
      replay: { messaging: replayMessaging, restoration: replayRestoration, functions: replayFunctions, imageManifest: replayImage } },
    evidence: evidenceFiles.map(item => ({ id: item.id, path: item.path, sha256: item.sha256 }))
  });

  const output = isAbsolute(outputArg) ? resolve(outputArg) : resolve(repoRoot, outputArg);
  const testRootReal = await realpath(testResultsRoot);
  const phase10RootReal = await realpath(join(testResultsRoot, "Phase10"));
  const outputParent = await realpath(dirname(output));
  const outputParentInfo = await lstat(dirname(output));
  if (!inside(testRootReal, output) || !inside(phase10RootReal, output) || output === phase10RootReal ||
      !inside(phase10RootReal, outputParent) || outputParentInfo.isSymbolicLink()) {
    throw new Error("Output must be a new directory beneath TestResults/Phase10.");
  }
  await mkdir(output, { recursive: false });
  const links = new Map(evidenceFiles.map(item => [item.id,
    relative(output, item.realPath).split(sep).map(segment => encodeURIComponent(segment)).join("/")]));
  const jsonOutput = join(output, "local-followup.json");
  const htmlOutput = join(output, "index.html");
  await writeFile(jsonOutput, JSON.stringify({ ...report, generatedUtc: new Date().toISOString() }, null, 2) + "\n", { encoding: "utf8", flag: "wx" });
  await writeFile(htmlOutput, renderPhase10LocalFollowupHtml(report, links), { encoding: "utf8", flag: "wx" });
  console.log("Local follow-up report: " + report.verdict);
  console.log("Same 13 image binaries: " + String(report.imageBinaryMatch) + "; clean candidate: " +
    (report.gates.find(item => item.id === "clean-single-source-candidate")?.status ?? "UNKNOWN"));
  console.log("JSON: " + relativeEvidence(jsonOutput));
  console.log("HTML: " + relativeEvidence(htmlOutput));
  if (report.verdict === "FAIL") process.exitCode = 1;
}

main().catch((error: unknown) => {
  console.error("Could not create Phase 10 local follow-up:", error instanceof Error ? error.message : "unknown error");
  process.exitCode = 2;
});
