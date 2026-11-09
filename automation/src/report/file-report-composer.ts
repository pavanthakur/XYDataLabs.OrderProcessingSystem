import type { ExecutiveSummaryRow, ReportComposer } from "../contracts/report-composer.js";

export class FileReportComposer implements ReportComposer {
  public async compose(rows: ExecutiveSummaryRow[]): Promise<string> {
    const lines = [
      "# Payment Automation Executive Summary",
      "",
      "| Run ID | Target | Tenant | Provider | Mode | Collection | Configured 3DS | Observed challenge | Provider verification | Customer Order | Order ID | Order Ref | Amount | Currency | Journey | Challenge | Verification | Cleanup | Outcome Message | Error Detail | Evidence |",
      "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"
    ];

    for (const row of rows) {
      lines.push(
        `| ${row.runId} | ${row.runtimeTarget} | ${row.tenantCode} | ${row.paymentProvider} | ${row.adapterMode ?? "unknown"} | ${row.collectionMode ?? "unknown"} | ${row.threeDsSetting} | ${row.observedChallenge ?? "unknown"} | ${row.providerVerification ?? "unverified"} | ${row.customerOrderId} | ${row.orderId} | ${row.orderReferenceId} | ${row.orderAmount} | ${row.orderCurrencyCode} | ${row.journeyOutcome} | ${row.challengeOutcome} | ${row.verificationOutcome} | ${row.cleanupOutcome} | ${row.outcomeMessage || "-"} | ${row.errorDetail || "-"} | ${row.evidenceReference} |`
      );
    }

    return `${lines.join("\n")}\n`;
  }
}
