import test from "node:test";
import assert from "node:assert/strict";
import { runDlqReplaySqlEvidenceAdapter } from "./phase10-dlq-replay-sql-adapter.js";
import type { ApprovedReplayEvidenceSnapshot } from "./approved-dlq-replay-evidence.js";

const request = {
  workspaceRoot: "Q:/repo",
  tenantCode: "TenantA",
  quarantineId: "11111111-1111-4111-8111-111111111111",
  sourceMessageId: "33333333-3333-4333-8333-333333333333",
  correlationId: "phase10-replay-test-unique",
  expectedSubscriptionId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  confirmFirewallLease: true,
  approval: {
    quarantineId: "11111111-1111-4111-8111-111111111111",
    replayRequestId: "22222222-2222-4222-8222-222222222222",
    state: "Approved",
    approvedUtc: "2026-11-16T10:00:00.000Z",
    alreadyApproved: false
  }
};

const snapshot: ApprovedReplayEvidenceSnapshot = {
  tenantCode: "TenantA",
  correlationId: request.correlationId,
  quarantine: {
    id: request.quarantineId,
    sourceMessageId: request.sourceMessageId,
    state: "Replayed",
    replayAttemptCount: 1,
    replayedUtc: "2026-11-16T10:00:12.000Z"
  },
  replayRequest: {
    id: request.approval.replayRequestId,
    quarantineId: request.quarantineId,
    approvedUtc: request.approval.approvedUtc,
    publishedUtc: "2026-11-16T10:00:05.000Z",
    processedUtc: "2026-11-16T10:00:12.000Z",
    lastError: null
  },
  effects: {
    inventoryInboxCount: 1,
    notificationsInboxCount: 1,
    inventoryReservationCount: 1,
    notificationDeliveryCount: 1,
    otherTenantEffectCount: 0,
    inventoryInboxProcessedUtc: "2026-11-16T10:00:13.000Z",
    notificationsInboxProcessedUtc: "2026-11-16T10:00:14.000Z",
    inventoryReservedUtc: "2026-11-16T10:00:13.000Z",
    notificationAcceptedUtc: "2026-11-16T10:00:14.000Z"
  }
};

test("requires separate firewall confirmation before launching PowerShell", async () => {
  let launched = false;
  await assert.rejects(runDlqReplaySqlEvidenceAdapter({
    ...request,
    confirmFirewallLease: false,
    execute: async () => { launched = true; return { stdout: "", stderr: "" }; }
  }), /separate explicit confirmation/);
  assert.equal(launched, false);
});

test("runs only the pinned dev SQL evidence script and validates its output", async () => {
  let command = "";
  let args: readonly string[] = [];
  const result = await runDlqReplaySqlEvidenceAdapter({
    ...request,
    execute: async (file, passed) => {
      command = file;
      args = passed;
      return { stdout: `notice\n${JSON.stringify({
        schemaVersion: "phase10-azure-dlq-replay-sql-evidence-v1",
        environment: "dev",
        status: "SNAPSHOT_READY_FOR_VALIDATION",
        expected: {},
        snapshot,
        failureType: null,
        firewallLeaseRestored: true,
        firewallCleanupFailureType: null
      })}\n`, stderr: "" };
    }
  });
  assert.equal(command, "pwsh");
  assert.ok(args.includes("-ConfirmFirewallLease"));
  assert.ok(args.includes("-Environment"));
  assert.ok(args.includes("dev"));
  assert.ok(args.includes(request.approval.approvedUtc));
  assert.deepEqual(result.findings, []);
  assert.equal(result.snapshot.replayRequest.id, request.approval.replayRequestId);
});

test("rejects incomplete snapshots and a firewall lease not confirmed restored", async () => {
  for (const envelope of [
    { schemaVersion: "phase10-azure-dlq-replay-sql-evidence-v1", environment: "dev", status: "INCOMPLETE", snapshot, firewallLeaseRestored: true },
    { schemaVersion: "phase10-azure-dlq-replay-sql-evidence-v1", environment: "dev", status: "SNAPSHOT_READY_FOR_VALIDATION", snapshot, firewallLeaseRestored: false }
  ]) {
    await assert.rejects(runDlqReplaySqlEvidenceAdapter({
      ...request,
      execute: async () => ({ stdout: JSON.stringify(envelope), stderr: "" })
    }), /incomplete|firewall lease/);
  }
});

test("rejects malformed identifiers before process launch", async () => {
  let launched = false;
  await assert.rejects(runDlqReplaySqlEvidenceAdapter({
    ...request,
    sourceMessageId: "bad-id",
    execute: async () => { launched = true; return { stdout: "", stderr: "" }; }
  }), /identifiers are invalid/);
  assert.equal(launched, false);
});
