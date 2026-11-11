export interface Phase10ImageRecord {
  project: "xy-phase10";
  service: string;
  containerId: string;
  imageReference: string;
  imageId: string;
  repositoryDigests: string[];
}

export interface Phase10ImageManifest {
  schema: "phase10-docker-image-identities-v1";
  runId: string;
  capturePoint: "before" | "after";
  candidate: { commit: string; worktree: "clean" | "dirty"; dirtyStatusSha256: string | null };
  buildLogsSha256: Record<string, string>;
  images: Phase10ImageRecord[];
}

export const PHASE10_DOCKER_SERVICES = ["azurite", "functions", "gateway", "inventory", "keycloak-local", "notifications",
  "orders", "payments", "redis", "servicebus-emulator", "servicebus-sql", "sql-server", "ui"] as const;

export type ImageManifestResult = { status: "PASS"; manifest: Phase10ImageManifest } |
  { status: "BLOCKED" | "FAIL"; reason: string };

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value)) : undefined;
}

export function validatePhase10ImageManifest(value: unknown, expectedRunId?: string,
  expectedCapturePoint?: "before" | "after"): ImageManifestResult {
  const manifest = record(value);
  const candidate = record(manifest?.candidate);
  if (manifest?.schema !== "phase10-docker-image-identities-v1" || typeof manifest.runId !== "string" || !manifest.runId ||
      (expectedRunId !== undefined && manifest.runId !== expectedRunId) ||
      (manifest.capturePoint !== "before" && manifest.capturePoint !== "after") ||
      (expectedCapturePoint !== undefined && manifest.capturePoint !== expectedCapturePoint)) {
    return { status: "BLOCKED", reason: "Manifest schema, run, or capture point is missing or inconsistent." };
  }
  if (!candidate || typeof candidate.commit !== "string" || !/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(candidate.commit) ||
      (candidate.worktree !== "clean" && candidate.worktree !== "dirty") ||
      (candidate.worktree === "clean" && candidate.dirtyStatusSha256 !== null) ||
      (candidate.worktree === "dirty" && (typeof candidate.dirtyStatusSha256 !== "string" || !/^[a-f0-9]{64}$/.test(candidate.dirtyStatusSha256)))) {
    return { status: "BLOCKED", reason: "Manifest candidate identity is missing or malformed." };
  }
  if (!Array.isArray(manifest.images) || manifest.images.length !== 13) {
    return { status: "BLOCKED", reason: "Manifest does not cover exactly the 13 expected Phase 10 services." };
  }
  const services = new Set<string>();
  const containers = new Set<string>();
  const images: Phase10ImageRecord[] = [];
  for (const value of manifest.images) {
    const item = record(value);
    if (item?.project !== "xy-phase10" || typeof item.service !== "string" || !/^[a-z0-9][a-z0-9_-]*$/.test(item.service) ||
        services.has(item.service) || typeof item.containerId !== "string" || !/^[0-9a-f]{12,64}$/.test(item.containerId) || containers.has(item.containerId) ||
        typeof item.imageReference !== "string" || !item.imageReference || item.imageReference.length > 512 ||
        typeof item.imageId !== "string" || !/^sha256:[0-9a-f]{64}$/.test(item.imageId) ||
        !Array.isArray(item.repositoryDigests) || item.repositoryDigests.some(digest => typeof digest !== "string" || !/^.+@sha256:[0-9a-f]{64}$/.test(digest))) {
      return { status: "BLOCKED", reason: "Manifest contains a missing, duplicate, foreign, or malformed service image record." };
    }
    services.add(item.service);
    containers.add(item.containerId);
    images.push({ project: "xy-phase10", service: item.service, containerId: item.containerId,
      imageReference: item.imageReference, imageId: item.imageId, repositoryDigests: [...item.repositoryDigests] as string[] });
  }
  if (PHASE10_DOCKER_SERVICES.some(service => !services.has(service))) {
    return { status: "BLOCKED", reason: "Manifest omits one or more required Phase 10 Compose services." };
  }
  const buildLogs = record(manifest.buildLogsSha256);
  if (!buildLogs || Object.values(buildLogs).some(hash => typeof hash !== "string" || !/^[a-f0-9]{64}$/.test(hash))) {
    return { status: "BLOCKED", reason: "Build-log identity metadata is missing or malformed." };
  }
  return { status: "PASS", manifest: {
    schema: "phase10-docker-image-identities-v1", runId: manifest.runId, capturePoint: manifest.capturePoint,
    candidate: { commit: candidate.commit, worktree: candidate.worktree,
      dirtyStatusSha256: typeof candidate.dirtyStatusSha256 === "string" ? candidate.dirtyStatusSha256 : null },
    buildLogsSha256: buildLogs as Record<string, string>, images: images.sort((a, b) => a.service.localeCompare(b.service))
  } };
}

export function phase10ImageSetsMatch(left: Phase10ImageManifest, right: Phase10ImageManifest): boolean {
  return left.candidate.commit === right.candidate.commit && left.candidate.worktree === right.candidate.worktree &&
    left.candidate.dirtyStatusSha256 === right.candidate.dirtyStatusSha256 &&
    left.images.length === right.images.length && left.images.every((item, index) =>
      item.service === right.images[index]?.service && item.imageId === right.images[index]?.imageId &&
      item.imageReference === right.images[index]?.imageReference &&
      item.repositoryDigests.join("\n") === right.images[index]?.repositoryDigests.join("\n"));
}
