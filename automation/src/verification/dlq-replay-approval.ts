export interface DlqReplayApproval {
  quarantineId: string;
  replayRequestId: string;
  state: string;
  approvedUtc: string;
  alreadyApproved: boolean;
}

export interface DlqReplayApprovalRequest {
  environment: string;
  apiBaseUrl: string;
  tenantCode: string;
  quarantineId: string;
  accessToken: string;
  timeoutMs?: number;
  fetchImpl?: typeof fetch;
}

const guidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function tokenHasRoleClaim(accessToken: string, requiredRole: string): boolean {
  const parts = accessToken.split(".");
  if (parts.length !== 3 || !parts[1]) return false;
  try {
    const claims: unknown = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    if (claims === null || typeof claims !== "object" || Array.isArray(claims)) return false;
    const roles = (claims as Record<string, unknown>).roles;
    return (Array.isArray(roles) ? roles : typeof roles === "string" ? [roles] : [])
      .some(role => role === requiredRole);
  } catch {
    return false;
  }
}

function readString(source: Record<string, unknown>, camel: string, pascal: string): string | undefined {
  const value = source[camel] ?? source[pascal];
  return typeof value === "string" ? value : undefined;
}

/**
 * Requests one DLQ approval from the application's protected API.
 * The JWT role check is only a fail-fast UX guard; the API remains the authority
 * and must validate signature, issuer, audience, scope, expiry, and role.
 * This function never retries the state-changing POST and never emits the token
 * or response body in an error.
 */
export async function approveDlqReplay(request: DlqReplayApprovalRequest): Promise<DlqReplayApproval> {
  if (request.environment !== "dev") throw new Error("DLQ replay approval automation is restricted to Azure dev.");
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(request.tenantCode)) throw new Error("A valid tenant code is required; no approval was sent.");
  if (!guidPattern.test(request.quarantineId)) throw new Error("A valid quarantine ID is required; no approval was sent.");
  if (!tokenHasRoleClaim(request.accessToken, "phase10-operator")) {
    throw new Error("The Entra access token has no phase10-operator role claim; no approval was sent.");
  }

  let base: URL;
  try {
    base = new URL(request.apiBaseUrl);
  } catch {
    throw new Error("The configured Azure API URL is invalid; no approval was sent.");
  }
  if (base.protocol !== "https:" || base.username || base.password || base.search || base.hash || base.pathname !== "/") {
    throw new Error("DLQ replay approval requires a clean HTTPS API origin; no approval was sent.");
  }

  const timeoutMs = request.timeoutMs ?? 15000;
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1000 || timeoutMs > 60000) {
    throw new Error("DLQ replay approval timeout must be between 1 and 60 seconds.");
  }
  const fetchImpl = request.fetchImpl ?? fetch;
  let response: Response;
  try {
    response = await fetchImpl(
      new URL(`/api/v1/admin/dlq/${request.quarantineId}/approve`, base),
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${request.accessToken}`,
          accept: "application/json",
          "x-tenant-code": request.tenantCode
        },
        signal: AbortSignal.timeout(timeoutMs)
      });
  } catch {
    throw new Error("The DLQ approval request failed or timed out; it was not retried. Reconcile the request state before another attempt.");
  }

  if (response.status === 401 || response.status === 403) {
    throw new Error(`The application rejected DLQ approval (${response.status}); no replay acceptance is claimed.`);
  }
  if (response.status === 404) throw new Error("The quarantine record was not found; no replay approval was created.");
  if (!response.ok) throw new Error(`The DLQ approval API returned HTTP ${response.status}; no replay acceptance is claimed.`);

  let payload: unknown;
  try {
    payload = await response.json();
  } catch {
    throw new Error("The DLQ approval API returned malformed JSON; reconcile its state before another attempt.");
  }
  if (payload === null || typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error("The DLQ approval API returned an invalid result; reconcile its state before another attempt.");
  }
  const result = payload as Record<string, unknown>;
  const quarantineId = readString(result, "quarantineId", "QuarantineId");
  const replayRequestId = readString(result, "replayRequestId", "ReplayRequestId");
  const state = readString(result, "state", "State");
  const approvedUtc = readString(result, "approvedUtc", "ApprovedUtc");
  const alreadyApproved = result.alreadyApproved ?? result.AlreadyApproved;
  if (quarantineId?.toLowerCase() !== request.quarantineId.toLowerCase()
      || !replayRequestId || !guidPattern.test(replayRequestId)
      || state?.toLowerCase() !== "approved"
      || !approvedUtc || !Number.isFinite(Date.parse(approvedUtc))
      || typeof alreadyApproved !== "boolean") {
    throw new Error("The DLQ approval API response did not match the requested quarantine; reconcile its state before another attempt.");
  }
  return { quarantineId, replayRequestId, state, approvedUtc, alreadyApproved };
}
