export type AuthPreflightSignOutEvidence = {
  journeyOutcome: string;
  outcomeMessage: string;
};

export function isAuthPreflightSignOutVerified(rows: readonly AuthPreflightSignOutEvidence[]): boolean {
  return rows.some(row => row.journeyOutcome === "auth-preflight-passed"
    && /application sign-out verified\./i.test(row.outcomeMessage));
}
