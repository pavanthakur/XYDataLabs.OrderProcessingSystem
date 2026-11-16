import { mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { JsonRuntimeTargetCatalog } from "../catalog/json-runtime-target-catalog.js";
import { PaymentJourneyRunner } from "../browser/payment-journey-runner.js";
import { safePaymentDiagnostic } from "../support/payment-diagnostics.js";
import { runDlqReplaySqlEvidenceAdapter } from "../verification/phase10-dlq-replay-sql-adapter.js";
import { reservePhase10Report } from "./phase10-report-reservation.js";
import { finalizeReplayApproval } from "./phase10-replay-finalization.js";

const workspaceRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");

export function parseArguments(args: string[]): { tenantCode: string; quarantineId: string; sourceMessageId: string; correlationId: string; confirmFirewallLease: boolean } {
  const value = (name: string) => {
    const index = args.indexOf(name);
    return index >= 0 ? args[index + 1] : undefined;
  };
  const tenantCode = value("--tenant-code");
  const quarantineId = value("--quarantine-id");
  const sourceMessageId = value("--source-message-id");
  const correlationId = value("--correlation-id");
  if (!tenantCode || !quarantineId || !sourceMessageId || !correlationId) {
    throw new Error("Usage: npm run run:azure:dlq-replay-approval -- --tenant-code <tenant> --quarantine-id <guid> --source-message-id <guid> --correlation-id <id> --confirm-approval --confirm-firewall-lease");
  }
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(tenantCode)) throw new Error("Tenant code has invalid characters.");
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(quarantineId)) {
    throw new Error("Quarantine ID must be a GUID.");
  }
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(sourceMessageId)) {
    throw new Error("Source message ID must be a GUID.");
  }
  if (correlationId.length > 128 || !/^[A-Za-z0-9_.:-]+$/.test(correlationId)) throw new Error("Correlation ID has invalid characters or length.");
  if (!args.includes("--confirm-approval")) throw new Error("This operation creates an approved replay request. Pass --confirm-approval to explicitly authorize that mutation.");
  const confirmFirewallLease = args.includes("--confirm-firewall-lease");
  if (!confirmFirewallLease) throw new Error("Post-approval SQL verification creates a temporary Azure SQL firewall lease. Pass --confirm-firewall-lease only when that separate dev mutation is approved.");
  if (args.some(arg => arg === "--target" || arg === "--environment")) {
    throw new Error("Replay approval is pinned to azure-dev; target/environment overrides are not accepted.");
  }
  return { tenantCode, quarantineId, sourceMessageId, correlationId, confirmFirewallLease };
}

async function main(): Promise<void> {
  const input = parseArguments(process.argv.slice(2));
  if (!process.env.EXPECTED_AZURE_SUBSCRIPTION_ID || !/^[0-9a-f-]{36}$/i.test(process.env.EXPECTED_AZURE_SUBSCRIPTION_ID)) {
    throw new Error("Set EXPECTED_AZURE_SUBSCRIPTION_ID to the approved Azure-dev subscription before starting; no browser/API approval was attempted.");
  }
  const startedUtc = new Date().toISOString();
  const runId = `azure-dlq-replay-${startedUtc.replace(/[-:.]/g, "").replace(/Z$/, "Z")}`;
  const reportDirectory = path.join(workspaceRoot, "TestResults", "Playwright", "azure-dlq-replay", runId);
  await mkdir(reportDirectory, { recursive: true });
  const reportPath = path.join(reportDirectory, "approval-summary.json");
  const report: Record<string, unknown> = {
    schemaVersion: "phase10-azure-dlq-replay-approval-v1",
    runId,
    target: "azure-dev",
    tenantCode: input.tenantCode,
    quarantineId: input.quarantineId,
    status: "NOT_RUN",
    stage: "approval-only",
    startedUtc,
    finishedUtc: null,
    approval: null,
    sqlEvidence: null,
    note: "This report covers only the protected API approval call; Functions processing and downstream effects are verified separately."
  };
  const reportReservation = await reservePhase10Report(reportPath, report);
  const runner = new PaymentJourneyRunner();
  let approved = false;
  let runFailed = false;
  try {
    const target = await new JsonRuntimeTargetCatalog().resolve("azure-dev");
    if (target.runtime !== "azure" || target.environment !== "dev") {
      throw new Error("Resolved runtime target is not Azure dev; approval was not attempted.");
    }
    console.log(`Ready for one protected replay approval: tenant=${input.tenantCode}; quarantine=${input.quarantineId}; target=azure-dev.`);
    console.log("Complete normal Entra sign-in/MFA in the headed browser. The access token remains in memory and is not written to reports.");
    report.status = "SUBMISSION_OUTCOME_UNKNOWN";
    report.stage = "submission-intended-before-browser-flow";
    await reportReservation.update(report);
    const result = await runner.execute({
      tenantCode: input.tenantCode,
      target,
      customerOrderId: "not-created",
      sandboxOtpCode: "",
      headless: false,
      operatorAssistedEntra: true,
      reuseEntraSession: true,
      dlqReplayApprovalQuarantineId: input.quarantineId,
      logger: message => console.log(safePaymentDiagnostic(message))
    });
    if (result.journeyOutcome !== "dlq-replay-approved-pending-verification" || !result.dlqReplayApproval) {
      throw new Error("Protected API did not return a validated replay approval result.");
    }
    approved = true;
    report.approval = result.dlqReplayApproval;
    report.operatorRoleAccepted = true;
    report.status = "APPROVED_PROCESSING_UNVERIFIED";
    report.stage = "approval-confirmed";
    await reportReservation.update(report);
    if (!process.env.EXPECTED_AZURE_SUBSCRIPTION_ID) {
      throw new Error("EXPECTED_AZURE_SUBSCRIPTION_ID is required before read-only Azure SQL verification.");
    }
    const sqlVerification = await runDlqReplaySqlEvidenceAdapter({
      workspaceRoot,
      tenantCode: input.tenantCode,
      quarantineId: input.quarantineId,
      sourceMessageId: input.sourceMessageId,
      correlationId: input.correlationId,
      approval: result.dlqReplayApproval,
      expectedSubscriptionId: process.env.EXPECTED_AZURE_SUBSCRIPTION_ID,
      confirmFirewallLease: input.confirmFirewallLease
    });
    report.sqlEvidence = sqlVerification;
    report.status = sqlVerification.findings.length === 0
      ? "REPLAY_EFFECTS_VERIFIED_DUPLICATE_DELIVERY_PENDING"
      : "APPROVED_PROCESSING_UNVERIFIED";
    if (sqlVerification.findings.length > 0) throw new Error("Replay processing or durable-effect evidence did not satisfy the acceptance contract.");
  } catch (error) {
    runFailed = true;
    report.status = approved ? "APPROVED_SIGNOUT_OR_REPORT_INCOMPLETE" : "INCOMPLETE_RECONCILIATION_REQUIRED";
    report.failure = safePaymentDiagnostic(error instanceof Error ? error.message : "Replay approval did not complete.");
    throw error;
  } finally {
    await finalizeReplayApproval(report, approved,
      () => runner.closeOperatorAssistedSession(message => console.log(safePaymentDiagnostic(message))), reportReservation);
    console.log(`Replay approval stage: ${String(report.status)}. Report: ${path.relative(workspaceRoot, reportPath).replaceAll(path.sep, "/")}`);
  }
  if (runFailed) throw new Error("DLQ replay approval run did not complete all required verification and sign-out steps; inspect its sanitized report before retrying.");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    console.error(error instanceof Error ? safePaymentDiagnostic(error.message) : "DLQ replay approval failed; inspect the sanitized run report.");
    process.exitCode = 1;
  });
}
