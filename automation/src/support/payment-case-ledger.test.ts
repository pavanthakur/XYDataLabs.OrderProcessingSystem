import test from "node:test";
import assert from "node:assert/strict";
import {recordCaseProgress,verificationOnlyRecoveryEligible,type PaymentCaseLedger} from "./payment-case-ledger.js";
import type {ExecutiveSummaryRow} from "../contracts/report-composer.js";
function ledger():PaymentCaseLedger{return {schemaVersion:1,tenantCode:"TenantD",provider:"Razorpay",runtimeTarget:"azure-dev",runPrefix:"fixture",startedUtc:"fixture",mutation:"preparing",journey:"pending",verification:"pending",restoration:"pending"};}
function order(value:PaymentCaseLedger){recordCaseProgress(value,{stage:"order-persisted",orderId:1,customerOrderId:"ORDER-1",orderReferenceId:"reference",amount:200,currency:"INR"});}
test("order and submission intent survive independently of later verification",()=>{
  const value=ledger();order(value);recordCaseProgress(value,{stage:"submission-started"});
  assert.equal(value.anchors?.customerOrderId,"ORDER-1");assert.equal(value.verification,"pending");
  assert.equal(verificationOnlyRecoveryEligible(value),false);
});
test("cannot skip intent, confirm without provider ID or submit twice",()=>{
  const value=ledger();assert.throws(()=>recordCaseProgress(value,{stage:"submission-started"}));
  order(value);recordCaseProgress(value,{stage:"submission-started"});
  assert.throws(()=>recordCaseProgress(value,{stage:"provider-confirmed"}));
  assert.throws(()=>recordCaseProgress(value,{stage:"submission-started"}));
});
test("a confirmed payment with failed verification permits read-only recovery only after restoration",()=>{
  const value=ledger();order(value);recordCaseProgress(value,{stage:"submission-started"});recordCaseProgress(value,{stage:"provider-confirmed",providerPaymentId:"pay_fixture"});
  value.journey="completed";value.verification="blocked";value.row={adapterMode:"sandbox"} as ExecutiveSummaryRow;
  assert.equal(verificationOnlyRecoveryEligible(value),false);value.restoration="passed";
  assert.equal(verificationOnlyRecoveryEligible(value),true);
  value.restoration="blocked";assert.equal(verificationOnlyRecoveryEligible(value),false);
});
