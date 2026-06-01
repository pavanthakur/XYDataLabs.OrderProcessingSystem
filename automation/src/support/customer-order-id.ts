export function buildRunPrefix(now: Date): string {
  const runNumber = Math.floor(now.getTime() / 1000);
  const dayTag = now.toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short"
  }).replace(/\s+/g, "");

  return `OR-${runNumber}-${dayTag}`;
}

export function buildCustomerOrderId(
  runPrefix: string,
  tenantCode: string,
  profile: string,
  runtime: string,
  providerType?: string
): string {
  const providerTag = providerType ? resolveProviderTag(providerType) : "auto";
  return `${runPrefix}-${resolveTenantTag(tenantCode)}-${profile}-${runtime}-${providerTag}`.replace(/\s+/g, "");
}

function resolveTenantTag(tenantCode: string): string {
  switch (tenantCode) {
    case "TenantA":
      return "tA";
    case "TenantB":
      return "tB";
    case "TenantC":
      return "tC";
    default:
      return tenantCode;
  }
}

function resolveProviderTag(providerType: string): string {
  switch (providerType.trim().toLowerCase()) {
    case "openpay":
      return "op";
    case "razorpay":
      return "rz";
    default:
      return providerType;
  }
}
