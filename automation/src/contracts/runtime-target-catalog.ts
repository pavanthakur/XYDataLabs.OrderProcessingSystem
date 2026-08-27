export type VerificationMode = "physical" | "azure";
export type BrowserMode = "local" | "docker" | "azure";
export type ExpectedTenantSource = "runtime-configuration" | "catalog";
export type RuntimeKind = "local" | "docker" | "azure";
export type EnvironmentName = "dev" | "stg" | "prod";
export type RuntimeProfile = "http" | "https";

export interface RuntimeTargetDefinition {
  key: string;
  baseUrl: string;
  apiBaseUrl?: string;
  verificationMode: VerificationMode;
  browserMode: BrowserMode;
  expectedTenantSource: ExpectedTenantSource;
  supportsPartialExecution: boolean;
  supportsHeadless: boolean;
  runtime: RuntimeKind;
  environment: EnvironmentName;
  profile: RuntimeProfile;
  paymentPagePath: string;
  azureResourceGroupName?: string;
  azureGatewayContainerAppName?: string;
  azureUiContainerAppName?: string;
  azureSqlServerName?: string;
  azureRedisName?: string;
  ignoreHttpsErrors: boolean;
}

export interface RuntimeTargetCatalog {
  resolve(targetKey: string): Promise<RuntimeTargetDefinition>;
}
