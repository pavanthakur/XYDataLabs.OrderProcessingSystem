import type { ChallengeOutcome } from "./provider-challenge-handler.js";
import type { CleanupOutcome } from "./payment-fixture-provisioner.js";

export type ThreeDsSetting = "enabled" | "disabled" | "unknown";

export interface ExecutiveSummaryRow {
  runId: string;
  runtimeTarget: string;
  tenantCode: string;
  paymentProvider: string;
  threeDsSetting: ThreeDsSetting;
  journeyOutcome: string;
  challengeOutcome: ChallengeOutcome;
  verificationOutcome: string;
  cleanupOutcome: CleanupOutcome;
  startedUtc: string;
  finishedUtc: string;
  evidenceReference: string;
}

export interface ReportComposer {
  compose(rows: ExecutiveSummaryRow[]): Promise<string>;
}
