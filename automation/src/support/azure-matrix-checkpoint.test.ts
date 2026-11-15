import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { assertResumeSafe, matrixBinding, readCheckpoint, saveCheckpoint, type MatrixCheckpoint } from "./azure-matrix-checkpoint.js";
import type { ExecutiveSummaryRow } from "../contracts/report-composer.js";

const row = { tenantCode: "TenantA", paymentProvider: "Razorpay", journeyOutcome: "completed", verificationOutcome: "passed", cleanupOutcome: "reset", adapterMode: "sandbox" } as ExecutiveSummaryRow;
const valid = (): MatrixCheckpoint => ({ schemaVersion: 1, binding: "candidate", cases: [{ key: "tenanta|razorpay", state: "verified-restored", row }] });
test("verified restored cases can be retained without submitting again", () => assert.doesNotThrow(() => assertResumeSafe(valid(), "candidate", ["tenanta|razorpay"])));
for (const scenario of ["started", "missing-row", "duplicate", "unknown", "failed-verification", "unrestored", "live", "mismatched-row", "malformed"] as const) {
  test(`resume refuses ${scenario} before a submission`, () => {
    const checkpoint = structuredClone(valid());
    switch (scenario) {
      case "started": checkpoint.cases[0].state = "started"; break;
      case "missing-row": delete checkpoint.cases[0].row; break;
      case "duplicate": checkpoint.cases.push(checkpoint.cases[0]); break;
      case "unknown": checkpoint.cases[0].key = "other|razorpay"; break;
      case "failed-verification": checkpoint.cases[0].row!.verificationOutcome = "failed"; break;
      case "unrestored": checkpoint.cases[0].row!.cleanupOutcome = "manual-review"; break;
      case "live": checkpoint.cases[0].row!.adapterMode = "live"; break;
      case "mismatched-row": checkpoint.cases[0].row!.tenantCode = "TenantB"; break;
      case "malformed": checkpoint.schemaVersion = 99 as 1; break;
    }
    assert.throws(() => assertResumeSafe(checkpoint, "candidate", ["tenanta|razorpay"]));
  });
}
test("candidate, deployment or settings changes invalidate binding", () => {
  assert.notEqual(matrixBinding({ revision: "one" }), matrixBinding({ revision: "two" }));
  assert.throws(() => assertResumeSafe(valid(), "changed", ["tenanta|razorpay"]));
});
test("atomic intent survives interruption and refuses resume; paths cannot escape evidence", async (t) => {
  const root = await mkdtemp(path.join(os.tmpdir(), "azure-checkpoint-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const evidence = path.join(root, "evidence"); await mkdir(evidence);
  const file = path.join(evidence, "checkpoint.json");
  await saveCheckpoint(file, { schemaVersion: 1, binding: "candidate", cases: [{ key: "tenanta|razorpay", state: "started" }] });
  const saved = await readCheckpoint(file, evidence);
  assert.throws(() => assertResumeSafe(saved, "candidate", ["tenanta|razorpay"]));
  await saveCheckpoint(file, valid());
  assert.equal(JSON.parse(await readFile(file, "utf8")).cases[0].state, "verified-restored");
  const outside = path.join(root, "outside.json"); await writeFile(outside, JSON.stringify(valid()));
  await assert.rejects(readCheckpoint(outside, evidence), /inside/);
});

test("symlink escape is refused where supported", async (t) => {
  const root = await mkdtemp(path.join(os.tmpdir(), "azure-link-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const evidence = path.join(root, "evidence"); await mkdir(evidence);
  const outside = path.join(root, "outside.json"); await writeFile(outside, JSON.stringify(valid()));
  const link = path.join(evidence, "linked.json");
  try { await symlink(outside, link); } catch (error) {
    if (["EPERM", "EACCES"].includes((error as NodeJS.ErrnoException).code ?? "")) { t.skip("Symlink creation unavailable"); return; }
    throw error;
  }
  await assert.rejects(readCheckpoint(link, evidence), /inside/);
});
