const guidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function validateLocalOperatorClaims(claims, tenantCode) {
  const roles = Array.isArray(claims?.realm_access?.roles) ? claims.realm_access.roles : [];
  if (!roles.includes("phase10-operator")) {
    throw new Error("Local operator token lacks phase10-operator; no replay approval was sent.");
  }
  if (!roles.includes("platform-admin") && claims?.tenant_code !== tenantCode) {
    throw new Error("Local operator is not assigned to the replay tenant; no approval was sent.");
  }
}

export function validateLocalDlqApprovalResponse(requestedQuarantineId, payload) {
  if (!guidPattern.test(requestedQuarantineId)) throw new Error("DLQ approval requires a valid quarantine ID.");
  if (payload === null || typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error("Local replay approval returned mismatched or incomplete metadata; reconcile before another request.");
  }
  const replayRequestId = payload.replayRequestId ?? payload.ReplayRequestId;
  const returnedQuarantineId = payload.quarantineId ?? payload.QuarantineId;
  const state = payload.state ?? payload.State;
  const approvedUtc = payload.approvedUtc ?? payload.ApprovedUtc;
  const alreadyApproved = payload.alreadyApproved ?? payload.AlreadyApproved;
  if (typeof returnedQuarantineId !== "string"
      || returnedQuarantineId.toLowerCase() !== requestedQuarantineId.toLowerCase()
      || typeof replayRequestId !== "string" || !guidPattern.test(replayRequestId)
      || typeof state !== "string" || state.toLowerCase() !== "approved"
      || typeof approvedUtc !== "string" || !Number.isFinite(Date.parse(approvedUtc))
      || alreadyApproved !== false) {
    throw new Error("Local replay approval returned mismatched or incomplete metadata; reconcile before another request.");
  }
  return { quarantineId: returnedQuarantineId, replayRequestId, state, approvedUtc, alreadyApproved };
}
