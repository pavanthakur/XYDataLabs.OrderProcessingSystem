import assert from "node:assert/strict";
import { test } from "node:test";
import { finalizeReplayApproval } from "./phase10-replay-finalization.js";

test("sign-out failure preserves approval, persists evidence, closes reservation and rejects", async () => {
  const report: Record<string, unknown> = { approval: { replayRequestId: "test-id" }, status: "VERIFIED" };
  const actions: string[] = [];
  await assert.rejects(finalizeReplayApproval(report, true, async () => {
    actions.push("signout"); throw new Error("token=must-not-be-copied");
  }, {
    update: async record => { actions.push("persist"); assert.equal(record, report); },
    close: async () => { actions.push("close"); }
  }), /sign-out failed/);
  assert.deepEqual(actions, ["signout", "persist", "close"]);
  assert.deepEqual(report.approval, { replayRequestId: "test-id" });
  assert.equal(report.status, "APPROVED_SIGNOUT_FAILED");
  assert.doesNotMatch(JSON.stringify(report), /must-not-be-copied/);
});

test("persistence failure still closes ownership and rejects", async () => {
  let closed = false;
  await assert.rejects(finalizeReplayApproval({}, true, async () => {}, {
    update: async () => { throw new Error("write failed"); },
    close: async () => { closed = true; }
  }), /write failed/);
  assert.equal(closed, true);
});

test("successful finalization preserves verification outcome", async () => {
  const report: Record<string, unknown> = { status: "DUPLICATE_DELIVERY_PENDING" };
  await finalizeReplayApproval(report, true, async () => {}, { update: async () => {}, close: async () => {} });
  assert.equal(report.status, "DUPLICATE_DELIVERY_PENDING");
  assert.equal(report.signOutStatus, "passed");
});
