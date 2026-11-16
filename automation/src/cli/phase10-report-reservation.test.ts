import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, readdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { reservePhase10Report } from "./phase10-report-reservation.js";

test("reserves ownership separately and replaces summary with closed file handles", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "phase10-report-reservation-"));
  const filePath = path.join(directory, "approval-summary.json");
  const reservation = await reservePhase10Report(filePath, { status: "NOT_RUN" });
  try {
    assert.deepEqual(JSON.parse(await readFile(filePath, "utf8")), { status: "NOT_RUN" });
    await reservation.update({ status: "APPROVED_PROCESSING_UNVERIFIED" });
    assert.deepEqual(JSON.parse(await readFile(filePath, "utf8")), { status: "APPROVED_PROCESSING_UNVERIFIED" });
    assert.equal((await readdir(`${filePath}.checkpoints`)).length, 2);
    assert.deepEqual(JSON.parse(await readFile(path.join(`${filePath}.checkpoints`, "000000.json"), "utf8")), { status: "NOT_RUN" });
  } finally {
    await reservation.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("concurrent reservations have one owner and a closed owner cannot be reused", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "phase10-owner-"));
  const file = path.join(directory, "summary.json");
  try {
    const attempts = await Promise.allSettled([reservePhase10Report(file, {}), reservePhase10Report(file, {})]);
    assert.equal(attempts.filter(attempt => attempt.status === "fulfilled").length, 1);
    for (const attempt of attempts) if (attempt.status === "fulfilled") {
      await attempt.value.close();
      await assert.rejects(attempt.value.update({}), /closed/);
    }
    await assert.rejects(reservePhase10Report(file, {}));
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("failed summary update preserves prior summary and new immutable checkpoint", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "phase10-checkpoint-failure-"));
  const file = path.join(directory, "summary.json");
  const reservation = await reservePhase10Report(file, { status: "NOT_RUN" });
  try {
    await writeFile(`${file}.2.tmp`, "collision", { flag: "wx" });
    await assert.rejects(reservation.update({ status: "SUBMISSION_OUTCOME_UNKNOWN" }), { code: "EEXIST" });
    assert.deepEqual(JSON.parse(await readFile(file, "utf8")), { status: "NOT_RUN" });
    assert.deepEqual(JSON.parse(await readFile(path.join(`${file}.checkpoints`, "000001.json"), "utf8")), { status: "SUBMISSION_OUTCOME_UNKNOWN" });
    await assert.rejects(reservation.update({ status: "PASS" }), /Earlier checkpoint failed/);
  } finally { await reservation.close(); await rm(directory, { recursive: true, force: true }); }
});

test("an existing report artifact blocks reservation and is left unchanged", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "phase10-report-collision-"));
  const filePath = path.join(directory, "approval-summary.json");
  const original = "preserve existing evidence\n";
  const { writeFile } = await import("node:fs/promises");
  await writeFile(filePath, original, { encoding: "utf8", flag: "wx" });
  try {
    await assert.rejects(reservePhase10Report(filePath, { status: "NOT_RUN" }), /already exists/);
    assert.equal(await readFile(filePath, "utf8"), original);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
