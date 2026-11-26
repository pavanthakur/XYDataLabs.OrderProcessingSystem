export interface ReplayApproverTokenExpectation {
  objectId: string;
  directoryId: string;
  apiClientId: string;
  tenantCode: string;
}

const isGuid = (value: string): boolean => /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value);

/** Fail-closed local check for the delegated API token used by the replay approver. */
export function assertReplayApproverToken(accessToken: string, expected: ReplayApproverTokenExpectation): void {
  let claims: Record<string, unknown>;
  try {
    const parts = accessToken.split(".");
    if (parts.length !== 3) throw new Error();
    const decoded: unknown = JSON.parse(Buffer.from(parts[1]!, "base64url").toString("utf8"));
    if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) throw new Error();
    claims = decoded as Record<string, unknown>;
  } catch {
    throw new Error("The authenticated browser did not provide a valid API access token; no replay action was performed.");
  }

  const roles = claims.roles;
  const tenantClaim = claims["extn.applicationTenantCode"];
  const tenantValues = Array.isArray(tenantClaim) ? tenantClaim : [tenantClaim];
  const expectedAudiences = [expected.apiClientId, `api://${expected.apiClientId}`].map(value => value.toLowerCase());
  const valid = isGuid(expected.objectId) && isGuid(expected.directoryId) && isGuid(expected.apiClientId)
    && String(claims.oid ?? "").toLowerCase() === expected.objectId.toLowerCase()
    && String(claims.tid ?? "").toLowerCase() === expected.directoryId.toLowerCase()
    && expectedAudiences.includes(String(claims.aud ?? "").toLowerCase())
    && String(claims.scp ?? "").split(/\s+/).includes("access_as_user")
    && Array.isArray(roles) && roles.length === 1 && roles[0] === "phase10-operator"
    && tenantValues.length === 1 && typeof tenantValues[0] === "string"
    && tenantValues[0].trim().toLowerCase() === expected.tenantCode.trim().toLowerCase();

  if (!valid) {
    throw new Error("The API token does not match the pinned replay approver, API audience, delegated scope, TenantA claim, and phase10-operator role; no replay action was performed.");
  }
}
