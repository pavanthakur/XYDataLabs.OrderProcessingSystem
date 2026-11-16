import { execFile as nodeExecFile } from "node:child_process";
import { promisify } from "node:util";
import path from "node:path";
import { validateApprovedReplayEvidence, type ApprovedReplayEvidenceRequest, type ApprovedReplayEvidenceSnapshot } from "./approved-dlq-replay-evidence.js";
import type { DlqReplayApproval } from "./dlq-replay-approval.js";

const execFile = promisify(nodeExecFile);
type ExecuteFile = (file: string, args: readonly string[], options: { cwd: string; windowsHide: boolean; timeout: number; encoding: "utf8" }) => Promise<{ stdout: string; stderr: string }>;
const executePowerShell: ExecuteFile = async (file, args, options) => {
  const result = await execFile(file, args, options);
  return { stdout: String(result.stdout), stderr: String(result.stderr) };
};

export interface DlqReplaySqlAdapterRequest {
  workspaceRoot: string;
  tenantCode: string;
  quarantineId: string;
  sourceMessageId: string;
  correlationId: string;
  approval: DlqReplayApproval;
  expectedSubscriptionId: string;
  confirmFirewallLease: boolean;
  timeoutSeconds?: number;
  powershellExecutable?: string;
  execute?: ExecuteFile;
}

interface SqlSnapshotEnvelope {
  schemaVersion?: string;
  environment?: string;
  status?: string;
  expected?: Record<string, unknown>;
  snapshot?: unknown;
  failureType?: string | null;
  firewallLeaseRestored?: boolean;
  firewallCleanupFailureType?: string | null;
}

function guid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function parseLastJsonLine(output: string): SqlSnapshotEnvelope {
  const lines = output.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  for (let index = lines.length - 1; index >= 0; index--) {
    try {
      const parsed: unknown = JSON.parse(lines[index]!);
      if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)) return parsed as SqlSnapshotEnvelope;
    } catch { /* Only a complete JSON record is considered evidence. */ }
  }
  throw new Error("Read-only DLQ SQL verifier returned no valid JSON evidence.");
}

/** Executes only the read-only SQL snapshot helper. It may create/remove a narrow firewall lease, so that side effect is a separate explicit input. */
export async function runDlqReplaySqlEvidenceAdapter(request: DlqReplaySqlAdapterRequest): Promise<{
  snapshot: ApprovedReplayEvidenceSnapshot;
  findings: string[];
}> {
  if (!request.confirmFirewallLease) throw new Error("A separate explicit confirmation is required for the temporary Azure SQL firewall lease.");
  if (!guid(request.expectedSubscriptionId)) throw new Error("Expected Azure subscription ID is missing or invalid; no SQL verification was started.");
  if (!guid(request.quarantineId) || !guid(request.sourceMessageId) || !guid(request.approval.replayRequestId)) {
    throw new Error("Replay evidence identifiers are invalid; no SQL verification was started.");
  }
  if (!request.tenantCode || !/^[A-Za-z0-9_-]{1,64}$/.test(request.tenantCode) || !request.correlationId || request.correlationId.length > 128) {
    throw new Error("Replay tenant or correlation identifier is invalid; no SQL verification was started.");
  }
  const approvedUtc = Date.parse(request.approval.approvedUtc);
  if (!Number.isFinite(approvedUtc)) throw new Error("Approval timestamp is invalid; no SQL verification was started.");
  const timeoutSeconds = request.timeoutSeconds ?? 120;
  if (!Number.isInteger(timeoutSeconds) || timeoutSeconds < 1 || timeoutSeconds > 300) throw new Error("Replay SQL verification timeout is invalid.");

  const scriptPath = path.join(request.workspaceRoot, "scripts", "verify-phase10-azure-dlq-replay.ps1");
  const args = [
    "-NoProfile", "-File", scriptPath,
    "-Environment", "dev",
    "-ExpectedSubscriptionId", request.expectedSubscriptionId,
    "-TenantCode", request.tenantCode,
    "-QuarantineId", request.quarantineId,
    "-ReplayRequestId", request.approval.replayRequestId,
    "-SourceMessageId", request.sourceMessageId,
    "-CorrelationId", request.correlationId,
    "-ApprovedUtc", request.approval.approvedUtc,
    "-TimeoutSeconds", String(timeoutSeconds),
    "-ConfirmFirewallLease"
  ];

  let stdout: string;
  try {
    const run = request.execute ?? executePowerShell;
    ({ stdout } = await run(request.powershellExecutable ?? "pwsh", args, { cwd: request.workspaceRoot, windowsHide: true, timeout: (timeoutSeconds + 90) * 1000, encoding: "utf8" }));
  } catch (error) {
    const stdoutFromFailure = error !== null && typeof error === "object" && "stdout" in error && typeof error.stdout === "string" ? error.stdout : "";
    if (!stdoutFromFailure) throw new Error("Read-only Azure SQL replay verification failed; inspect the sanitized run record and firewall lease state.");
    stdout = stdoutFromFailure;
  }

  const envelope = parseLastJsonLine(stdout);
  if (envelope.schemaVersion !== "phase10-azure-dlq-replay-sql-evidence-v1"
      || envelope.environment !== "dev"
      || envelope.status !== "SNAPSHOT_READY_FOR_VALIDATION"
      || envelope.firewallLeaseRestored !== true
      || !envelope.expected
      || !envelope.snapshot
      || typeof envelope.snapshot !== "object") {
    throw new Error("Azure SQL replay evidence is incomplete or its temporary firewall lease was not proven restored.");
  }
  const expected: ApprovedReplayEvidenceRequest = {
    tenantCode: request.tenantCode,
    quarantineId: request.quarantineId,
    replayRequestId: request.approval.replayRequestId,
    sourceMessageId: request.sourceMessageId,
    correlationId: request.correlationId,
    approvedUtc: request.approval.approvedUtc
  };
  const findings = validateApprovedReplayEvidence(expected, envelope.snapshot as ApprovedReplayEvidenceSnapshot);
  return { snapshot: envelope.snapshot as ApprovedReplayEvidenceSnapshot, findings };
}
