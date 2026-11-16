import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { reserveLocalDlqApprovalEvidence } from "../../frontend/apps/web/scripts/phase10-local-dlq-approval-evidence.mjs";

test("durably records submission intent before a state-changing request", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "phase10-local-replay-evidence-"));
  const file = path.join(directory, "approval.jsonl");
  const evidence = await reserveLocalDlqApprovalEvidence(file, { status: "NOT_RUN" });
  try {
    await evidence.append({ status: "SUBMISSION_OUTCOME_UNKNOWN", step: "submission-intended" });
    await evidence.append({ status: "APPROVED", replayRequestId: "redacted-test-id" });
    assert.deepEqual(JSON.parse(await readFile(file, "utf8")), { status: "APPROVED", replayRequestId: "redacted-test-id" });
    assert.deepEqual((await readFile(`${file}.jsonl`, "utf8")).trim().split("\n").map(line => JSON.parse(line)), [
      { status: "NOT_RUN" },
      { status: "SUBMISSION_OUTCOME_UNKNOWN", step: "submission-intended" },
      { status: "APPROVED", replayRequestId: "redacted-test-id" }
    ]);
  } finally {
    await evidence.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("exclusive reservation preserves an existing record and refuses a concurrent attempt", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "phase10-local-replay-collision-"));
  const file = path.join(directory, "approval.jsonl");
  await writeFile(file, "prior evidence\n", { flag: "wx" });
  try {
    await assert.rejects(reserveLocalDlqApprovalEvidence(file, { status: "NOT_RUN" }), { code: "EEXIST" });
    assert.equal(await readFile(file, "utf8"), "prior evidence\n");
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("interrupted submission remains unknown and serialized checkpoints preserve ordering", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "phase10-local-interrupted-"));
  const file = path.join(directory, "approval.json");
  const evidence = await reserveLocalDlqApprovalEvidence(file, { status: "NOT_RUN" });
  try {
    await Promise.all([
      evidence.append({ status: "AUTHENTICATED" }),
      evidence.append({ status: "SUBMISSION_OUTCOME_UNKNOWN" })
    ]);
    await evidence.close();
    assert.equal(JSON.parse(await readFile(file, "utf8")).status, "SUBMISSION_OUTCOME_UNKNOWN");
    const records = (await readFile(`${file}.jsonl`, "utf8")).trim().split("\n").map(JSON.parse);
    assert.deepEqual(records.map(record => record.status), ["NOT_RUN", "AUTHENTICATED", "SUBMISSION_OUTCOME_UNKNOWN"]);
    await assert.rejects(evidence.append({ status: "APPROVED" }), /closed/);
    await assert.rejects(reserveLocalDlqApprovalEvidence(file, {}), { code: "EEXIST" });
  } finally {
    await evidence.close();
    await rm(directory, { recursive: true, force: true });
  }
});
