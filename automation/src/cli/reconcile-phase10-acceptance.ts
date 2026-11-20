import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { lstat, readFile, writeFile } from "node:fs/promises";
import { basename, dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { isDeepStrictEqual } from "node:util";
import { phase10NfrSealMatches, phase10PaymentBaselinePaths, readPhase10Artifact, verifyPhase10Completion } from "../report/phase10-completion.js";
import { phase10PaymentConfigurationMatches, reconcilePhase10Acceptance } from "../report/phase10-acceptance.js";
import { verifyStandalonePaymentEvidence } from "../report/phase10-standalone-payment.js";

const run = promisify(execFile);
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const testResultsRoot = resolve(repositoryRoot, "TestResults");

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value)) : undefined;
}

async function json(path: string): Promise<unknown> {
  try {
    const info = await lstat(path);
    if (!info.isFile() || info.isSymbolicLink() || info.size > 2 * 1024 * 1024) return undefined;
    return JSON.parse((await readFile(path, "utf8")).replace(/^\uFEFF/, "")) as unknown;
  } catch (error) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") return undefined;
    if (error instanceof SyntaxError) return undefined;
    throw error;
  }
}

async function directory(path: string): Promise<string> {
  const info = await lstat(path);
  if (!info.isDirectory() || info.isSymbolicLink()) throw new Error("Run directories must be non-symlink directories.");
  return path;
}

async function standaloneDirectory(path: string): Promise<string> {
  const target = resolve(repositoryRoot, path);
  const rel = relative(testResultsRoot, target);
  if (!rel || rel === ".." || rel.startsWith(`..${sep}`) || /^[A-Za-z]:/.test(rel)) {
    throw new Error("Standalone payment evidence must be in a run directory under TestResults.");
  }
  let cursor = testResultsRoot;
  for (const segment of rel.split(sep)) {
    cursor = join(cursor, segment);
    let info: import("node:fs").Stats;
    try { info = await lstat(cursor); }
    catch (error) {
      if (error instanceof Error && "code" in error && error.code === "ENOENT") return target;
      throw error;
    }
    if (!info.isDirectory() || info.isSymbolicLink()) throw new Error("Standalone payment run paths cannot contain symlinks and must be directories.");
  }
  return target;
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const option = (name: string) => { const index = args.indexOf(name); return index >= 0 ? args[index + 1] : undefined; };
  const fromRepo = (value: string | undefined) => value ? resolve(repositoryRoot, value) : undefined;
  const e2eRoot = fromRepo(option("--e2e"));
  const nfrRoot = fromRepo(option("--nfr"));
  const standaloneOptions = ["--payment-deterministic", "--payment-sandbox-positive", "--payment-sandbox-negative"] as const;
  const standaloneRoots = standaloneOptions.map(name => option(name));
  const standaloneSelected = standaloneRoots.some(Boolean);
  const legacyPaymentRoot = fromRepo(option("--payments-e2e"));
  if (standaloneSelected && (standaloneRoots.some(root => !root) || legacyPaymentRoot)) {
    throw new Error("Standalone mode requires all three --payment-* directories and cannot be combined with --payments-e2e.");
  }
  const paymentRoot = standaloneSelected ? undefined : legacyPaymentRoot ?? e2eRoot;
  if (!e2eRoot || !nfrRoot || (!paymentRoot && !standaloneSelected)) throw new Error("Usage: reconcile:phase10-acceptance -- --e2e <docker-run-dir> --nfr <nfr-run-dir> [--payments-e2e <sealed-both-run-dir> | --payment-deterministic <run-dir> --payment-sandbox-positive <run-dir> --payment-sandbox-negative <run-dir>] [--expected-commit <sha>]");
  const expectedCommit = option("--expected-commit") ?? (await run("git", ["rev-parse", "HEAD"])).stdout.trim();
  if (!/^[0-9a-f]{40}$/.test(expectedCommit)) throw new Error("Expected commit must be a full 40-character SHA.");
  await directory(e2eRoot);
  await directory(nfrRoot);
  if (paymentRoot) await directory(paymentRoot);
  const standalonePayments = standaloneSelected ? await Promise.all(standaloneRoots.map(async (root, index) =>
    verifyStandalonePaymentEvidence(await standaloneDirectory(root!),
      ["deterministic", "sandbox-positive", "sandbox-negative"][index] as "deterministic" | "sandbox-positive" | "sandbox-negative", expectedCommit))) : [];

  const completion = await verifyPhase10Completion(e2eRoot);
  const index = await readFile(join(e2eRoot, "index.html"), "utf8").catch(() => "");
  const issues = index.match(/<h2>Issues<\/h2><ul>(.*?)<\/ul>/s)?.[1] ?? "";
  const nfrFiles = ["wrapper-summary.json", "nfr/summary.json", "nfr/consumer-outage-drill.json",
    "nfr/replay-proof/functions-proof.json", "nfr/performance-probe.json",
    "docker-image-identities-before.json", "docker-image-identities-after.json",
    "nfr/payment-settings-before.json", "nfr/payment-settings-after.json"] as const;
  const nfrBytes = new Map(await Promise.all(nfrFiles.map(async name => [name, await readPhase10Artifact(nfrRoot, name)] as const)));
  const nfrJson = (name: typeof nfrFiles[number]): unknown => {
    const bytes = nfrBytes.get(name);
    if (!bytes) return undefined;
    try { return JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, "")) as unknown; }
    catch (error) { if (error instanceof SyntaxError) return undefined; throw error; }
  };
  const nfrSummary = record(nfrJson("nfr/summary.json"));
  const selection = record(nfrSummary?.selection);
  const separateMatrix = selection?.mode === "full" && selection.dynamicPaymentMatrix === "not-run-explicit";
  const nfrRequired = separateMatrix ? nfrFiles : nfrFiles.slice(0, -2);
  const sealVerified = phase10NfrSealMatches(await json(join(nfrRoot, "nfr-evidence-seal.json")), basename(nfrRoot),
    nfrRequired, name => {
      const bytes = nfrBytes.get(name as typeof nfrFiles[number]);
      return bytes ? createHash("sha256").update(bytes).digest("hex") : undefined;
    });
  const nfrWrapper = record(nfrJson("wrapper-summary.json"));
  const nfrRunId = typeof nfrWrapper?.runDir === "string" ? nfrWrapper.runDir.replace(/[\\/]+$/, "").split(/[\\/]/).at(-1) : undefined;
  const settingsBefore = nfrJson("nfr/payment-settings-before.json");
  const settingsAfter = nfrJson("nfr/payment-settings-after.json");
  const paymentCompletion = paymentRoot ? paymentRoot === e2eRoot ? completion : await verifyPhase10Completion(paymentRoot) : { state: "INCOMPLETE" as const };
  const baselines = paymentRoot ? await Promise.all(phase10PaymentBaselinePaths.map(async (name, index) => {
    const bytes = await readPhase10Artifact(paymentRoot, name);
    if (!bytes || paymentCompletion.state !== "COMPLETE" ||
        paymentCompletion.paymentBaselineSha256?.[index] !== createHash("sha256").update(bytes).digest("hex")) return undefined;
    try { return JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, "")) as unknown; } catch { return undefined; }
  })) : [];
  const result = reconcilePhase10Acceptance({
    expectedCommit,
    e2e: {
      completion: completion.state, completionStatus: completion.state === "COMPLETE" ? completion.status : undefined,
      packet: await json(join(e2eRoot, "acceptance-packet.json")), summary: await json(join(e2eRoot, "run-summary.json")),
      coverage: await json(join(e2eRoot, "phase10-coverage-summary.json")),
      reportIssuesClean: issues.trim() === "<li>None detected by this limited preview.</li>",
      imageBefore: await json(join(e2eRoot, "docker-image-identities-before.json")),
      imageAfter: await json(join(e2eRoot, "docker-image-identities-after.json"))
    },
    ...(paymentRoot ? { payments: {
      completionStatus: paymentCompletion.state === "COMPLETE" ? paymentCompletion.status : undefined,
      configurationMatched: sealVerified && phase10PaymentConfigurationMatches(settingsBefore, settingsAfter, baselines[0], baselines[1]),
      sandboxGates: baselines[2],
      packet: await json(join(paymentRoot, "acceptance-packet.json")), summary: await json(join(paymentRoot, "run-summary.json")),
      imageBefore: await json(join(paymentRoot, "docker-image-identities-before.json")),
      imageAfter: await json(join(paymentRoot, "docker-image-identities-after.json"))
    } } : {}),
    standalonePayments: standaloneSelected ? standalonePayments.map((item, index) => item ? ({
      ...item, configurationMatched: item.configurationMatched && sealVerified &&
        phase10PaymentConfigurationMatches(settingsBefore, settingsAfter, item.seed, item.restored)
    }) : ({
      kind: ["deterministic", "sandbox-positive", "sandbox-negative"][index] as "deterministic" | "sandbox-positive" | "sandbox-negative",
      status: "BLOCKED" as const, configurationMatched: false
    })) : [],
    nfr: {
      sealVerified: sealVerified && nfrRunId === basename(nfrRoot) && nfrWrapper?.status === (separateMatrix ? "incomplete" : "passed") &&
        nfrWrapper?.localProofStatus === nfrSummary?.status,
      settingsUnchanged: sealVerified && record(settingsBefore)?.schema === "phase10-payment-settings-snapshot-v1" &&
        isDeepStrictEqual(settingsBefore, settingsAfter),
      summary: nfrJson("nfr/summary.json"), outageDrill: nfrJson("nfr/consumer-outage-drill.json"),
      replayProof: nfrJson("nfr/replay-proof/functions-proof.json"),
      performanceProbe: nfrJson("nfr/performance-probe.json"),
      imageBefore: nfrJson("docker-image-identities-before.json"),
      imageAfter: nfrJson("docker-image-identities-after.json"),
      imageRunId: nfrWrapper?.dockerImageIdentitiesBefore === "docker-image-identities-before.json" &&
        nfrWrapper?.dockerImageIdentitiesAfter === "docker-image-identities-after.json" ? nfrRunId : undefined
    }
  });
  const output = join(e2eRoot, "phase10-acceptance-reconciliation.json");
  await writeFile(output, JSON.stringify({ ...result, e2eRun: e2eRoot, nfrRun: nfrRoot, paymentRun: paymentRoot, createdUtc: new Date().toISOString() }, null, 2) + "\n",
    { encoding: "utf8", flag: "wx" });
  for (const item of result.gates) console.log(`${item.status.padEnd(8)} ${item.name} - ${item.detail}`);
  console.log(`Verdict: ${result.verdict} (scope: ${result.scope}). Written: ${output}`);
  process.exitCode = result.verdict === "PASS" ? 0 : 1;
}

main().catch((error: unknown) => {
  console.error("Could not reconcile Phase 10 acceptance:", error instanceof Error ? error.message : "unknown error");
  process.exitCode = 2;
});
