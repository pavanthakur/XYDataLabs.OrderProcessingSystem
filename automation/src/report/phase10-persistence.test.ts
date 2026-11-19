import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";
import { normalizePhase10PersistenceEvidence } from "./phase10-persistence.js";

const commit = "a".repeat(40);
const runId = "phase10-persistence-20261120-000000001";
const rows = [
  { tenant: "TenantA", database: "Shared", orderId: 10, reference: "ref-a", amount: 200, currency: "INR", status: "Paid" },
  { tenant: "TenantB", database: "Shared", orderId: 20, reference: "ref-b", amount: 200, currency: "INR", status: "Paid" },
  { tenant: "TenantC", database: "Dedicated", orderId: 30, reference: "ref-c", amount: 200, currency: "MXN", status: "Paid" }
];
const digest = (text: string) => createHash("sha256").update(text, "utf8").digest("hex");
const services = ["azurite", "functions", "gateway", "inventory", "keycloak-local", "notifications", "orders", "payments", "redis", "servicebus-emulator", "servicebus-sql", "sql-server", "ui"];
const images = services.map((service, index) => ({ project: "xy-phase10", service, imageId: `sha256:${String(index + 1).padStart(64, "0")}` }));
const candidate = { commit, worktree: "clean" };
const manifest = (capturePoint: string) => ({ schema: "phase10-docker-image-identities-v1", runId, capturePoint, candidate, images });

function fixture() {
  const beforeText = JSON.stringify(rows);
  const afterText = JSON.stringify(rows);
  const beforeImageText = JSON.stringify(manifest("before"));
  const afterImageText = JSON.stringify(manifest("after"));
  return {
    summary: { status: "passed", runId, candidate, disk: "G:\\DockerStorage\\DockerDesktopWSL", sqlVolume: "xy-phase10_phase10-sql-data",
      publicEndpointsReachable: true, imageIdentitiesUnchanged: true, nativeSqlBefore: [7092], nativeSqlAfter: [7092],
      evidenceSha256: { before: digest(beforeText), after: digest(afterText), imageBefore: digest(beforeImageText), imageAfter: digest(afterImageText) } },
    before: JSON.parse(beforeText), after: JSON.parse(afterText), beforeTextSha256: digest(beforeText), afterTextSha256: digest(afterText),
    imageBefore: JSON.parse(beforeImageText), imageAfter: JSON.parse(afterImageText),
    imageBeforeSha256: digest(beforeImageText), imageAfterSha256: digest(afterImageText),
    parentGitProvenance: { start: { ...candidate, contentIdentity: "b".repeat(64) }, finish: { ...candidate, contentIdentity: "b".repeat(64) } },
    parentImageBefore: manifest("before"), parentImageAfter: manifest("after")
  };
}

test("supplemental persistence evidence passes only with exact snapshot, image and candidate reconciliation", () => {
  const result = normalizePhase10PersistenceEvidence(fixture());
  assert.equal(result.status, "PASS");
  assert.equal(result.runId, runId);
  assert.equal(result.candidateCommit, commit);
  assert.equal(result.tenantRows, 3);
  assert.equal(result.imageCount, 13);
  assert.deepEqual(result.issues, []);
});

test("persistence evidence blocks snapshot mutation, candidate mismatch, bad digest and image mismatch", () => {
  const changedRows = fixture();
  changedRows.after[0].status = "Unpaid";
  assert.ok(normalizePhase10PersistenceEvidence(changedRows).issues.some(issue => issue.includes("order rows")));

  const wrongCandidate = fixture();
  wrongCandidate.parentGitProvenance.finish.commit = "c".repeat(40);
  assert.ok(normalizePhase10PersistenceEvidence(wrongCandidate).issues.some(issue => issue.includes("candidate")));

  const wrongDigest = fixture();
  wrongDigest.afterTextSha256 = "0".repeat(64);
  assert.ok(normalizePhase10PersistenceEvidence(wrongDigest).issues.some(issue => issue.includes("snapshot hashes")));

  const wrongImages = fixture();
  wrongImages.imageAfter.images[0].imageId = `sha256:${"f".repeat(64)}`;
  assert.ok(normalizePhase10PersistenceEvidence(wrongImages).issues.some(issue => issue.includes("image")));
});

test("absent persistence evidence is NOT-RUN rather than a pass", () => {
  assert.equal(normalizePhase10PersistenceEvidence().status, "NOT-RUN");
});
