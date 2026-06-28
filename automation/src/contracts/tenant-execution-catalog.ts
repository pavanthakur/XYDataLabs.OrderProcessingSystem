export interface TenantResolutionFailure {
  tenantCode: string;
  reason: string;
}

export interface TenantExecutionItem {
  tenantCode: string;
  tenantTier: string;
  paymentProviderCode: string | null;
}

export interface TenantExecutionPlan {
  resolvedTenants: TenantExecutionItem[];
  skippedTenantCodes: string[];
  failures: TenantResolutionFailure[];
}

export interface TenantExecutionCatalog {
  resolve(
    tenantCodes: string[],
    allowPartialExecution: boolean,
    logger?: (message: string) => void
  ): Promise<TenantExecutionPlan>;
}
