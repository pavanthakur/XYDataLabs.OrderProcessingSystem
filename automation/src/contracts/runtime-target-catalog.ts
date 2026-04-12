export type VerificationMode = "physical" | "azure";
export type BrowserMode = "local" | "docker" | "azure";
export type ChallengeCapability = "unsupported" | "otp-spike-pending" | "supported";
export type ExpectedTenantSource = "runtime-configuration" | "catalog";
export type RuntimeKind = "local" | "docker" | "azure";
export type EnvironmentName = "dev" | "stg" | "prod";
export type RuntimeProfile = "http" | "https";

export interface RuntimeTargetDefinition {
  key: string;
  baseUrl: string;
  verificationMode: VerificationMode;
  browserMode: BrowserMode;
  expectedTenantSource: ExpectedTenantSource;
  challengeCapability: ChallengeCapability;
  supportsPartialExecution: boolean;
  supportsHeadless: boolean;
  runtime: RuntimeKind;
  environment: EnvironmentName;
  profile: RuntimeProfile;
  paymentPagePath: string;
  ignoreHttpsErrors: boolean;
}

export interface RuntimeTargetCatalog {
  resolve(targetKey: string): Promise<RuntimeTargetDefinition>;
}
