import type { ExecutiveSummaryRow, ReportComposer } from "../contracts/report-composer.js";

export class FileReportComposer implements ReportComposer {
  public async compose(rows: ExecutiveSummaryRow[]): Promise<string> {
    const lines = [
      "# Payment Automation Executive Summary",
      ...(rows.some(row => row.journeyOutcome === "dry_run") ? ["", "**DRY-RUN — NOT PAYMENT ACCEPTANCE EVIDENCE. No charge was executed by these rows.**"] : []),
      ...(rows.some(row => row.executionEvidence==="carried-forward"||row.executionEvidence==="read-only-reconciled") ? ["", "**Includes carried-forward/reconciled cases: not an uninterrupted fresh payment run. Original run IDs and evidence are retained.**"] : []),
      "",
      "| Run ID | Target | Tenant | Provider | Mode | Collection | Configured 3DS | Observed challenge | Provider verification | Customer Order | Order ID | Order Ref | Amount | Currency | Journey | Challenge | Verification | Cleanup | Outcome Message | Error Detail | Evidence |",
      "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"
    ];

    for (const row of rows) {
      lines.push(
        `| ${row.runId} | ${row.runtimeTarget} | ${row.tenantCode} | ${row.paymentProvider} | ${row.adapterMode ?? "unknown"} | ${row.collectionMode ?? "unknown"} | ${row.threeDsSetting} | ${row.observedChallenge ?? "unknown"} | ${row.providerVerification ?? "unverified"} | ${row.customerOrderId} | ${row.orderId} | ${row.orderReferenceId} | ${row.orderAmount} | ${row.orderCurrencyCode} | ${row.journeyOutcome} | ${row.challengeOutcome} | ${row.verificationOutcome} | ${row.cleanupOutcome} | ${row.outcomeMessage || "-"} | ${row.errorDetail || "-"} | ${row.executionEvidence ?? "unknown-origin"}: ${row.evidenceReference} |`
      );
    }

    return `${lines.join("\n")}\n`;
  }
}
