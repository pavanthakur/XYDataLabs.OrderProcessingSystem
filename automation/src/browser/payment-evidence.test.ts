import assert from "node:assert/strict";
import {test} from "node:test";
import {assertSandboxConfirmation,assertRuntimeMode,requiredChallengeVerified} from "./payment-evidence.js";
const completed={paymentId:"pay_fixture",status:"completed",remoteStatusConfirmed:true,isSuccess:true,isPending:false,isFailure:false};
test("confirmed payment cannot replace required visible-challenge evidence",()=>{
  assert.equal(requiredChallengeVerified(true,"not-presented","partial"),false);
  assert.equal(requiredChallengeVerified(true,"presented","submitted"),false);
  assert.equal(requiredChallengeVerified(true,"presented","passed"),true);
  assert.equal(requiredChallengeVerified(false,"not-presented","not-applicable"),true);
});
test("real final provider confirmation is required",()=>{
  assert.doesNotThrow(()=>assertSandboxConfirmation(completed));
  for(const change of [{remoteStatusConfirmed:false},{status:"authorized"},{status:"created"},{isPending:true},{isFailure:true},
    {paymentId:"DET-RAZORPAY-fixture"},{paymentId:""},{isSuccess:false}]) {
    assert.throws(()=>assertSandboxConfirmation({...completed,...change}));
  }
  assert.throws(()=>assertSandboxConfirmation(undefined));
});
test("sandbox never accepts simulation, unknown mode or live configuration",()=>{
  assert.doesNotThrow(()=>assertRuntimeMode({adapterMode:"sandbox",isProduction:false},"sandbox"));
  assert.doesNotThrow(()=>assertRuntimeMode({adapterMode:"deterministic",isProduction:false},"deterministic"));
  for(const adapterMode of ["deterministic","live","unknown",""]) assert.throws(()=>assertRuntimeMode({adapterMode,isProduction:false},"sandbox"));
  assert.throws(()=>assertRuntimeMode({adapterMode:"sandbox",isProduction:true},"sandbox"));
});
test("order amounts and currencies must be confirmed, never invented from local data",()=>{
  const expected={amount:1,currency:"INR"};
  assert.throws(()=>assertSandboxConfirmation(completed,expected));
  assert.throws(()=>assertSandboxConfirmation({...completed,providerAmount:2,providerCurrency:"INR"},expected));
  assert.throws(()=>assertSandboxConfirmation({...completed,providerAmount:1,providerCurrency:"MXN"},expected));
  assert.doesNotThrow(()=>assertSandboxConfirmation({...completed,providerAmount:1,providerCurrency:"INR"},expected));
});
