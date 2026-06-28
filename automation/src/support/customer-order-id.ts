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
  return tenantCode.trim().replace(/[^a-zA-Z0-9]+/g, "").slice(0, 12) || "tenant";
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
