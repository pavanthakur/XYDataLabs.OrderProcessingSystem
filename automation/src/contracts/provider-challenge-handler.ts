export type ChallengeOutcome = "passed" | "partial" | "failed" | "not-applicable";

export interface ProviderChallengeContext {
  tenantCode: string;
  sandboxOtpCode?: string;
  diagnosticsDirectory?: string;
}

export interface ProviderChallengeHandler {
  execute(context: ProviderChallengeContext): Promise<ChallengeOutcome>;
}
