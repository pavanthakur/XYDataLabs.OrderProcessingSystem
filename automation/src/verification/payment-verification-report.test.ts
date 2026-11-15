import test from "node:test";
import assert from "node:assert/strict";
import { validatePaymentVerificationReport,verificationSafetyEstablished } from "./payment-verification-report.js";
import type { VerificationRequest } from "../contracts/verification-adapter.js";
const request: VerificationRequest = { runtimeTarget:"azure-dev",runtime:"azure",environment:"dev",profile:"https",runPrefix:"fixture",tenantCode:"TenantD",providerPaymentId:"pay_fixture",customerOrderId:"ORDER-1",orderReferenceId:"reference",startedUtc:new Date(Date.now()-300000).toISOString() };
function valid() {
  const names=["Q8 bleed","Q9 bleed","API log -> DB charge IDs","UI telemetry -> callbacks present where expected","App Insights query execution","Provider payment IDs -> request/dependency correlation",...["Pre-flight 3DS","Q2 rows","Q5 steps","Successful charge","Paid order"].map(name=>`${name} [TenantD]`)];
  return {SchemaVersion:1,EvidenceKind:"payment-correlation",Runtime:"azure",Environment:"dev",RunPrefix:"fixture",GeneratedUtc:new Date().toISOString(),ChargeCorrelation:[{Tenant:"TenantD",CustomerOrderId:"ORDER-1",InDb:true,DbStatus:"completed",UiCallbackExpected:true,UiCallbackLogged:true}],Checks:Object.fromEntries(names.map(name=>[name,{Expected:"fixture",Actual:"fixture",Outcome:"PASS"}]))};
}

test("complete versioned check inventory passes for an arbitrary tenant",()=>assert.deepEqual(validatePaymentVerificationReport(valid(),request),[]));

test("positive callback proof cannot be waived by a green check or a disabled 3DS flag",()=>{
  const report=valid();report.ChargeCorrelation[0].UiCallbackExpected=false;
  assert.ok(validatePaymentVerificationReport(report,request).length);
  assert.equal(verificationSafetyEstablished(report,request),false);
  report.ChargeCorrelation[0].UiCallbackExpected=true;report.ChargeCorrelation[0].UiCallbackLogged=false;
  assert.ok(validatePaymentVerificationReport(report,request).length);
  assert.equal(verificationSafetyEstablished(report,request),true);
});
function rejectsStatus(status:string){
  const report=valid(); report.Checks["Q8 bleed"].Outcome=status;
  assert.ok(validatePaymentVerificationReport(report,request).length);
}
function rejectsReport(value:unknown){assert.ok(validatePaymentVerificationReport(value,request).length);}
test("FAIL status fails closed",()=>rejectsStatus("FAIL"));
test("INCONCLUSIVE status fails closed",()=>rejectsStatus("INCONCLUSIVE"));
test("SKIP status fails closed",()=>rejectsStatus("SKIP"));
test("BLOCKED status fails closed",()=>rejectsStatus("BLOCKED"));
test("unknown status fails closed",()=>rejectsStatus("unknown"));
test("empty status fails closed",()=>rejectsStatus(""));
test("null report cannot pass",()=>rejectsReport(null));
test("empty report cannot pass",()=>rejectsReport({}));
test("array report cannot pass",()=>rejectsReport([]));
test("empty checks cannot pass",()=>rejectsReport({Checks:{}}));
test("array checks cannot pass",()=>rejectsReport({Checks:[]}));
test("unexpected-only checks cannot pass",()=>rejectsReport({Checks:{unexpected:{Outcome:"PASS"}}}));
test("omitted mandatory check cannot pass even when remaining checks pass",()=>{
  const report=valid();delete report.Checks["Successful charge [TenantD]"];
  assert.ok(validatePaymentVerificationReport(report,request).some(item=>item.includes("Successful charge")));
});
test("wrong schema, runtime, environment and missing provider ID block",()=>{
  for(const change of [{SchemaVersion:2},{Runtime:"docker"},{Environment:"prod"},{EvidenceKind:"dry-run"}]) assert.ok(validatePaymentVerificationReport({...valid(),...change},request).length);
  assert.ok(validatePaymentVerificationReport(valid(),{...request,providerPaymentId:undefined}).length);
});
test("untrusted diagnostic values never appear in findings",()=>{
  const report=valid();report.Checks["untrusted-secret"]={Outcome:"raw-sensitive-value",Expected:"sensitive",Actual:"sensitive"};
  assert.doesNotMatch(validatePaymentVerificationReport(report,request).join(" "),/raw-sensitive|untrusted-secret/);
});
test("stale or wrong-run reports cannot satisfy a new case",()=>{
  assert.ok(validatePaymentVerificationReport({...valid(),RunPrefix:"other"},request).length);
  assert.ok(validatePaymentVerificationReport({...valid(),GeneratedUtc:"2000-01-01T00:00:00Z"},request).length);
});
test("pending cross-tenant or wrong-order charge correlation cannot pass",()=>{
  for(const change of [{DbStatus:"created"},{Tenant:"Other"},{CustomerOrderId:"ORDER-2"},{InDb:false}]){
    const report=valid();Object.assign(report.ChargeCorrelation[0],change);
    assert.ok(validatePaymentVerificationReport(report,request).length);
  }
});
test("isolated telemetry gaps may continue but shared safety and money-state failures stop",()=>{
  const report=valid();report.Checks["UI telemetry -> callbacks present where expected"].Outcome="FAIL";
  assert.equal(verificationSafetyEstablished(report,request),true);
  report.Checks["Q8 bleed"].Outcome="FAIL";assert.equal(verificationSafetyEstablished(report,request),false);
  report.Checks["Q8 bleed"].Outcome="PASS";report.Checks["Paid order [TenantD]"].Outcome="FAIL";
  assert.equal(verificationSafetyEstablished(report,request),false);
  assert.equal(verificationSafetyEstablished({},request),false);
});
