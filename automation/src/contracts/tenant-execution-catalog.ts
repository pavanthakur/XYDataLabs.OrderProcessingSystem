export interface TenantResolutionFailure {
  tenantCode: string;
  reason: string;
}

export interface TenantExecutionPlan {
  resolvedTenantCodes: string[];
  skippedTenantCodes: string[];
  failures: TenantResolutionFailure[];
}

export interface TenantExecutionCatalog {
  resolve(tenantCodes: string[], allowPartialExecution: boolean): Promise<TenantExecutionPlan>;
}
