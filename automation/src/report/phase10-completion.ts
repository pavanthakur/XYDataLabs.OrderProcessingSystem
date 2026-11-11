import { createHash } from "node:crypto";
import { lstat, readFile } from "node:fs/promises";
import { basename, join } from "node:path";
import { phase10ImageSetsMatch, validatePhase10ImageManifest } from "./phase10-images.js";

const legacyArtifacts = ["acceptance-packet.json", "run-summary.json", "phase10-preview.html"] as const;
const currentArtifacts = [...legacyArtifacts, "phase10-coverage-summary.json"] as const;
const currentArtifactsV3 = [...currentArtifacts, "index.html"] as const;
const currentArtifactsV4 = [...currentArtifactsV3, "docker-image-identities-before.json", "docker-image-identities-after.json"] as const;
type Status = "passed" | "partial" | "failed";
export type CompletionResult = { state: "COMPLETE"; status: Status } | { state: "INCOMPLETE" };

function object(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value)) : undefined;
}

async function readFileSafely(root: string, name: string): Promise<Buffer | undefined> {
  try {
    const path = join(root, name);
    const info = await lstat(path);
    if (!info.isFile() || info.isSymbolicLink() || info.size > 2 * 1024 * 1024) return undefined;
    return await readFile(path);
  } catch (error) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") return undefined;
    throw error;
  }
}

function json(bytes: Buffer | undefined): Record<string, unknown> | undefined {
  if (!bytes) return undefined;
  try { return object(JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, "")) as unknown); }
  catch (error) { if (error instanceof SyntaxError) return undefined; throw error; }
}

export async function verifyPhase10Completion(root: string): Promise<CompletionResult> {
  const incomplete: CompletionResult = { state: "INCOMPLETE" };
  const directory = await lstat(root);
  if (!directory.isDirectory() || directory.isSymbolicLink()) return incomplete;
  const marker = json(await readFileSafely(root, "phase10-completion.json"));
  const hashes = object(marker?.sha256);
  const status = marker?.status;
  const artifacts = marker?.schema === "phase10-completion-v1" ? legacyArtifacts
    : marker?.schema === "phase10-completion-v2" ? currentArtifacts
      : marker?.schema === "phase10-completion-v3" ? currentArtifactsV3
        : marker?.schema === "phase10-completion-v4" ? currentArtifactsV4 : undefined;
  if (!artifacts || typeof marker?.runId !== "string" ||
      marker.runId !== basename(root) || (status !== "passed" && status !== "partial" && status !== "failed") ||
      !hashes || Object.keys(hashes).length !== artifacts.length) return incomplete;
  const contents = new Map<string, Buffer>();
  for (const name of artifacts) {
    const expected = hashes[name];
    if (typeof expected !== "string" || !/^[a-f0-9]{64}$/.test(expected)) return incomplete;
    const bytes = await readFileSafely(root, name);
    if (!bytes || createHash("sha256").update(bytes).digest("hex") !== expected) return incomplete;
    contents.set(name, bytes);
  }
  const packet = json(contents.get("acceptance-packet.json"));
  const summary = json(contents.get("run-summary.json"));
  if (!packet || !summary || summary.runId !== marker.runId ||
      summary.status !== status || packet.status !== status ||
      typeof summary.runRoot !== "string" || !summary.runRoot ||
      packet.runRoot !== summary.runRoot ||
      summary.runRoot.replace(/[\\/]+$/, "").split(/[\\/]/).at(-1) !== marker.runId) return incomplete;
  if (marker.schema === "phase10-completion-v4") {
    const before = validatePhase10ImageManifest(json(contents.get("docker-image-identities-before.json")), marker.runId, "before");
    const after = validatePhase10ImageManifest(json(contents.get("docker-image-identities-after.json")), marker.runId, "after");
    const git = object(summary.gitProvenance);
    const provenanceStart = object(git?.start);
    const provenanceFinish = object(git?.finish);
    if (before.status !== "PASS" || after.status !== "PASS" ||
        !phase10ImageSetsMatch(before.manifest, after.manifest) ||
        provenanceStart?.commit !== before.manifest.candidate.commit || provenanceFinish?.commit !== before.manifest.candidate.commit ||
        provenanceStart?.worktree !== before.manifest.candidate.worktree ||
        provenanceFinish?.worktree !== before.manifest.candidate.worktree) return incomplete;
  }
  return { state: "COMPLETE", status };
}
