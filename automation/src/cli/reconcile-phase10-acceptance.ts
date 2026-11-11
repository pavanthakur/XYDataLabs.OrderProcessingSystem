import { execFile } from "node:child_process";
import { lstat, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";
import { verifyPhase10Completion } from "../report/phase10-completion.js";
import { reconcilePhase10Acceptance } from "../report/phase10-acceptance.js";

const run = promisify(execFile);

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

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const option = (name: string) => { const index = args.indexOf(name); return index >= 0 ? args[index + 1] : undefined; };
  const e2eRoot = option("--e2e");
  const nfrRoot = option("--nfr");
  if (!e2eRoot || !nfrRoot) throw new Error("Usage: reconcile:phase10-acceptance -- --e2e <docker-run-dir> --nfr <nfr-run-dir> [--expected-commit <sha>]");
  const expectedCommit = option("--expected-commit") ?? (await run("git", ["rev-parse", "HEAD"])).stdout.trim();
  if (!/^[0-9a-f]{40}$/.test(expectedCommit)) throw new Error("Expected commit must be a full 40-character SHA.");
  await directory(e2eRoot);
  await directory(nfrRoot);

  const completion = await verifyPhase10Completion(e2eRoot);
  const index = await readFile(join(e2eRoot, "index.html"), "utf8").catch(() => "");
  const issues = index.match(/<h2>Issues<\/h2><ul>(.*?)<\/ul>/s)?.[1] ?? "";
  const nfrDirectory = join(nfrRoot, "nfr");
  const nfrWrapper = record(await json(join(nfrRoot, "wrapper-summary.json")));
  const nfrRunId = typeof nfrWrapper?.runDir === "string" ? nfrWrapper.runDir.replace(/[\\/]+$/, "").split(/[\\/]/).at(-1) : undefined;
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
    nfr: {
      summary: await json(join(nfrDirectory, "summary.json")), outageDrill: await json(join(nfrDirectory, "consumer-outage-drill.json")),
      replayProof: await json(join(nfrDirectory, "replay-proof", "functions-proof.json")),
      performanceProbe: await json(join(nfrDirectory, "performance-probe.json")),
      imageBefore: await json(join(nfrRoot, "docker-image-identities-before.json")),
      imageAfter: await json(join(nfrRoot, "docker-image-identities-after.json")),
      imageRunId: nfrWrapper?.dockerImageIdentitiesBefore === "docker-image-identities-before.json" &&
        nfrWrapper?.dockerImageIdentitiesAfter === "docker-image-identities-after.json" ? nfrRunId : undefined
    }
  });
  const output = join(e2eRoot, "phase10-acceptance-reconciliation.json");
  await writeFile(output, JSON.stringify({ ...result, e2eRun: e2eRoot, nfrRun: nfrRoot, createdUtc: new Date().toISOString() }, null, 2) + "\n",
    { encoding: "utf8", flag: "wx" });
  for (const item of result.gates) console.log(`${item.status.padEnd(8)} ${item.name} - ${item.detail}`);
  console.log(`Verdict: ${result.verdict} (scope: ${result.scope}). Written: ${output}`);
  process.exitCode = result.verdict === "PASS" ? 0 : 1;
}

main().catch((error: unknown) => {
  console.error("Could not reconcile Phase 10 acceptance:", error instanceof Error ? error.message : "unknown error");
  process.exitCode = 2;
});
