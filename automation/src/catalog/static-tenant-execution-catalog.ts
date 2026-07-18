import type { TenantExecutionCatalog, TenantExecutionPlan, TenantExecutionItem, TenantResolutionFailure } from "../contracts/tenant-execution-catalog.js";

const supportedTenantCodes = ["TenantA", "TenantB", "TenantC"];

export class StaticTenantExecutionCatalog implements TenantExecutionCatalog {
  public async resolve(
    tenantCodes: string[],
    allowPartialExecution: boolean,
    logger?: (message: string) => void
  ): Promise<TenantExecutionPlan> {
    logger?.(`Static tenant catalog resolving ${tenantCodes.length > 0 ? tenantCodes.join(", ") : "default tenants"}.`);

    const normalizedTenantCodes = tenantCodes.length > 0
      ? Array.from(new Set(tenantCodes.map((tenantCode) => tenantCode.trim()).filter(Boolean)))
      : Array.from(supportedTenantCodes);

    const resolvedTenants: TenantExecutionItem[] = [];
    const failures: TenantResolutionFailure[] = [];

    for (const tenantCode of normalizedTenantCodes) {
      if (supportedTenantCodes.includes(tenantCode)) {
        resolvedTenants.push({
          tenantCode,
          tenantTier: tenantCode === "TenantC" ? "Dedicated" : "SharedPool",
          paymentProviderCode: tenantCode === "TenantC" ? "OpenPay" : "Razorpay"
        });
        continue;
      }

      failures.push({ tenantCode, reason: "Unsupported tenant code for the initial automation slice." });
    }

    if (failures.length > 0 && !allowPartialExecution) {
      throw new Error(failures.map((failure) => `${failure.tenantCode}: ${failure.reason}`).join("; "));
    }

    return {
      resolvedTenants,
      skippedTenantCodes: failures.map((failure) => failure.tenantCode),
      failures
    };
  }
}
