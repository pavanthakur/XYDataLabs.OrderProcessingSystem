import { createHash } from "node:crypto";
import { lstat, readFile } from "node:fs/promises";
import { basename, join } from "node:path";
import { phase10ImageSetsMatch, validatePhase10ImageManifest } from "./phase10-images.js";

const legacyArtifacts = ["acceptance-packet.json", "run-summary.json", "phase10-preview.html"] as const;
const currentArtifacts = [...legacyArtifacts, "phase10-coverage-summary.json"] as const;
const currentArtifactsV3 = [...currentArtifacts, "index.html"] as const;
const currentArtifactsV4 = [...currentArtifactsV3, "docker-image-identities-before.json", "docker-image-identities-after.json"] as const;
export const phase10FunctionsProofPath = "messaging/functions-proof.json";
const currentArtifactsV5 = [...currentArtifactsV4, phase10FunctionsProofPath] as const;
export const phase10PaymentBaselinePaths = ["seed-contract.json", "restoration-contract.json", "payments/sandbox-gates.json"] as const;
const currentArtifactsV6 = [...currentArtifactsV5, ...phase10PaymentBaselinePaths] as const;
type Status = "passed" | "partial" | "failed";
export type CompletionResult = { state: "COMPLETE"; status: Status; functionsProofSha256?: string;
  paymentBaselineSha256?: string[] } | { state: "INCOMPLETE" };

export function phase10NfrSealMatches(seal: unknown, runId: string, requiredPaths: readonly string[],
  loadedHash: (path: string) => string | undefined): boolean {
  const record = object(seal);
  const hashes = object(record?.sha256);
  return record?.schema === "phase10-nfr-evidence-v1" && record.runId === runId && !!hashes &&
    requiredPaths.every(path => typeof hashes[path] === "string" && /^[a-f0-9]{64}$/.test(hashes[path]) &&
      hashes[path] === loadedHash(path));
}

function object(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value)) : undefined;
}

export async function readPhase10Artifact(root: string, name: string): Promise<Buffer | undefined> {
  try {
    const segments = name.split("/");
    if (segments.some(segment => !/^[a-z0-9][a-z0-9.-]*$/i.test(segment))) return undefined;
    for (let depth = 0; depth < segments.length; depth++) {
      const directory = await lstat(join(root, ...segments.slice(0, depth)));
      if (!directory.isDirectory() || directory.isSymbolicLink()) return undefined;
    }
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
  const marker = json(await readPhase10Artifact(root, "phase10-completion.json"));
  const hashes = object(marker?.sha256);
  const status = marker?.status;
  const artifacts = marker?.schema === "phase10-completion-v1" ? legacyArtifacts
    : marker?.schema === "phase10-completion-v2" ? currentArtifacts
      : marker?.schema === "phase10-completion-v3" ? currentArtifactsV3
        : marker?.schema === "phase10-completion-v4" ? currentArtifactsV4
          : marker?.schema === "phase10-completion-v5" ? currentArtifactsV5
            : marker?.schema === "phase10-completion-v6" ? currentArtifactsV6 : undefined;
  if (!artifacts || typeof marker?.runId !== "string" ||
      marker.runId !== basename(root) || (status !== "passed" && status !== "partial" && status !== "failed") ||
      !hashes || Object.keys(hashes).length !== artifacts.length) return incomplete;
  const contents = new Map<string, Buffer>();
  for (const name of artifacts) {
    const expected = hashes[name];
    if (typeof expected !== "string" || !/^[a-f0-9]{64}$/.test(expected)) return incomplete;
    const bytes = await readPhase10Artifact(root, name);
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
  if (["phase10-completion-v4", "phase10-completion-v5", "phase10-completion-v6"].includes(String(marker.schema))) {
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
  return { state: "COMPLETE", status,
    ...(marker.schema === "phase10-completion-v5" || marker.schema === "phase10-completion-v6"
      ? { functionsProofSha256: hashes[phase10FunctionsProofPath] as string } : {}),
    ...(marker.schema === "phase10-completion-v6"
      ? { paymentBaselineSha256: phase10PaymentBaselinePaths.map(path => hashes[path] as string) } : {}) };
}
