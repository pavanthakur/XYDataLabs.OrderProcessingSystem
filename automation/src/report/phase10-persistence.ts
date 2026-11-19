import { createHash } from "node:crypto";
import { PHASE10_DOCKER_SERVICES } from "./phase10-images.js";
import type { EvidenceStatus } from "./phase10-report.js";

type JsonRecord = Record<string, unknown>;

export interface Phase10PersistenceEvidence {
  status: EvidenceStatus;
  runId: string | null;
  candidateCommit: string | null;
  tenantRows: number;
  imageCount: number;
  issues: string[];
}

function record(value: unknown): JsonRecord | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : undefined;
}

function sha256(value: unknown): value is string {
  return typeof value === "string" && /^[a-f0-9]{64}$/i.test(value);
}

function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  const item = record(value);
  if (item) return `{${Object.keys(item).sort().map(key => `${JSON.stringify(key)}:${canonical(item[key])}`).join(",")}}`;
  return JSON.stringify(value);
}

function candidateMatches(candidate: unknown, parent: unknown): boolean {
  const item = record(candidate);
  const root = record(parent);
  const start = record(root?.start);
  const finish = record(root?.finish);
  return Boolean(item && root && item.worktree === "clean" && start?.worktree === "clean" && finish?.worktree === "clean" &&
    typeof item.commit === "string" && /^[a-f0-9]{40}$/i.test(item.commit) &&
    item.commit === start?.commit && item.commit === finish?.commit);
}

function imageIdentity(value: unknown): Map<string, string> | undefined {
  const manifest = record(value);
  if (manifest?.schema !== "phase10-docker-image-identities-v1" || !Array.isArray(manifest.images) ||
      manifest.images.length !== PHASE10_DOCKER_SERVICES.length) return undefined;
  const identities = new Map<string, string>();
  for (const value of manifest.images) {
    const image = record(value);
    if (image?.project !== "xy-phase10" || typeof image.service !== "string" ||
        !/^[a-z][a-z0-9-]{0,63}$/.test(image.service) || typeof image.imageId !== "string" ||
        !/^sha256:[a-f0-9]{64}$/i.test(image.imageId) || identities.has(image.service)) return undefined;
    identities.set(image.service, image.imageId.toLowerCase());
  }
  return identities.size === PHASE10_DOCKER_SERVICES.length && PHASE10_DOCKER_SERVICES.every(service => identities.has(service)) ? identities : undefined;
}

function snapshotsMatch(beforeInput: unknown, afterInput: unknown): number {
  if (!Array.isArray(beforeInput) || !Array.isArray(afterInput) || beforeInput.length === 0 || beforeInput.length !== afterInput.length) return 0;
  const key = (value: unknown): string | undefined => {
    const row = record(value);
    return typeof row?.tenant === "string" && /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(row.tenant) &&
      Number.isSafeInteger(row.orderId) && Number(row.orderId) > 0 ? `${row.tenant}\0${row.orderId}` : undefined;
  };
  const beforeKeys = beforeInput.map(key);
  const afterKeys = afterInput.map(key);
  if (beforeKeys.some(value => value === undefined) || afterKeys.some(value => value === undefined) ||
      new Set(beforeKeys).size !== beforeKeys.length || new Set(afterKeys).size !== afterKeys.length ||
      [...beforeKeys].sort().join("\n") !== [...afterKeys].sort().join("\n")) return 0;
  const afterByKey = new Map(afterInput.map(row => [key(row)!, row]));
  if (beforeInput.some(row => canonical(row) !== canonical(afterByKey.get(key(row)!)))) return 0;
  return beforeInput.length;
}

export function normalizePhase10PersistenceEvidence(input?: {
  summary: unknown;
  before: unknown;
  after: unknown;
  beforeTextSha256: string | undefined;
  afterTextSha256: string | undefined;
  imageBefore: unknown;
  imageAfter: unknown;
  imageBeforeSha256: string | undefined;
  imageAfterSha256: string | undefined;
  parentGitProvenance: unknown;
  parentImageBefore: unknown;
  parentImageAfter: unknown;
}): Phase10PersistenceEvidence {
  if (!input) return { status: "NOT-RUN", runId: null, candidateCommit: null, tenantRows: 0, imageCount: 0, issues: [] };

  const issues: string[] = [];
  const summary = record(input.summary);
  const runId = typeof summary?.runId === "string" && /^phase10-persistence-\d{8}-\d{9}$/.test(summary.runId) ? summary.runId : null;
  if (summary?.status !== "passed" || !runId) issues.push("Persistence run summary is missing, invalid or unsuccessful.");
  if (!candidateMatches(summary?.candidate, input.parentGitProvenance)) issues.push("Persistence candidate does not match the clean parent run candidate.");
  if (summary?.publicEndpointsReachable !== true || summary?.imageIdentitiesUnchanged !== true ||
      typeof summary.sqlVolume !== "string" || !/^xy-phase10_[a-z0-9_-]+$/.test(summary.sqlVolume) ||
      typeof summary.disk !== "string" || summary.disk.trim().length === 0) {
    issues.push("Persistence runtime, named SQL volume or storage identity is incomplete.");
  }
  if (!Array.isArray(summary?.nativeSqlBefore) || !Array.isArray(summary?.nativeSqlAfter) ||
      canonical(summary.nativeSqlBefore) !== canonical(summary.nativeSqlAfter)) {
    issues.push("Native SQL listener evidence changed or is unavailable.");
  }
  const rows = snapshotsMatch(input.before, input.after);
  if (rows === 0) issues.push("Known tenant order rows did not reconcile byte-for-byte across the restart.");
  const evidenceHashes = record(summary?.evidenceSha256);
  if (!sha256(input.beforeTextSha256) || !sha256(input.afterTextSha256) ||
      evidenceHashes?.before !== input.beforeTextSha256 || evidenceHashes?.after !== input.afterTextSha256) {
    issues.push("Before/after persistence snapshot hashes are missing or inconsistent.");
  }
  const beforeManifest = record(input.imageBefore);
  const afterManifest = record(input.imageAfter);
  const expectedBeforeHash = record(summary?.evidenceSha256)?.imageBefore;
  const expectedAfterHash = record(summary?.evidenceSha256)?.imageAfter;
  if (!sha256(input.imageBeforeSha256) || !sha256(input.imageAfterSha256) ||
      expectedBeforeHash !== input.imageBeforeSha256 || expectedAfterHash !== input.imageAfterSha256 ||
      beforeManifest?.capturePoint !== "before" || afterManifest?.capturePoint !== "after" ||
      beforeManifest?.runId !== runId || afterManifest?.runId !== runId ||
      !candidateMatches(summary?.candidate, { start: beforeManifest?.candidate, finish: afterManifest?.candidate })) {
    issues.push("Persistence image-manifest hashes or candidate/run identities do not reconcile.");
  }
  const imagesBefore = imageIdentity(input.imageBefore);
  const imagesAfter = imageIdentity(input.imageAfter);
  const parentBefore = imageIdentity(input.parentImageBefore);
  const parentAfter = imageIdentity(input.parentImageAfter);
  const equalMaps = (left: Map<string, string> | undefined, right: Map<string, string> | undefined) =>
    Boolean(left && right && left.size === right.size && [...left].every(([service, image]) => right.get(service) === image));
  if (!equalMaps(imagesBefore, imagesAfter) || !equalMaps(imagesBefore, parentBefore) || !equalMaps(imagesAfter, parentAfter)) {
    issues.push("Persistence images do not match each other and the parent E2E image inventory.");
  }
  return { status: issues.length ? "BLOCKED" : "PASS", runId, candidateCommit: issues.length ? null :
    (record(summary?.candidate)?.commit as string), tenantRows: rows, imageCount: imagesBefore?.size ?? 0, issues };
}
