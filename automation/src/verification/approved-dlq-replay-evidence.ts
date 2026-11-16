export interface ApprovedReplayEvidenceRequest {
  tenantCode: string;
  quarantineId: string;
  replayRequestId: string;
  sourceMessageId: string;
  correlationId: string;
  approvedUtc: string;
}

export interface ApprovedReplayEvidenceSnapshot {
  tenantCode: string;
  correlationId: string;
  quarantine: {
    id: string;
    sourceMessageId: string;
    state: string;
    replayAttemptCount: number;
    replayedUtc: string | null;
  };
  replayRequest: {
    id: string;
    quarantineId: string;
    approvedUtc: string | null;
    publishedUtc: string | null;
    processedUtc: string | null;
    lastError: string | null;
  };
  effects: {
    inventoryInboxCount: number;
    notificationsInboxCount: number;
    inventoryReservationCount: number;
    notificationDeliveryCount: number;
    otherTenantEffectCount: number;
    inventoryInboxProcessedUtc: string | null;
    notificationsInboxProcessedUtc: string | null;
    inventoryReservedUtc: string | null;
    notificationAcceptedUtc: string | null;
  };
}

const guidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function validTimestamp(value: string | null): number | undefined {
  if (!value) return undefined;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

/**
 * Validates read-only SQL evidence for one approved Azure-dev DLQ replay.
 * It deliberately returns findings instead of throwing so the report can keep
 * an incomplete/failed result without exposing raw database values.
 */
export function validateApprovedReplayEvidence(
  request: ApprovedReplayEvidenceRequest,
  snapshot: ApprovedReplayEvidenceSnapshot
): string[] {
  const findings: string[] = [];
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(request.tenantCode)) findings.push("Expected tenant code is malformed.");
  for (const [label, value] of [["quarantine", request.quarantineId], ["replay request", request.replayRequestId], ["source message", request.sourceMessageId]] as const) {
    if (!guidPattern.test(value)) findings.push(`Expected ${label} identifier is malformed.`);
  }
  if (!request.correlationId || request.correlationId.length > 128) findings.push("Expected correlation ID is missing or too long.");

  const approvedMs = validTimestamp(request.approvedUtc);
  if (approvedMs === undefined) findings.push("Approval timestamp is missing or invalid.");
  if (snapshot.tenantCode !== request.tenantCode) findings.push("Replay evidence belongs to a different tenant.");
  if (snapshot.correlationId !== request.correlationId) findings.push("Replay evidence was queried with a different correlation ID.");
  if (snapshot.quarantine.id.toLowerCase() !== request.quarantineId.toLowerCase()) findings.push("Quarantine evidence does not match the approved quarantine.");
  if (snapshot.quarantine.sourceMessageId.toLowerCase() !== request.sourceMessageId.toLowerCase()) findings.push("Quarantine source message does not match the test envelope.");
  if (snapshot.quarantine.state.toLowerCase() !== "replayed") findings.push("Quarantine is not in Replayed state.");
  if (snapshot.quarantine.replayAttemptCount !== 1) findings.push("Quarantine must show exactly one replay attempt.");
  if (snapshot.replayRequest.id.toLowerCase() !== request.replayRequestId.toLowerCase()) findings.push("Replay request evidence does not match the approved request.");
  if (snapshot.replayRequest.quarantineId.toLowerCase() !== request.quarantineId.toLowerCase()) findings.push("Replay request points to a different quarantine.");
  if (snapshot.replayRequest.lastError !== null) findings.push("Replay request has an error and cannot pass acceptance.");

  const publishedMs = validTimestamp(snapshot.replayRequest.publishedUtc);
  const processedMs = validTimestamp(snapshot.replayRequest.processedUtc);
  const replayedMs = validTimestamp(snapshot.quarantine.replayedUtc);
  const publishedApprovalMs = validTimestamp(snapshot.replayRequest.approvedUtc);
  const approvalResponseMs = approvedMs;
  if (publishedApprovalMs === undefined) findings.push("Replay request has no valid approval timestamp.");
  if (publishedMs === undefined) findings.push("Replay request has no valid PublishedUtc evidence.");
  if (processedMs === undefined) findings.push("Replay request has no valid ProcessedUtc evidence.");
  if (replayedMs === undefined) findings.push("Quarantine has no valid ReplayedUtc evidence.");
  if (approvedMs !== undefined && publishedMs !== undefined && publishedMs < approvedMs) findings.push("Replay publication predates approval.");
  if (approvedMs !== undefined && publishedApprovalMs !== undefined && Math.abs(publishedApprovalMs - approvedMs) > 1000) findings.push("Replay request approval timestamp does not match the approval response.");
  if (publishedMs !== undefined && processedMs !== undefined && processedMs < publishedMs) findings.push("Replay processing predates publication.");
  if (approvedMs !== undefined && replayedMs !== undefined && replayedMs < approvedMs) findings.push("Replay completion predates approval.");
  if (processedMs !== undefined && replayedMs !== undefined && Math.abs(processedMs - replayedMs) > 1000) findings.push("Replay request and quarantine completion timestamps disagree.");
  const effectTimes = [
    snapshot.effects.inventoryInboxProcessedUtc,
    snapshot.effects.notificationsInboxProcessedUtc,
    snapshot.effects.inventoryReservedUtc,
    snapshot.effects.notificationAcceptedUtc
  ].map(validTimestamp);
  if (effectTimes.some(value => value === undefined)) findings.push("One or more downstream durable effects lack valid timestamps.");
  if (processedMs !== undefined && effectTimes.some(value => value !== undefined && value < processedMs)) findings.push("A downstream effect predates Functions replay processing.");
  if (approvalResponseMs !== undefined && effectTimes.every((value): value is number => value !== undefined)
      && Math.max(...effectTimes) - approvalResponseMs > 60_000) findings.push("Replay downstream effects exceeded the 60-second visibility target.");

  const counts = {
    inventoryInboxCount: snapshot.effects.inventoryInboxCount,
    notificationsInboxCount: snapshot.effects.notificationsInboxCount,
    inventoryReservationCount: snapshot.effects.inventoryReservationCount,
    notificationDeliveryCount: snapshot.effects.notificationDeliveryCount,
    otherTenantEffectCount: snapshot.effects.otherTenantEffectCount
  };
  for (const [label, count] of Object.entries(counts)) {
    if (!Number.isInteger(count) || count < 0) findings.push(`The ${label} count is invalid.`);
  }
  if (counts.inventoryInboxCount !== 1) findings.push("Inventory consumer inbox must contain exactly one correlated replay.");
  if (counts.notificationsInboxCount !== 1) findings.push("Notifications consumer inbox must contain exactly one correlated replay.");
  if (counts.inventoryReservationCount !== 1) findings.push("Exactly one inventory reservation effect is required.");
  if (counts.notificationDeliveryCount !== 1) findings.push("Exactly one notification delivery effect is required.");
  if (counts.otherTenantEffectCount !== 0) findings.push("A cross-tenant effect was observed.");
  return findings;
}

export interface ApprovedReplayEvidencePollOptions {
  request: ApprovedReplayEvidenceRequest;
  readSnapshot: (signal: AbortSignal) => Promise<ApprovedReplayEvidenceSnapshot | null>;
  timeoutMs?: number;
  pollIntervalMs?: number;
  signal?: AbortSignal;
  now?: () => number;
  delay?: (milliseconds: number, signal: AbortSignal) => Promise<void>;
}

function abortableDelay(milliseconds: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal.aborted) return reject(signal.reason ?? new Error("Verification cancelled."));
    const onAbort = () => {
      clearTimeout(timer);
      signal.removeEventListener("abort", onAbort);
      reject(signal.reason ?? new Error("Verification cancelled."));
    };
    const timer = setTimeout(() => {
      signal.removeEventListener("abort", onAbort);
      resolve();
    }, milliseconds);
    signal.addEventListener("abort", onAbort, { once: true });
  });
}

/** Bounded, read-only polling; it never re-approves or republishes a replay. */
export async function waitForApprovedReplayEvidence(options: ApprovedReplayEvidencePollOptions): Promise<ApprovedReplayEvidenceSnapshot> {
  const timeoutMs = options.timeoutMs ?? 120_000;
  const pollIntervalMs = options.pollIntervalMs ?? 2_000;
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1_000 || timeoutMs > 300_000) throw new Error("Replay verification timeout must be between 1 and 300 seconds.");
  if (!Number.isInteger(pollIntervalMs) || pollIntervalMs < 100 || pollIntervalMs > 30_000) throw new Error("Replay verification polling interval is invalid.");

  const controller = new AbortController();
  if (options.signal?.aborted) throw new Error("Replay verification was cancelled; the replay itself was not changed.");
  const externalAbort = () => controller.abort(options.signal?.reason);
  options.signal?.addEventListener("abort", externalAbort, { once: true });
  const deadline = (options.now ?? Date.now)() + timeoutMs;
  const delay = options.delay ?? abortableDelay;
  try {
    while ((options.now ?? Date.now)() <= deadline) {
      if (controller.signal.aborted) throw new Error("Replay verification was cancelled; the replay itself was not changed.");
      const snapshot = await options.readSnapshot(controller.signal);
      if (snapshot) {
        const findings = validateApprovedReplayEvidence(options.request, snapshot);
        if (findings.length === 0) return snapshot;
        // A partial state is normal while Functions are processing. A terminal
        // rejection/error or impossible identity mismatch should fail promptly.
        if (snapshot.replayRequest.lastError !== null
            || snapshot.tenantCode !== options.request.tenantCode
            || snapshot.quarantine.id.toLowerCase() !== options.request.quarantineId.toLowerCase()
            || snapshot.replayRequest.id.toLowerCase() !== options.request.replayRequestId.toLowerCase()) {
          throw new Error(`Replay verification found a terminal or mismatched state: ${findings.join("; ")}`);
        }
      }
      if ((options.now ?? Date.now)() >= deadline) break;
      await delay(Math.min(pollIntervalMs, Math.max(0, deadline - (options.now ?? Date.now)())), controller.signal);
    }
    throw new Error("Approved replay was not fully processed before the bounded verification timeout; do not re-approve or republish automatically.");
  } finally {
    options.signal?.removeEventListener("abort", externalAbort);
    controller.abort();
  }
}
