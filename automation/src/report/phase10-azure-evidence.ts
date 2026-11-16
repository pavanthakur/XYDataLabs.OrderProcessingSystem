import { createHash } from "node:crypto";

export type AzureEvidenceStatus = "PASS" | "FAIL" | "BLOCKED" | "NOT-RUN";

export interface AzureEvidenceGate {
  id: string;
  status: AzureEvidenceStatus;
  sourceStatus: string;
  provenance: "BOUND" | "UNBOUND" | "MISSING";
}

export interface AzureEvidenceReport {
  environment: "dev" | "UNKNOWN";
  runnerRevisions: string[];
  gates: AzureEvidenceGate[];
  completeness: "COMPLETE" | "INCOMPLETE";
  verdict: "PASS" | "FAIL" | "BLOCKED";
}

export const PHASE10_AZURE_EVIDENCE_REQUIRED_FILES = [
  "deployment-identity.json", "runtime-smoke.json", "identity.json", "payment-matrix-summary.json",
  "transport-smoke.json", "functions-replay.json", "recovery-nfr.json", "rollback.json", "restoration.json"
] as const;

export interface AzureEvidenceFileManifest {
  schema: "phase10-azure-evidence-manifest-v1";
  environment: "dev";
  files: { name: string; sha256: string }[];
  gateSources: Record<string, string[]>;
}

export function verifyAzureEvidenceFileManifest(manifest: unknown, actualFiles: Record<string, string>): {
  valid: boolean;
  verifiedByGate: Record<string, string[]>;
} {
  const source = asRecord(manifest);
  if (!source || source.schema !== "phase10-azure-evidence-manifest-v1" || source.environment !== "dev" ||
      !Array.isArray(source.files) || source.files.length === 0) return { valid: false, verifiedByGate: {} };
  const names = new Set<string>();
  const verifiedByName = new Map<string, string>();
  for (const value of source.files) {
    const file = asRecord(value);
    if (!file || typeof file.name !== "string" || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(file.name) ||
        file.name === ".." || typeof file.sha256 !== "string" || !/^[a-f0-9]{64}$/i.test(file.sha256) ||
        names.has(file.name.toLowerCase())) return { valid: false, verifiedByGate: {} };
    const actual = actualFiles[file.name];
    if (!actual || actual.toLowerCase() !== file.sha256.toLowerCase()) return { valid: false, verifiedByGate: {} };
    names.add(file.name.toLowerCase());
    verifiedByName.set(file.name.toLowerCase(), actual.toLowerCase());
  }
  if (Object.keys(actualFiles).some(name => !names.has(name.toLowerCase()))) return { valid: false, verifiedByGate: {} };
  if (PHASE10_AZURE_EVIDENCE_REQUIRED_FILES.some(name => !names.has(name.toLowerCase()))) return { valid: false, verifiedByGate: {} };
  const gateSources = asRecord(source.gateSources);
  const gateIds = ["identity", "payments", "transport-functions", "recovery-nfr", "rollback", "restoration"];
  if (!gateSources || Object.keys(gateSources).length !== gateIds.length || gateIds.some(id => !Array.isArray(gateSources[id]))) {
    return { valid: false, verifiedByGate: {} };
  }
  const verifiedByGate: Record<string, string[]> = {};
  const gateContractFiles: Record<string, string> = {
    identity: "identity.json", payments: "payment-matrix-summary.json", "transport-functions": "functions-replay.json",
    "recovery-nfr": "recovery-nfr.json", rollback: "rollback.json", restoration: "restoration.json"
  };
  for (const id of gateIds) {
    const files = gateSources[id] as unknown[];
    if (files.length === 0 || files.some(name => typeof name !== "string" || !verifiedByName.has(name.toLowerCase()) ||
        name.toLowerCase() === gateContractFiles[id])) {
      return { valid: false, verifiedByGate: {} };
    }
    const hashes = files.map(name => verifiedByName.get((name as string).toLowerCase())!);
    if (new Set(hashes).size !== hashes.length) return { valid: false, verifiedByGate: {} };
    verifiedByGate[id] = hashes;
  }
  return { valid: true, verifiedByGate };
}

export const PHASE10_AZURE_EVIDENCE_REQUIRED_GATES = [
  "deployment-provenance", "runtime-smoke", "identity", "payments", "transport-functions",
  "recovery-nfr", "rollback", "restoration"
] as const;
const applicationServices = ["gateway", "inventory", "notifications", "orders", "payments", "ui"] as const;

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value)) : undefined;
}

function asRevision(value: unknown): string | undefined {
  return typeof value === "string" && /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/i.test(value) ? value.toLowerCase() : undefined;
}

export function computeAzureDeploymentIdentitySha256(value: {
  sourceRevision: string;
  configurationIdentitySha256: string;
  functionsPackageSha256: string;
  applicationImages: { service: string; digest: string }[];
}): string {
  const canonical = JSON.stringify({
    environment: "dev",
    sourceRevision: value.sourceRevision.toLowerCase(),
    configurationIdentitySha256: value.configurationIdentitySha256.toLowerCase(),
    functionsPackageSha256: value.functionsPackageSha256.toLowerCase(),
    applicationImages: [...value.applicationImages]
      .sort((left, right) => left.service < right.service ? -1 : left.service > right.service ? 1 : 0)
      .map(image => ({ service: image.service, digest: image.digest.toLowerCase() }))
  });
  return createHash("sha256").update(canonical, "utf8").digest("hex");
}

function smokeStatus(value: unknown, schema: string): { status: AzureEvidenceStatus; sourceStatus: string; revision?: string; deploymentIdentity?: string } {
  const source = asRecord(value);
  if (!source || source.schema !== schema || source.environment !== "dev" ||
      (source.status !== "passed" && source.status !== "failed") || !Array.isArray(source.checks) || source.checks.length === 0) {
    return { status: "BLOCKED", sourceStatus: "MISSING_OR_INVALID" };
  }
  const validChecks = source.checks.every(item => {
    const check = asRecord(item);
    return !!check && typeof check.name === "string" && /^[A-Za-z0-9._-]{1,80}$/.test(check.name) &&
      (check.status === "passed" || check.status === "failed");
  });
  const deploymentIdentity = typeof source.deploymentIdentitySha256 === "string" && /^[a-f0-9]{64}$/i.test(source.deploymentIdentitySha256)
    ? source.deploymentIdentitySha256.toLowerCase() : undefined;
  if (!validChecks) return { status: "BLOCKED", sourceStatus: "MALFORMED_CHECKS", revision: asRevision(source.sourceRevision), deploymentIdentity };
  const failedCheck = source.checks.some(item => asRecord(item)?.status === "failed");
  const status = source.status === "failed" || failedCheck ? "FAIL" : "PASS";
  if (source.status === "passed" && failedCheck) return { status: "FAIL", sourceStatus: "CONTRADICTORY", revision: asRevision(source.sourceRevision), deploymentIdentity };
  return { status, sourceStatus: status, revision: asRevision(source.sourceRevision), deploymentIdentity };
}

function timestamp(value: unknown): number | undefined {
  if (typeof value !== "string") return undefined;
  const milliseconds = Date.parse(value);
  return Number.isFinite(milliseconds) ? milliseconds : undefined;
}

function passed(value: unknown): boolean {
  return value === "passed";
}

function validTenantCodes(value: unknown): string[] | undefined {
  if (!Array.isArray(value) || value.length === 0 || value.some(item => typeof item !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(item))) return undefined;
  const codes = value as string[];
  return new Set(codes.map(code => code.toLowerCase())).size === codes.length ? codes : undefined;
}

function sourceHashes(value: unknown): boolean {
  return Array.isArray(value) && value.length > 0 && value.every(hash => typeof hash === "string" && /^[a-f0-9]{64}$/i.test(hash));
}

function normalizeBoundGate(value: unknown, schema: string, gateId: string, deploymentIdentity: string | undefined,
  verifiedSourceSha256: readonly string[],
  validateDetails: (source: Record<string, unknown>) => "PASS" | "FAIL" | "BLOCKED"): AzureEvidenceGate {
  const source = asRecord(value);
  const sourceStatus = typeof source?.status === "string" && /^[a-z-]{1,40}$/.test(source.status) ? source.status.toUpperCase() : "MISSING_OR_INVALID";
  if (!source || source.schema !== schema || source.environment !== "dev" ||
      (source.status !== "passed" && source.status !== "failed") || !asRevision(source.runnerRevision) ||
      source.deploymentIdentitySha256 !== deploymentIdentity || !deploymentIdentity ||
      timestamp(source.startedUtc) === undefined || timestamp(source.completedUtc) === undefined ||
      timestamp(source.completedUtc)! < timestamp(source.startedUtc)! || !sourceHashes(source.sourceEvidenceSha256) ||
      new Set((source.sourceEvidenceSha256 as string[]).map(hash => hash.toLowerCase())).size !== verifiedSourceSha256.length ||
      (source.sourceEvidenceSha256 as string[]).map(hash => hash.toLowerCase()).sort().join("|") !== [...verifiedSourceSha256].map(hash => hash.toLowerCase()).sort().join("|")) {
    return { id: gateId, status: "BLOCKED", sourceStatus: "CONTRACT_OR_PROVENANCE_INVALID", provenance: source?.deploymentIdentitySha256 ? "UNBOUND" : "MISSING" };
  }
  if (source.status === "failed") return { id: gateId, status: "FAIL", sourceStatus, provenance: "BOUND" };
  const detailStatus = validateDetails(source);
  return { id: gateId, status: detailStatus, sourceStatus: detailStatus === "PASS" ? sourceStatus
    : detailStatus === "FAIL" ? "REQUIRED_CHECK_FAILED" : "REQUIRED_EVIDENCE_MISSING", provenance: "BOUND" };
}

function normalizeIdentity(value: unknown, deploymentIdentity: string | undefined, verified: readonly string[]): AzureEvidenceGate {
  return normalizeBoundGate(value, "phase10-azure-identity-evidence-v1", "identity", deploymentIdentity, verified, source => {
    const tenants = validTenantCodes(source.activeTenantCodes);
    const isolation = Array.isArray(source.regularUserIsolation) ? source.regularUserIsolation.map(asRecord) : [];
    if (!tenants) return "BLOCKED";
    const scalarChecks = ["adminTenantSwitching", "forgedTenantHeaderDenied", "expiredTokenRejected", "wrongAudienceRejected",
      "unauthorizedDeepLinkDenied", "crossTabLogout"];
    const scalarValues = scalarChecks.map(name => source[name]);
    if (scalarValues.some(result => result === "failed") || isolation.some(item => item?.status === "failed")) return "FAIL";
    if (scalarValues.some(result => result !== "passed") || isolation.length !== tenants.length * tenants.length) return "BLOCKED";
    const pairs = new Set<string>();
    for (const item of isolation) {
      if (!item || typeof item.assignedTenantCode !== "string" || typeof item.requestedTenantCode !== "string" ||
          !tenants.includes(item.assignedTenantCode) || !tenants.includes(item.requestedTenantCode) ||
          !["allowed", "denied"].includes(String(item.result))) return "BLOCKED";
      const key = `${item.assignedTenantCode.toLowerCase()}|${item.requestedTenantCode.toLowerCase()}`;
      if (pairs.has(key)) return "BLOCKED";
      pairs.add(key);
      const expected = item.assignedTenantCode === item.requestedTenantCode ? "allowed" : "denied";
      if (item.status !== "passed" || item.result !== expected) return "FAIL";
    }
    if (pairs.size !== tenants.length * tenants.length) return "BLOCKED";
    return "PASS";
  });
}

function normalizePayments(value: unknown, deploymentIdentity: string | undefined, verified: readonly string[]): AzureEvidenceGate {
  return normalizeBoundGate(value, "phase10-azure-payment-evidence-v1", "payments", deploymentIdentity, verified, source => {
    const tenants = validTenantCodes(source.activeTenantCodes);
    const cases = Array.isArray(source.cases) ? source.cases.map(asRecord) : [];
    if (!tenants || cases.length !== tenants.length * 2) return "BLOCKED";
    const keys = new Set<string>();
    for (const item of cases) {
      if (!item || typeof item.tenantCode !== "string" || !tenants.some(tenant => tenant === item.tenantCode) ||
          !["Razorpay", "OpenPay"].includes(String(item.provider))) return "BLOCKED";
      const key = `${item.tenantCode.toLowerCase()}|${String(item.provider).toLowerCase()}`;
      if (keys.has(key)) return "BLOCKED";
      keys.add(key);
      const checks = ["freshOrder", "providerConfirmed", "callbackValidated", "sqlCorrelated", "amountCurrencyMatched",
        "uniqueSuccessfulCharge", "paidOrderProjection", "restorationVerified"];
      if (item.status === "failed" || item.adapterMode !== undefined && item.adapterMode !== "sandbox" ||
          checks.some(name => item[name] === false)) return "FAIL";
      if (item.status !== "passed" || item.adapterMode !== "sandbox" || checks.some(name => item[name] !== true)) return "BLOCKED";
    }
    return tenants.every(tenant => keys.has(`${tenant.toLowerCase()}|razorpay`) && keys.has(`${tenant.toLowerCase()}|openpay`)) ? "PASS" : "BLOCKED";
  });
}

function normalizeTransportFunctions(value: unknown, deploymentIdentity: string | undefined, verified: readonly string[]): AzureEvidenceGate {
  const required = ["publishConsumed", "durableEffects", "brokerDlqForwarding", "functionsQuarantine",
    "protectedReplayApproval", "functionsReplayProcessed", "duplicateDeliveryNoExtraEffects", "noCrossTenantEffects"];
  return normalizeBoundGate(value, "phase10-azure-functions-evidence-v1", "transport-functions", deploymentIdentity, verified, source => {
    const checks = asRecord(source.checks);
    if (!checks) return "BLOCKED";
    if (required.some(name => checks[name] === "failed")) return "FAIL";
    return required.every(name => checks[name] === "passed") ? "PASS" : "BLOCKED";
  });
}

function normalizeRecovery(value: unknown, deploymentIdentity: string | undefined, verified: readonly string[]): AzureEvidenceGate {
  return normalizeBoundGate(value, "phase10-azure-recovery-evidence-v1", "recovery-nfr", deploymentIdentity, verified, source => {
    const metrics = asRecord(source.metrics);
    if (!metrics) return "BLOCKED";
    const requiredNumbers = ["messagesSent", "messagesConsumed", "durableEffects", "consumerP95Seconds", "replayVisibilitySeconds",
      "lostCommittedMessages", "duplicateBusinessEffects", "recoverySeconds"];
    if (requiredNumbers.some(name => typeof metrics[name] !== "number" || !Number.isFinite(metrics[name]))) return "BLOCKED";
    const number = (name: string): number => metrics[name] as number;
    const okay = number("messagesSent") === 100 && number("messagesConsumed") === 100 && number("durableEffects") === 100 &&
      number("consumerP95Seconds") < 30 && number("replayVisibilitySeconds") < 60 && number("lostCommittedMessages") === 0 &&
      number("duplicateBusinessEffects") === 0 && number("recoverySeconds") <= 1800;
    return okay ? "PASS" : "FAIL";
  });
}

function normalizeRollback(value: unknown, deploymentIdentity: string | undefined, verified: readonly string[]): AzureEvidenceGate {
  return normalizeBoundGate(value, "phase10-azure-rollback-evidence-v1", "rollback", deploymentIdentity, verified, source => {
    const required = ["previousArtifactVerified", "rollbackExecuted", "healthVerifiedAfterRollback", "candidateRestored", "durableStatePreserved", "databaseRollbackAttempted"];
    if (required.some(name => typeof source[name] !== "boolean") || typeof source.previousImageDigest !== "string") return "BLOCKED";
    if (/^[^\s@]+@sha256:[a-f0-9]{64}$/i.test(source.previousImageDigest) === false) return "BLOCKED";
    return source.previousArtifactVerified === true && source.rollbackExecuted === true && source.healthVerifiedAfterRollback === true &&
      source.candidateRestored === true && source.durableStatePreserved === true && source.databaseRollbackAttempted === false ? "PASS" : "FAIL";
  });
}

function normalizeRestoration(value: unknown, deploymentIdentity: string | undefined, verified: readonly string[]): AzureEvidenceGate {
  return normalizeBoundGate(value, "phase10-azure-restoration-evidence-v1", "restoration", deploymentIdentity, verified, source => {
    const required = ["providerSettingsRestored", "fixtureLocksAbsent", "firewallLeasesRemoved", "temporaryConfigurationRestored", "ownedResourcesReconciled"];
    if (required.some(name => typeof source[name] !== "boolean")) return "BLOCKED";
    return required.every(name => source[name] === true) ? "PASS" : "FAIL";
  });
}

/**
 * Summarizes optional Azure artifacts alongside the local report. Azure gates
 * remain blocked unless their evidence is present and tied to deployment
 * provenance; this preview never certifies the cloud acceptance run.
 */
export function normalizeAzureEvidence(input: {
  runtime?: unknown;
  transport?: unknown;
  deployment?: unknown;
  identity?: unknown;
  payments?: unknown;
  transportFunctions?: unknown;
  recovery?: unknown;
  rollback?: unknown;
  restoration?: unknown;
  evidenceManifest?: unknown;
  actualEvidenceFiles?: Record<string, string>;
} = {}): AzureEvidenceReport {
  const verifiedManifest = verifyAzureEvidenceFileManifest(input.evidenceManifest, input.actualEvidenceFiles ?? {});
  const verifiedByGate = verifiedManifest.valid ? verifiedManifest.verifiedByGate : {};
  const runtime = smokeStatus(input.runtime, "phase10-azure-runtime-smoke-v1");
  const transport = smokeStatus(input.transport, "phase10-azure-transport-smoke-v1");
  const deployment = asRecord(input.deployment);
  const images = Array.isArray(deployment?.applicationImages) ? deployment.applicationImages.map(asRecord) : [];
  const imageServices = images.map(image => image?.service).filter((value): value is string => typeof value === "string");
  const validImages = images.length === applicationServices.length && imageServices.length === images.length &&
    new Set(imageServices).size === imageServices.length && applicationServices.every(service => imageServices.includes(service)) &&
    images.every(image => typeof image?.digest === "string" &&
      /^[^\s@]+@sha256:[a-f0-9]{64}$/i.test(image.digest));
  const sourceRevision = asRevision(deployment?.sourceRevision);
  const configurationIdentitySha256 = typeof deployment?.configurationIdentitySha256 === "string" && /^[a-f0-9]{64}$/i.test(deployment.configurationIdentitySha256)
    ? deployment.configurationIdentitySha256 : undefined;
  const functionsPackageSha256 = typeof deployment?.functionsPackageSha256 === "string" && /^[a-f0-9]{64}$/i.test(deployment.functionsPackageSha256)
    ? deployment.functionsPackageSha256 : undefined;
  const identitySha256 = typeof deployment?.identitySha256 === "string" && /^[a-f0-9]{64}$/i.test(deployment.identitySha256)
    ? deployment.identitySha256.toLowerCase() : undefined;
  const deploymentBound = deployment?.schema === "phase10-azure-deployment-identity-v1" && deployment.environment === "dev" &&
    sourceRevision !== undefined && configurationIdentitySha256 !== undefined && functionsPackageSha256 !== undefined &&
    identitySha256 !== undefined && validImages && computeAzureDeploymentIdentitySha256({ sourceRevision, configurationIdentitySha256,
      functionsPackageSha256, applicationImages: images.map(image => ({ service: image!.service as string, digest: image!.digest as string })) }) === identitySha256;
  const deploymentSourceStatus = deploymentBound ? "BOUND" : "MISSING_OR_INVALID";
  const deploymentIdentity = deploymentBound ? identitySha256 : undefined;
  const runtimeRevisionMatches = deploymentBound && runtime.deploymentIdentity === deploymentIdentity;
  const transportRevisionMatches = deploymentBound && transport.deploymentIdentity === deploymentIdentity;

  const gates: AzureEvidenceGate[] = [
    { id: "deployment-provenance", status: deploymentBound ? "PASS" : "BLOCKED", sourceStatus: deploymentSourceStatus, provenance: deploymentBound ? "BOUND" : "MISSING" },
    { id: "runtime-smoke", status: runtime.status === "FAIL" ? "FAIL" : runtime.status === "PASS" && runtime.revision && runtimeRevisionMatches ? "PASS" : "BLOCKED",
      sourceStatus: runtime.status === "PASS" && !runtime.revision ? "RUNNER_REVISION_MISSING" : runtime.sourceStatus,
      provenance: runtime.deploymentIdentity ? (runtimeRevisionMatches ? "BOUND" : "UNBOUND") : "MISSING" },
    normalizeIdentity(input.identity, deploymentIdentity, verifiedByGate.identity ?? []),
    normalizePayments(input.payments, deploymentIdentity, verifiedByGate.payments ?? []),
    { ...normalizeTransportFunctions(input.transportFunctions, deploymentIdentity, verifiedByGate["transport-functions"] ?? []),
      ...(transport.status === "FAIL" ? { status: "FAIL" as const, sourceStatus: "TRANSPORT_SMOKE_FAILED" } : {}) },
    normalizeRecovery(input.recovery, deploymentIdentity, verifiedByGate["recovery-nfr"] ?? []),
    normalizeRollback(input.rollback, deploymentIdentity, verifiedByGate.rollback ?? []),
    normalizeRestoration(input.restoration, deploymentIdentity, verifiedByGate.restoration ?? [])
  ];
  const allSourcesPresent = gates.every(gate => gate.status === "PASS" || gate.status === "FAIL");
  const verdict = gates.some(gate => gate.status === "FAIL") ? "FAIL"
    : allSourcesPresent && gates.every(gate => gate.status === "PASS") ? "PASS" : "BLOCKED";
  return {
    environment: deploymentBound ? "dev" : "UNKNOWN",
    runnerRevisions: [...new Set([runtime.revision, transport.revision].filter((value): value is string => !!value))],
    gates,
    completeness: allSourcesPresent ? "COMPLETE" : "INCOMPLETE",
    verdict
  };
}
