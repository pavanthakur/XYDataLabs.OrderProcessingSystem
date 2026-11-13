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
  publicUiBaseUrl?: string;
  publicApiBaseUrl?: string;
  publicUrlMode?: "catalog" | "generated";
  allowGeneratedAzureUrlFallback?: boolean;
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
  azureManagedEnvironmentName?: string;
  azureGatewayContainerAppName?: string;
  azureOrdersContainerAppName?: string;
  azurePaymentsContainerAppName?: string;
  azureInventoryContainerAppName?: string;
  azureNotificationsContainerAppName?: string;
  azureUiContainerAppName?: string;
  azureFunctionAppName?: string;
  azureSqlServerName?: string;
  azureOperationsDatabaseName?: string;
  azureRedisName?: string;
  azureBrokerSuffix?: string;
  azureServiceBusNamespaceName?: string;
  azureReplayRequestQueueName?: string;
  azureApplicationInsightsName?: string;
  azureKeyVaultName?: string;
  ignoreHttpsErrors: boolean;
}

export interface RuntimeTargetCatalog {
  resolve(targetKey: string): Promise<RuntimeTargetDefinition>;
}
