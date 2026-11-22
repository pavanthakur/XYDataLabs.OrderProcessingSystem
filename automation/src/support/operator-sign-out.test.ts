import assert from "node:assert/strict";
import { test } from "node:test";
import { isAuthPreflightSignOutVerified } from "./operator-sign-out.js";

test("auth-only operator run accepts sign-out verified by its no-charge journey", () => {
  assert.equal(isAuthPreflightSignOutVerified([{
    journeyOutcome: "auth-preflight-passed",
    outcomeMessage: "Authenticated tenant access and application sign-out verified. No payment was attempted."
  }]), true);
});

test("auth-only operator run does not infer sign-out from a successful login alone", () => {
  assert.equal(isAuthPreflightSignOutVerified([{
    journeyOutcome: "auth-preflight-passed",
    outcomeMessage: "Authenticated tenant access passed. In-memory session retained for this run."
  }]), false);
  assert.equal(isAuthPreflightSignOutVerified([{
    journeyOutcome: "failed",
    outcomeMessage: "Application sign-out verified."
  }]), false);
});
