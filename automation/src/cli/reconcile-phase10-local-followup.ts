import { createHash } from "node:crypto";
import { lstat, mkdir, readFile, realpath, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { verifyPhase10Completion } from "../report/phase10-completion.js";
import { reconcilePhase10LocalFollowup, renderPhase10LocalFollowupHtml } from "../report/phase10-local-followup.js";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const testResultsRoot = resolve(repoRoot, "TestResults");
const maxJsonBytes = 2 * 1024 * 1024;

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
  try { return JSON.parse((await readFile(real, "utf8")).replace(/^\uFEFF/, "")) as unknown; }
  catch (error) { if (error instanceof SyntaxError) throw new Error("Evidence JSON is malformed."); throw error; }
}

function relativeEvidence(path: string): string {
  return relative(repoRoot, path).split(sep).join("/");
}

async function evidence(id: string, path: string): Promise<{ id: string; path: string; sha256: string; realPath: string }> {
  const realPath = await safePath(path);
  const bytes = await readFile(realPath);
  return { id, path: relativeEvidence(realPath), sha256: createHash("sha256").update(bytes).digest("hex"), realPath };
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const option = (name: string) => { const index = args.indexOf(name); return index >= 0 ? args[index + 1] : undefined; };
  const e2eArg = option("--e2e");
  const foundationArg = option("--foundation");
  const functionsArg = option("--functions");
  const nfrArg = option("--nfr-root");
  const imageArg = option("--image-manifest");
  const outputArg = option("--out");
  if (!e2eArg || !foundationArg || !functionsArg || !nfrArg || !imageArg || !outputArg) {
    throw new Error("Usage: report:phase10-local-followup -- --e2e <run-dir> --foundation <summary.json> --functions <functions-proof.json> --nfr-root <nfr-dir> --image-manifest <after.json> --out <new-TestResults-dir>");
  }

  const e2eRoot = await safePath(e2eArg, true);
  const nfrRoot = await safePath(nfrArg, true);
  const e2eFile = (name: string) => join(e2eRoot, name);
  const nfrFile = (name: string) => join(nfrRoot, name);
  const e2eCompletion = await verifyPhase10Completion(e2eRoot);
  const [packet, e2eSummary, e2eImage, foundation, functions, nfr, burst, outage, rollback, currentImage] = await Promise.all([
    json(e2eFile("acceptance-packet.json")), json(e2eFile("run-summary.json")), json(e2eFile("docker-image-identities-after.json")),
    json(foundationArg), json(functionsArg), json(nfrFile("summary.json")), json(nfrFile("operational-100-message-burst.json")),
    json(nfrFile("consumer-outage-drill.json")), json(nfrFile("rollback-evidence.json")), json(imageArg)
  ]);
  const evidenceFiles = await Promise.all([
    evidence("e2e-acceptance-packet", e2eFile("acceptance-packet.json")),
    evidence("e2e-run-summary", e2eFile("run-summary.json")),
    evidence("e2e-completion", e2eFile("phase10-completion.json")),
    evidence("e2e-image-manifest", e2eFile("docker-image-identities-after.json")),
    evidence("current-foundation", foundationArg), evidence("current-functions", functionsArg),
    evidence("current-nfr-summary", nfrFile("summary.json")), evidence("current-burst", nfrFile("operational-100-message-burst.json")),
    evidence("current-outage", nfrFile("consumer-outage-drill.json")), evidence("current-rollback", nfrFile("rollback-evidence.json")),
    evidence("current-image-manifest", imageArg)
  ]);
  const report = reconcilePhase10LocalFollowup({
    e2e: { completion: e2eCompletion.state,
      completionStatus: e2eCompletion.state === "COMPLETE" ? e2eCompletion.status : undefined,
      packet, summary: e2eSummary, imageAfter: e2eImage },
    current: { imageManifest: currentImage, foundation, functions, nfr, burst, outage, rollback },
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
