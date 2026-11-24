export const assignedSandboxRoutes = { TenantA: "Razorpay", TenantB: "Razorpay", TenantC: "OpenPay" } as const;
export type NonAdminSandboxIdentity = { objectId: string; directoryId: string; apiClientId: string };

export function assertNonAdminSandboxClaims(token: string, tenant: string, expected: NonAdminSandboxIdentity): void {
  let claims: Record<string, unknown>;
  try {
    const parts = token.split(".");
    if (parts.length !== 3) throw new Error();
    claims = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    if (!claims || typeof claims !== "object") throw new Error();
  } catch { throw new Error("Expected a delegated Entra API token; no order was created."); }
  const roles = claims.roles;
  const failed: string[] = [];
  if (String(claims.oid ?? "").toLowerCase() !== expected.objectId.toLowerCase()) failed.push("guest-account");
  if (String(claims.tid ?? "").toLowerCase() !== expected.directoryId.toLowerCase()) failed.push("directory");
  if (![expected.apiClientId, `api://${expected.apiClientId}`].map(value => value.toLowerCase()).includes(String(claims.aud ?? "").toLowerCase())) failed.push("api-audience");
  if (!String(claims.scp ?? "").split(/\s+/).includes("access_as_user")) failed.push("delegated-scope");
  if (claims["extn.applicationTenantCode"] !== tenant) failed.push("application-tenant");
  if (roles !== undefined && (!Array.isArray(roles) || roles.some(role => typeof role !== "string" || ["platform-admin", "phase10-operator"].includes(role.toLowerCase())))) failed.push("privileged-or-invalid-roles");
  if (failed.length) throw new Error(`Non-admin identity checks failed: ${failed.join(", ")}; no order was created.`);
}

export function assertAssignedSandboxRoutes(tenants: readonly { tenantCode: string; paymentProviderCode?: string | null }[]): void {
  const expected = Object.entries(assignedSandboxRoutes);
  if (tenants.length !== expected.length || expected.some(([code, provider]) =>
    tenants.filter(tenant => tenant.tenantCode === code && tenant.paymentProviderCode?.toLowerCase() === provider.toLowerCase()).length !== 1)) {
    throw new Error("Azure-dev tenant/provider routes differ from the approved assigned-provider matrix. No provider settings or orders were changed.");
  }
}
