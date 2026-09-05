import type { ChallengeOutcome } from "./provider-challenge-handler.js";
import type { CleanupOutcome } from "./payment-fixture-provisioner.js";

export type ThreeDsSetting = "enabled" | "disabled" | "unknown";

export interface ExecutiveSummaryRow {
  runId: string;
  runtimeTarget: string;
  tenantCode: string;
  paymentProvider: string;
  customerOrderId: string;
  orderId: number;
  orderReferenceId: string;
  orderAmount: number;
  orderCurrencyCode: string;
  threeDsSetting: ThreeDsSetting;
  journeyOutcome: string;
  challengeOutcome: ChallengeOutcome;
  verificationOutcome: string;
  cleanupOutcome: CleanupOutcome;
  /** Human-readable callback status message displayed on the final payment page (success or failure). */
  outcomeMessage: string;
  /** Exact error detail captured from exceptions or provider error banners; empty string when no error occurred. */
  errorDetail: string;
  startedUtc: string;
  finishedUtc: string;
  evidenceReference: string;
}

export interface ReportComposer {
  compose(rows: ExecutiveSummaryRow[]): Promise<string>;
}
