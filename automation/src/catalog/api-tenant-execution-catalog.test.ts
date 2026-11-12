import assert from "node:assert/strict";
import { test } from "node:test";
import type { TestContext } from "node:test";
import { ApiTenantExecutionCatalog } from "./api-tenant-execution-catalog.js";
import type { RuntimeTargetDefinition } from "../contracts/runtime-target-catalog.js";

const target: RuntimeTargetDefinition = {
  key: "azure-dev",
  runtime: "azure",
  environment: "dev",
  profile: "http",
  baseUrl: "https://ui.example.test",
  apiBaseUrl: "https://api.example.test",
  verificationMode: "azure",
  browserMode: "azure",
  expectedTenantSource: "runtime-configuration",
  supportsPartialExecution: false,
  supportsHeadless: true,
  paymentPagePath: "/payments/new",
  ignoreHttpsErrors: false,
};

const runtimeConfiguration = {
  activeTenantCode: "Clinic-West-47",
  configuredActiveTenantCode: "Clinic-West-47",
  tenantHeaderName: "X-Tenant-Code",
  availableTenants: [
    { tenantId: 11, tenantCode: "Clinic-West-47", tenantName: "West Clinic" },
    { tenantId: 12, tenantCode: "Tenant-Delta", tenantName: "Delta" },
  ],
};

function registryResponse() {
  return [
    { tenantId: 11, tenantCode: "Clinic-West-47", tenantName: "West Clinic", tenantTier: "SharedPool", paymentProviderCode: "Razorpay" },
    { tenantId: 12, tenantCode: "Tenant-Delta", tenantName: "Delta", tenantTier: "Dedicated", paymentProviderCode: "OpenPay" },
  ];
}

function installFetch(t: TestContext, registry: unknown = registryResponse()) {
  const originalFetch = globalThis.fetch;
  const requested: Array<{ url: string; headers?: Headers }> = [];
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    requested.push({ url, headers: new Headers(init?.headers) });
    if (url.endsWith("/api/v1/Info/runtime-configuration")) {
      return Response.json(runtimeConfiguration);
    }
    if (url.endsWith("/api/v1/Info/tenant-registry")) {
      if (registry instanceof Error) throw registry;
      return Response.json(registry);
    }
    throw new Error("Unexpected synthetic request.");
  }) as typeof fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  return requested;
}

test("runtime tenant discovery resolves arbitrary shared and dedicated registry tenants", async (t) => {
  const requested = installFetch(t);
  const result = await new ApiTenantExecutionCatalog(target).resolve([], false);
  assert.deepEqual(result.resolvedTenants.map((tenant) => [tenant.tenantCode, tenant.tenantTier, tenant.paymentProviderCode]), [
    ["Clinic-West-47", "SharedPool", "Razorpay"],
    ["Tenant-Delta", "Dedicated", "OpenPay"],
  ]);
  const registryRequest = requested.find((request) => request.url.endsWith("/tenant-registry"));
  assert.equal(registryRequest?.headers?.get("x-tenant-code"), "Clinic-West-47");
});

test("runtime discovery rejects registry tenants absent from runtime configuration", async (t) => {
  installFetch(t, [
    ...registryResponse(),
    { tenantId: 13, tenantCode: "Tenant-Unconfigured", tenantName: "Unknown", tenantTier: "Dedicated", paymentProviderCode: "OpenPay" },
  ]);
  await assert.rejects(new ApiTenantExecutionCatalog(target).resolve([], false), /not present in runtime configuration/);
});

test("runtime discovery rejects missing provider assignment and unsupported tier", async (t) => {
  for (const [record, expected] of [
    [{ ...registryResponse()[0], paymentProviderCode: null }, /missing paymentProviderCode/],
    [{ ...registryResponse()[0], tenantTier: "Unknown" }, /unsupported tenantTier/],
  ] as const) {
    installFetch(t, [record]);
    await assert.rejects(new ApiTenantExecutionCatalog(target).resolve([], false), expected);
  }
});

test("Azure tenant discovery fails closed when the registry endpoint is unavailable", async (t) => {
  const requested = installFetch(t, new Error("synthetic unavailable endpoint"));
  await assert.rejects(new ApiTenantExecutionCatalog(target).resolve([], false), /Azure execution must fail closed/);
  assert.equal(requested.length, 2, "Azure must not fall back to a local SQL registry lookup.");
});
