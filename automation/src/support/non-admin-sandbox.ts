export const assignedSandboxRoutes = { TenantA: "Razorpay", TenantB: "Razorpay", TenantC: "OpenPay" } as const;
export type NonAdminIdentityType = "guest" | "member";
export type NonAdminSandboxIdentity = { objectId: string; directoryId: string; apiClientId: string; identityType: NonAdminIdentityType };

const expectedTenantCodes = ["TenantA", "TenantB", "TenantC"] as const;
const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value);
const isGuid = (value: unknown): value is string => typeof value === "string" && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value);

// The API registration names the source as extension_<appId>_applicationTenantCode;
// Entra emits its JWT claim as extn.applicationTenantCode.
export const applicationTenantClaimType = "extn.applicationTenantCode";

export function mapNonAdminSandboxIdentities(value: unknown, expectedIdentityType: NonAdminIdentityType): Record<string, NonAdminSandboxIdentity> {
  if (!isRecord(value)) throw new Error("The private non-admin identity manifest is invalid; no browser or order was started.");
  const manifestType = value.identityType === undefined ? "guest" : value.identityType;
  if (manifestType !== expectedIdentityType) throw new Error("The selected non-admin identity type does not match its private manifest; no browser or order was started.");
  const users = value.users;
  if (value.schemaVersion !== 1 || value.environment !== "dev" || !isGuid(value.directoryId) || !isGuid(value.apiClientId) ||
      !Array.isArray(users) || users.length !== expectedTenantCodes.length) {
    throw new Error("The private non-admin identity manifest is incomplete or invalid; no browser or order was started.");
  }
  const mappings = users.filter(isRecord);
  if (mappings.length !== expectedTenantCodes.length ||
      [...mappings.map(item => item.tenantCode as string)].sort().join(",") !== [...expectedTenantCodes].sort().join(",") ||
      !mappings.every(item => isGuid(item.objectId)) ||
      new Set(mappings.map(item => (item.objectId as string).toLowerCase())).size !== expectedTenantCodes.length ||
      (expectedIdentityType === "member" && !mappings.every(item => typeof item.userPrincipalName === "string" && item.userPrincipalName.trim().length > 0)) ||
      (expectedIdentityType === "guest" && !mappings.every(item => typeof item.email === "string" && item.email.trim().length > 0))) {
    throw new Error("The private non-admin identity manifest must contain one distinct, complete identity for each required tenant; no browser or order was started.");
  }
  return Object.fromEntries(mappings.map(({ tenantCode, objectId }) => [tenantCode as string, {
    objectId: objectId as string,
    directoryId: value.directoryId as string,
    apiClientId: value.apiClientId as string,
    identityType: expectedIdentityType
  }]));
}

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
  if (String(claims.oid ?? "").toLowerCase() !== expected.objectId.toLowerCase()) failed.push("account-object-id");
  if (String(claims.tid ?? "").toLowerCase() !== expected.directoryId.toLowerCase()) failed.push("directory");
  if (![expected.apiClientId, `api://${expected.apiClientId}`].map(value => value.toLowerCase()).includes(String(claims.aud ?? "").toLowerCase())) failed.push("api-audience");
  if (!String(claims.scp ?? "").split(/\s+/).includes("access_as_user")) failed.push("delegated-scope");
  if (claims[applicationTenantClaimType] !== tenant) failed.push("application-tenant");
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
