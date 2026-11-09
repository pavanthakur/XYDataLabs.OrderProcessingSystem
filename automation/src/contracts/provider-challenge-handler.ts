export type ChallengeOutcome = "passed" | "submitted" | "partial" | "failed" | "not-applicable";

export interface ProviderChallengeContext {
  tenantCode: string;
  sandboxOtpCode?: string;
  diagnosticsDirectory?: string;
  challengeTimeoutMs?: number;
  submissionTimeoutMs?: number;
}

export interface ProviderChallengeHandler {
  execute(context: ProviderChallengeContext): Promise<ChallengeOutcome>;
}
