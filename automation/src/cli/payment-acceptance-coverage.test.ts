import { test } from "node:test";
import assert from "node:assert/strict";
import { hasExactPaymentAcceptanceCoverage } from "./payment-acceptance-coverage.js";

test("accepts complete all-tenant two-provider coverage in any execution order", () => {
  const expected = ["TenantA|Razorpay|positive", "TenantA|OpenPay|positive", "TenantC|Razorpay|positive", "TenantC|OpenPay|positive"];
  assert.equal(hasExactPaymentAcceptanceCoverage(expected, [...expected].reverse()), true);
});

test("rejects omitted, duplicate, unexpected, and empty coverage", () => {
  const expected = ["TenantA|Razorpay|positive", "TenantA|OpenPay|positive"];
  assert.equal(hasExactPaymentAcceptanceCoverage(expected, [expected[0]]), false);
  assert.equal(hasExactPaymentAcceptanceCoverage(expected, [expected[0], expected[0]]), false);
  assert.equal(hasExactPaymentAcceptanceCoverage(expected, [expected[0], "TenantB|OpenPay|positive"]), false);
  assert.equal(hasExactPaymentAcceptanceCoverage([], []), false);
});
