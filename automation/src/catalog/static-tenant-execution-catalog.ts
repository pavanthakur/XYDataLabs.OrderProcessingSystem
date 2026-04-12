import type { TenantExecutionCatalog, TenantExecutionPlan } from "../contracts/tenant-execution-catalog.js";

const supportedTenantCodes = ["TenantA", "TenantB", "TenantC"] as const;

export class StaticTenantExecutionCatalog implements TenantExecutionCatalog {
  public async resolve(tenantCodes: string[], allowPartialExecution: boolean): Promise<TenantExecutionPlan> {
    const normalizedTenantCodes = tenantCodes.length > 0
      ? Array.from(new Set(tenantCodes.map((tenantCode) => tenantCode.trim()).filter(Boolean)))
      : Array.from(supportedTenantCodes);

    const resolvedTenantCodes: string[] = [];
    const failures: TenantExecutionPlan["failures"] = [];

    for (const tenantCode of normalizedTenantCodes) {
      if (supportedTenantCodes.includes(tenantCode as (typeof supportedTenantCodes)[number])) {
        resolvedTenantCodes.push(tenantCode);
        continue;
      }

      failures.push({ tenantCode, reason: "Unsupported tenant code for the initial automation slice." });
    }

    if (failures.length > 0 && !allowPartialExecution) {
      throw new Error(failures.map((failure) => `${failure.tenantCode}: ${failure.reason}`).join("; "));
    }

    return {
      resolvedTenantCodes,
      skippedTenantCodes: failures.map((failure) => failure.tenantCode),
      failures
    };
  }
}
