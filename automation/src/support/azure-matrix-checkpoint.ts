import { createHash, randomUUID } from "node:crypto";
import { readFile, rename, realpath, writeFile } from "node:fs/promises";
import path from "node:path";
import { execFileSync } from "node:child_process";
import type { ExecutiveSummaryRow } from "../contracts/report-composer.js";
import type {VerificationRequest} from "../contracts/verification-adapter.js";

export interface MatrixCheckpoint {
  schemaVersion: 1;
  binding: string;
  provenance?: {candidate:string;deployment:string;settings:string};
  plannedKeys?: string[];
  cases: Array<{ key: string; state: "started" | "verified-restored" | "verification-pending"; row?: ExecutiveSummaryRow; ledgerPath?:string; request?:VerificationRequest }>;
}

export function matrixBinding(value: unknown): string {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

export function assertResumeSafe(checkpoint: MatrixCheckpoint, binding: string, keys: string[]): void {
  if (checkpoint.schemaVersion !== 1 || checkpoint.binding !== binding || !Array.isArray(checkpoint.cases)) {
    throw new Error("Checkpoint candidate/deployment/settings binding differs or is malformed; resume refused.");
  }
  const seen = new Set<string>();
  for (const item of checkpoint.cases) {
    if (!keys.includes(item.key) || seen.has(item.key) || item.state !== "verified-restored"
      || !item.row || `${item.row.tenantCode.toLowerCase()}|${item.row.paymentProvider.toLowerCase()}` !== item.key
      || !item.row.journeyOutcome.startsWith("completed") || item.row.verificationOutcome !== "passed"
      || item.row.cleanupOutcome !== "reset" || item.row.adapterMode !== "sandbox") {
      throw new Error("Checkpoint contains an interrupted, duplicate, unknown or unresolved case; reconcile read-only before any new submission.");
    }
    seen.add(item.key);
  }
}

// Hash content, not only HEAD: a dirty candidate must not inherit another candidate's receipts.
export async function candidateIdentity(root: string): Promise<string> {
  const files = execFileSync("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard"], { cwd: root }).toString().split("\0").filter(Boolean).sort();
  const hash = createHash("sha256");
  hash.update(execFileSync("git", ["rev-parse", "HEAD"], { cwd: root }));
  for (const file of files) {
    hash.update(file).update("\0");
    try { hash.update(await readFile(path.join(root, file))); }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; hash.update("DELETED"); }
  }
  return hash.digest("hex");
}

export async function readCheckpoint(file: string, evidenceRoot: string): Promise<MatrixCheckpoint> {
  return await readBoundedEvidence(file,evidenceRoot) as MatrixCheckpoint;
}

export async function readBoundedEvidence(file:string,evidenceRoot:string):Promise<unknown>{
  const root = await realpath(evidenceRoot);
  const actual = await realpath(file);
  const relative = path.relative(root, actual);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) throw new Error("Checkpoint must be inside the local evidence root.");
  return JSON.parse(await readFile(actual, "utf8"));
}

export async function saveCheckpoint(file: string, checkpoint: MatrixCheckpoint): Promise<void> {
  await writeAtomicEvidence(file,checkpoint);
}

export async function writeAtomicEvidence(file:string,value:unknown):Promise<void>{
  const temporary = `${file}.${randomUUID()}.tmp`;
  await writeFile(temporary, JSON.stringify(value, null, 2), { encoding: "utf8", flag: "wx" });
  await rename(temporary, file);
}
