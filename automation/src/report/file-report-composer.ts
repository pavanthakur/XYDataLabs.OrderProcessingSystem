import type { ExecutiveSummaryRow, ReportComposer } from "../contracts/report-composer.js";

export class FileReportComposer implements ReportComposer {
  public async compose(rows: ExecutiveSummaryRow[]): Promise<string> {
    const lines = [
      "# Payment Automation Executive Summary",
      "",
      "| Run ID | Target | Tenant | 3DS Setting | Journey | Challenge | Verification | Cleanup | Evidence |",
      "|---|---|---|---|---|---|---|---|---|"
    ];

    for (const row of rows) {
      lines.push(
        `| ${row.runId} | ${row.runtimeTarget} | ${row.tenantCode} | ${row.threeDsSetting} | ${row.journeyOutcome} | ${row.challengeOutcome} | ${row.verificationOutcome} | ${row.cleanupOutcome} | ${row.evidenceReference} |`
      );
    }

    return `${lines.join("\n")}\n`;
  }
}
