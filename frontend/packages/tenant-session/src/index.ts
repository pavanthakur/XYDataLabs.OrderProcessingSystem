import type { RuntimeConfiguration } from "@xydatalabs/orderprocessing-api-sdk";

const activeTenantStorageKey = "orderprocessing.activeTenantCode";

export interface TenantSessionState {
  activeTenantCode: string;
  tenantHeaderName: string;
  configuredActiveTenantCode: string;
}

export interface TenantSessionController {
  initialize(runtimeConfiguration: RuntimeConfiguration, requestedTenantCode?: string | null): TenantSessionState;
  setActiveTenantCode(nextTenantCode: string): TenantSessionState;
  getState(): TenantSessionState | null;
  getActiveTenantCode(): string | null;
  getTenantHeaderName(): string | null;
}

export function createTenantSession(storage: Storage | undefined = globalThis.localStorage): TenantSessionController {
  let runtimeConfiguration: RuntimeConfiguration | null = null;
  let state: TenantSessionState | null = null;

  return {
    initialize(nextRuntimeConfiguration, requestedTenantCode) {
      runtimeConfiguration = nextRuntimeConfiguration;

      const activeTenantCode = resolveTenantCode(nextRuntimeConfiguration, requestedTenantCode);
      state = {
        activeTenantCode,
        tenantHeaderName: nextRuntimeConfiguration.tenantHeaderName,
        configuredActiveTenantCode: nextRuntimeConfiguration.configuredActiveTenantCode
      };

      storage?.setItem(activeTenantStorageKey, activeTenantCode);
      return state;
    },

    setActiveTenantCode(nextTenantCode) {
      if (!runtimeConfiguration) {
        throw new Error("Tenant session cannot change tenants before runtime bootstrap completes.");
      }

      const activeTenantCode = resolveTenantCode(runtimeConfiguration, nextTenantCode);
      state = {
        activeTenantCode,
        tenantHeaderName: runtimeConfiguration.tenantHeaderName,
        configuredActiveTenantCode: runtimeConfiguration.configuredActiveTenantCode
      };

      storage?.setItem(activeTenantStorageKey, activeTenantCode);
      return state;
    },

    getState() {
      return state;
    },

    getActiveTenantCode() {
      return state?.activeTenantCode ?? null;
    },

    getTenantHeaderName() {
      return state?.tenantHeaderName ?? runtimeConfiguration?.tenantHeaderName ?? null;
    }
  };
}

function resolveTenantCode(runtimeConfiguration: RuntimeConfiguration, requestedTenantCode?: string | null): string {
  const matchedTenant = runtimeConfiguration.availableTenants.find((tenant) =>
    tenant.tenantCode.localeCompare(requestedTenantCode ?? "", undefined, { sensitivity: "accent" }) === 0
  );

  if (matchedTenant) {
    return matchedTenant.tenantCode;
  }

  const configuredTenant = runtimeConfiguration.availableTenants.find((tenant) =>
    tenant.tenantCode.localeCompare(runtimeConfiguration.activeTenantCode, undefined, { sensitivity: "accent" }) === 0
  );

  if (configuredTenant) {
    return configuredTenant.tenantCode;
  }

  const firstTenant = runtimeConfiguration.availableTenants[0];
  if (!firstTenant) {
    throw new Error("Runtime bootstrap did not return any active tenants.");
  }

  return firstTenant.tenantCode;
}