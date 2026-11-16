import test from "node:test";
import assert from "node:assert/strict";
import {
  validateApprovedReplayEvidence,
  waitForApprovedReplayEvidence,
  type ApprovedReplayEvidenceRequest,
  type ApprovedReplayEvidenceSnapshot
} from "./approved-dlq-replay-evidence.js";

const request: ApprovedReplayEvidenceRequest = {
  tenantCode: "TenantA",
  quarantineId: "11111111-1111-4111-8111-111111111111",
  replayRequestId: "22222222-2222-4222-8222-222222222222",
  sourceMessageId: "33333333-3333-4333-8333-333333333333",
  correlationId: "phase10-replay-test-unique",
  approvedUtc: "2026-11-16T10:00:00.000Z"
};

const passing: ApprovedReplayEvidenceSnapshot = {
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
    id: request.replayRequestId,
    quarantineId: request.quarantineId,
    publishedUtc: "2026-11-16T10:00:05.000Z",
    processedUtc: "2026-11-16T10:00:12.000Z",
    approvedUtc: request.approvedUtc,
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

test("accepts only a matching approved replay with one tenant-scoped durable effect per consumer", () => {
  assert.deepEqual(validateApprovedReplayEvidence(request, passing), []);
});

test("polls read-only processing evidence to completion without resubmitting approval", async () => {
  let now = Date.parse("2026-11-16T10:00:06.000Z");
  let reads = 0;
  const result = await waitForApprovedReplayEvidence({
    request,
    timeoutMs: 5_000,
    pollIntervalMs: 100,
    now: () => now,
    delay: async milliseconds => { now += milliseconds; },
    readSnapshot: async () => {
      reads++;
      if (reads < 3) return { ...structuredClone(passing), quarantine: { ...passing.quarantine, state: "Approved", replayAttemptCount: 0, replayedUtc: null }, replayRequest: { ...passing.replayRequest, publishedUtc: null, processedUtc: null } };
      return structuredClone(passing);
    }
  });
  assert.equal(result.replayRequest.id, request.replayRequestId);
  assert.equal(reads, 3);
});

test("times out without retrying or mutating replay state", async () => {
  let now = 1_000;
  let reads = 0;
  await assert.rejects(waitForApprovedReplayEvidence({
    request,
    timeoutMs: 1_000,
    pollIntervalMs: 500,
    now: () => now,
    delay: async milliseconds => { now += milliseconds; },
    readSnapshot: async () => { reads++; return null; }
  }), /bounded verification timeout/);
  assert.equal(reads, 3);
});

test("surfaces caller cancellation as read-only verification cancellation", async () => {
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(waitForApprovedReplayEvidence({
    request,
    signal: controller.signal,
    readSnapshot: async () => null
  }), /cancelled/);
});

test("rejects wrong tenant, quarantine, source message, request, and cross-tenant effects", () => {
  const snapshot = structuredClone(passing);
  snapshot.tenantCode = "TenantB";
  snapshot.correlationId = "other-correlation";
  snapshot.quarantine.id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  snapshot.quarantine.sourceMessageId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  snapshot.replayRequest.id = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
  snapshot.replayRequest.quarantineId = snapshot.quarantine.id;
  snapshot.effects.otherTenantEffectCount = 1;
  const findings = validateApprovedReplayEvidence(request, snapshot);
  assert.ok(findings.some(item => item.includes("different tenant")));
  assert.ok(findings.some(item => item.includes("different correlation")));
  assert.ok(findings.some(item => item.includes("approved quarantine")));
  assert.ok(findings.some(item => item.includes("test envelope")));
  assert.ok(findings.some(item => item.includes("approved request")));
  assert.ok(findings.some(item => item.includes("cross-tenant")));
});

test("rejects missing processing evidence, unexpected errors, and duplicate attempts/effects", () => {
  const snapshot = structuredClone(passing);
  snapshot.quarantine.replayAttemptCount = 2;
  snapshot.replayRequest.publishedUtc = null;
  snapshot.replayRequest.processedUtc = null;
  snapshot.replayRequest.lastError = "some error";
  snapshot.effects.inventoryReservationCount = 2;
  snapshot.effects.notificationDeliveryCount = 0;
  const findings = validateApprovedReplayEvidence(request, snapshot);
  assert.ok(findings.some(item => item.includes("exactly one replay attempt")));
  assert.ok(findings.some(item => item.includes("no valid PublishedUtc")));
  assert.ok(findings.some(item => item.includes("no valid ProcessedUtc")));
  assert.ok(findings.some(item => item.includes("has an error")));
  assert.ok(findings.some(item => item.includes("Exactly one inventory")));
  assert.ok(findings.some(item => item.includes("Exactly one notification")));
});

test("rejects timestamps out of order and malformed counts", () => {
  const snapshot = structuredClone(passing);
  snapshot.replayRequest.publishedUtc = "2026-11-16T09:59:59.000Z";
  snapshot.replayRequest.processedUtc = "2026-11-16T09:59:58.000Z";
  snapshot.effects.inventoryInboxCount = -1;
  const findings = validateApprovedReplayEvidence(request, snapshot);
  assert.ok(findings.some(item => item.includes("predates approval")));
  assert.ok(findings.some(item => item.includes("predates publication")));
  assert.ok(findings.some(item => item.includes("count is invalid")));
});
