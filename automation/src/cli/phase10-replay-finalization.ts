import type { ReservedPhase10Report } from "./phase10-report-reservation.js";

/** Persist approval facts even when sign-out fails, then fail the command. */
export async function finalizeReplayApproval(
  report: Record<string, unknown>,
  approved: boolean,
  signOut: () => Promise<void>,
  reservation: ReservedPhase10Report
): Promise<void> {
  let signOutFailed = false;
  try {
    await signOut();
    report.signOutStatus = "passed";
  } catch {
    signOutFailed = true;
    report.signOutStatus = "failed";
    report.status = approved ? "APPROVED_SIGNOUT_FAILED" : "INCOMPLETE_RECONCILIATION_REQUIRED";
    report.signOutFailure = "Entra sign-out could not be verified; inspect session state before continuing.";
  }
  report.finishedUtc = new Date().toISOString();
  try { await reservation.update(report); }
  finally { await reservation.close(); }
  if (signOutFailed) throw new Error("Replay approval sign-out failed; approval evidence was preserved, but acceptance is incomplete.");
}
