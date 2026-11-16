import assert from "node:assert/strict";
import { test } from "node:test";
import { computeAzureDeploymentIdentitySha256, normalizeAzureEvidence, PHASE10_AZURE_EVIDENCE_REQUIRED_GATES,
  PHASE10_AZURE_EVIDENCE_REQUIRED_FILES, verifyAzureEvidenceFileManifest } from "./phase10-azure-evidence.js";

const revision = "b".repeat(40);

function smoke(schema: string, changes: Record<string, unknown> = {}) {
  return {
    schema, status: "passed", environment: "dev", sourceRevision: revision,
    deploymentIdentitySha256: deployment().identitySha256,
    startedUtc: "2026-11-16T10:00:00Z", completedUtc: "2026-11-16T10:01:00Z",
    checks: [{ name: "health", status: "passed" }], ...changes
  };
}

function deployment() {
  const value = {
    sourceRevision: revision,
    configurationIdentitySha256: "d".repeat(64),
    functionsPackageSha256: "e".repeat(64),
    applicationImages: ["gateway", "inventory", "notifications", "orders", "payments", "ui"]
      .map((service, index) => ({ service, digest: `registry.example/${service}@sha256:${String(index + 1).repeat(64)}` }))
  };
  return { schema: "phase10-azure-deployment-identity-v1", environment: "dev", ...value,
    identitySha256: computeAzureDeploymentIdentitySha256(value) };
}

const gateIds = ["identity", "payments", "transport-functions", "recovery-nfr", "rollback", "restoration"] as const;
const gateDigests = Object.fromEntries(gateIds.map((gate, index) => [gate, String(index + 1).repeat(64)])) as Record<typeof gateIds[number], string>;

function boundEvidence(schema: string, gate: typeof gateIds[number], changes: Record<string, unknown> = {}) {
  return {
    schema, environment: "dev", status: "passed", runnerRevision: revision,
    deploymentIdentitySha256: deployment().identitySha256,
    startedUtc: "2026-11-16T10:00:00Z", completedUtc: "2026-11-16T10:01:00Z",
    sourceEvidenceSha256: [gateDigests[gate]], ...changes
  };
}

const evidenceIntegrity = {
  evidenceManifest: { schema: "phase10-azure-evidence-manifest-v1", environment: "dev",
    files: [
      ...PHASE10_AZURE_EVIDENCE_REQUIRED_FILES.map((name, index) => ({ name, sha256: (index + 7).toString(16).repeat(64) })),
      ...gateIds.map(gate => ({ name: `fixture-${gate}.json`, sha256: gateDigests[gate] }))
    ],
    gateSources: Object.fromEntries(gateIds.map(gate => [gate, [`fixture-${gate}.json`]])) },
  actualEvidenceFiles: Object.fromEntries([
    ...PHASE10_AZURE_EVIDENCE_REQUIRED_FILES.map((name, index) => [name, (index + 7).toString(16).repeat(64)]),
    ...gateIds.map(gate => [`fixture-${gate}.json`, gateDigests[gate]])
  ])
};

function completeAzureEvidence() {
  const activeTenantCodes = ["TenantA", "TenantB", "TenantC"];
  const identity = boundEvidence("phase10-azure-identity-evidence-v1", "identity", {
    activeTenantCodes, adminTenantSwitching: "passed", forgedTenantHeaderDenied: "passed", expiredTokenRejected: "passed",
    wrongAudienceRejected: "passed", unauthorizedDeepLinkDenied: "passed", crossTabLogout: "passed",
    regularUserIsolation: activeTenantCodes.flatMap(assignedTenantCode => activeTenantCodes.map(requestedTenantCode => ({
      assignedTenantCode, requestedTenantCode, result: assignedTenantCode === requestedTenantCode ? "allowed" : "denied", status: "passed"
    })))
  });
  const cases = activeTenantCodes.flatMap(tenantCode => ["Razorpay", "OpenPay"].map(provider => ({
    tenantCode, provider, status: "passed", adapterMode: "sandbox", freshOrder: true, providerConfirmed: true,
    callbackValidated: true, sqlCorrelated: true, amountCurrencyMatched: true, uniqueSuccessfulCharge: true,
    paidOrderProjection: true, restorationVerified: true
  })));
  const payments = boundEvidence("phase10-azure-payment-evidence-v1", "payments", { activeTenantCodes, cases });
  const functions = boundEvidence("phase10-azure-functions-evidence-v1", "transport-functions", { checks: {
    publishConsumed: "passed", durableEffects: "passed", brokerDlqForwarding: "passed", functionsQuarantine: "passed",
    protectedReplayApproval: "passed", functionsReplayProcessed: "passed", duplicateDeliveryNoExtraEffects: "passed", noCrossTenantEffects: "passed"
  } });
  const recovery = boundEvidence("phase10-azure-recovery-evidence-v1", "recovery-nfr", { metrics: {
    messagesSent: 100, messagesConsumed: 100, durableEffects: 100, consumerP95Seconds: 2.5,
    replayVisibilitySeconds: 12, lostCommittedMessages: 0, duplicateBusinessEffects: 0, recoverySeconds: 120
  } });
  const rollback = boundEvidence("phase10-azure-rollback-evidence-v1", "rollback", { previousArtifactVerified: true,
    previousImageDigest: `registry.example/app@sha256:${"2".repeat(64)}`, rollbackExecuted: true,
    healthVerifiedAfterRollback: true, candidateRestored: true, durableStatePreserved: true, databaseRollbackAttempted: false });
  const restoration = boundEvidence("phase10-azure-restoration-evidence-v1", "restoration", { providerSettingsRestored: true,
    fixtureLocksAbsent: true, firewallLeasesRemoved: true, temporaryConfigurationRestored: true, ownedResourcesReconciled: true });
  return { identity, payments, transportFunctions: functions, recovery, rollback, restoration };
}

test("missing Azure evidence remains incomplete and cannot produce PASS", () => {
  const report = normalizeAzureEvidence();
  assert.equal(report.environment, "UNKNOWN");
  assert.equal(report.completeness, "INCOMPLETE");
  assert.equal(report.verdict, "BLOCKED");
  assert.deepEqual(report.gates.map(gate => gate.id), PHASE10_AZURE_EVIDENCE_REQUIRED_GATES);
  assert.ok(report.gates.every(gate => gate.status === "BLOCKED"));
});

test("runtime and transport summaries require matching deployment identity before provenance can pass", () => {
  const report = normalizeAzureEvidence({
    deployment: deployment(),
    runtime: smoke("phase10-azure-runtime-smoke-v1"),
    transport: smoke("phase10-azure-transport-smoke-v1")
  });
  assert.equal(report.environment, "dev");
  assert.equal(report.gates.find(gate => gate.id === "deployment-provenance")?.status, "PASS");
  assert.equal(report.gates.find(gate => gate.id === "runtime-smoke")?.status, "PASS");
  assert.equal(report.gates.find(gate => gate.id === "transport-functions")?.status, "BLOCKED");
  assert.equal(report.verdict, "BLOCKED");
  assert.equal(report.completeness, "INCOMPLETE");
});

test("missing or mismatched deployment identity blocks otherwise green smoke evidence", () => {
  const missingBinding = normalizeAzureEvidence({ runtime: smoke("phase10-azure-runtime-smoke-v1") });
  assert.equal(missingBinding.gates.find(gate => gate.id === "runtime-smoke")?.status, "BLOCKED");
  const mismatch = normalizeAzureEvidence({
    deployment: deployment(),
    runtime: smoke("phase10-azure-runtime-smoke-v1", { deploymentIdentitySha256: "f".repeat(64) })
  });
  assert.equal(mismatch.gates.find(gate => gate.id === "runtime-smoke")?.provenance, "UNBOUND");
  assert.equal(mismatch.gates.find(gate => gate.id === "runtime-smoke")?.status, "BLOCKED");
  const incompleteServices = deployment();
  incompleteServices.applicationImages = incompleteServices.applicationImages.slice(1);
  const incomplete = normalizeAzureEvidence({ deployment: incompleteServices });
  assert.equal(incomplete.gates.find(gate => gate.id === "deployment-provenance")?.status, "BLOCKED");
  const altered = deployment();
  altered.configurationIdentitySha256 = "f".repeat(64);
  const alteredConfig = normalizeAzureEvidence({ deployment: altered });
  assert.equal(alteredConfig.gates.find(gate => gate.id === "deployment-provenance")?.status, "BLOCKED");
});

test("malformed and contradictory smoke results are blocked or failed without copying untrusted text", () => {
  const malformed = normalizeAzureEvidence({
    runtime: smoke("phase10-azure-runtime-smoke-v1", { checks: [{ name: "<script>secret</script>", status: "passed" }] })
  });
  assert.equal(malformed.gates.find(gate => gate.id === "runtime-smoke")?.status, "BLOCKED");
  assert.doesNotMatch(JSON.stringify(malformed), /script|secret/);
  const contradictory = normalizeAzureEvidence({
    runtime: smoke("phase10-azure-runtime-smoke-v1", { checks: [{ name: "health", status: "failed" }] })
  });
  assert.equal(contradictory.gates.find(gate => gate.id === "runtime-smoke")?.status, "FAIL");
});

test("gate-specific identity, payment, Functions, recovery, rollback and restoration contracts can reconcile", () => {
  const integrity = verifyAzureEvidenceFileManifest(evidenceIntegrity.evidenceManifest, evidenceIntegrity.actualEvidenceFiles);
  assert.equal(integrity.valid, true, JSON.stringify({ integrity, manifest: evidenceIntegrity.evidenceManifest, actual: evidenceIntegrity.actualEvidenceFiles }));
  const report = normalizeAzureEvidence({
    deployment: deployment(), runtime: smoke("phase10-azure-runtime-smoke-v1"),
    transport: smoke("phase10-azure-transport-smoke-v1"), ...completeAzureEvidence(), ...evidenceIntegrity
  });
  assert.equal(report.completeness, "COMPLETE", JSON.stringify(report.gates));
  assert.equal(report.verdict, "PASS");
  assert.ok(report.gates.every(gate => gate.status === "PASS" && gate.provenance === "BOUND"));
});

test("identity and payment contracts reject missing tenant/provider coverage and explicit failures", () => {
  const evidence = completeAzureEvidence();
  const payments = evidence.payments as Record<string, unknown>;
  const paymentCases = payments.cases as Record<string, unknown>[];
  const incompletePayment = { ...payments, cases: paymentCases.slice(1) };
  const paymentReport = normalizeAzureEvidence({ deployment: deployment(), payments: incompletePayment, ...evidenceIntegrity });
  assert.equal(paymentReport.gates.find(gate => gate.id === "payments")?.status, "BLOCKED");
  const declined = { ...payments, cases: paymentCases.map((item, index) => index ? item : { ...item, providerConfirmed: false }) };
  assert.equal(normalizeAzureEvidence({ deployment: deployment(), payments: declined, ...evidenceIntegrity }).gates.find(gate => gate.id === "payments")?.status, "FAIL");
  const identity = evidence.identity as Record<string, unknown>;
  const missingIdentity = { ...identity, regularUserIsolation: (identity.regularUserIsolation as Record<string, unknown>[]).slice(1) };
  assert.equal(normalizeAzureEvidence({ deployment: deployment(), identity: missingIdentity, ...evidenceIntegrity }).gates.find(gate => gate.id === "identity")?.status, "BLOCKED");
  const crossTenantAllowed = (identity.regularUserIsolation as Record<string, unknown>[]).map(item => item.assignedTenantCode === "TenantA" && item.requestedTenantCode === "TenantB"
    ? { ...item, result: "allowed" } : item);
  assert.equal(normalizeAzureEvidence({ deployment: deployment(), identity: { ...identity, regularUserIsolation: crossTenantAllowed }, ...evidenceIntegrity })
    .gates.find(gate => gate.id === "identity")?.status, "FAIL");
});

test("recovery thresholds, rollback execution and exact restoration fail closed", () => {
  const evidence = completeAzureEvidence();
  const recovery = evidence.recovery as Record<string, unknown>;
  const slowRecovery = { ...recovery, metrics: { ...(recovery.metrics as Record<string, unknown>), consumerP95Seconds: 30 } };
  assert.equal(normalizeAzureEvidence({ deployment: deployment(), recovery: slowRecovery, ...evidenceIntegrity }).gates.find(gate => gate.id === "recovery-nfr")?.status, "FAIL");
  const rollback = evidence.rollback as Record<string, unknown>;
  const missingRollback = { ...rollback, previousArtifactVerified: false };
  assert.equal(normalizeAzureEvidence({ deployment: deployment(), rollback: missingRollback, ...evidenceIntegrity }).gates.find(gate => gate.id === "rollback")?.status, "FAIL");
  const restoration = evidence.restoration as Record<string, unknown>;
  const unrestored = { ...restoration, firewallLeasesRemoved: false };
  assert.equal(normalizeAzureEvidence({ deployment: deployment(), restoration: unrestored, ...evidenceIntegrity }).gates.find(gate => gate.id === "restoration")?.status, "FAIL");
});

test("gate evidence hashes must match hashes computed from the manifest's actual files", () => {
  const evidence = completeAzureEvidence();
  const identity = evidence.identity as Record<string, unknown>;
  const report = normalizeAzureEvidence({
    deployment: deployment(), identity: { ...identity, sourceEvidenceSha256: [gateDigests.payments] }, ...evidenceIntegrity
  });
  assert.equal(report.gates.find(gate => gate.id === "identity")?.status, "BLOCKED");
});

test("Azure file manifest rejects altered bytes, unsafe names, duplicates and unlisted inputs", () => {
  const digest = "a".repeat(64);
  const requiredFiles = PHASE10_AZURE_EVIDENCE_REQUIRED_FILES.map((name, index) => ({ name, sha256: (index + 1).toString(16).repeat(64) }));
  const actualFiles = Object.fromEntries(requiredFiles.map(file => [file.name, file.sha256]));
  const valid = { schema: "phase10-azure-evidence-manifest-v1", environment: "dev",
    files: [...requiredFiles, { name: "details.json", sha256: digest }],
    gateSources: Object.fromEntries(["identity", "payments", "transport-functions", "recovery-nfr", "rollback", "restoration"]
      .map(gate => [gate, ["details.json"]])) };
  assert.deepEqual(verifyAzureEvidenceFileManifest(valid, { ...actualFiles, "details.json": digest }), {
    valid: true, verifiedByGate: Object.fromEntries(["identity", "payments", "transport-functions", "recovery-nfr", "rollback", "restoration"]
      .map(gate => [gate, [digest]]))
  });
  assert.equal(verifyAzureEvidenceFileManifest(valid, { ...actualFiles, "details.json": "b".repeat(64) }).valid, false);
  assert.equal(verifyAzureEvidenceFileManifest({ ...valid, files: [...requiredFiles, { name: "../details.json", sha256: digest }] }, { ...actualFiles, "../details.json": digest }).valid, false);
  assert.equal(verifyAzureEvidenceFileManifest({ ...valid, files: [...valid.files, ...valid.files] }, { ...actualFiles, "details.json": digest }).valid, false);
  assert.equal(verifyAzureEvidenceFileManifest({ ...valid, files: valid.files.filter(file => file.name !== "identity.json") }, { ...actualFiles, "details.json": digest }).valid, false);
  assert.equal(verifyAzureEvidenceFileManifest(valid, { ...actualFiles, "details.json": digest, "unexpected.json": digest }).valid, false);
});
