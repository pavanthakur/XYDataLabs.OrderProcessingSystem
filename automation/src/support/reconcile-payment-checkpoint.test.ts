import test from "node:test";
import assert from "node:assert/strict";
import {reconcilePaymentCheckpoint,type OriginalPaymentProof} from "./reconcile-payment-checkpoint.js";
import type {MatrixCheckpoint} from "./azure-matrix-checkpoint.js";
import type {PaymentCaseLedger} from "./payment-case-ledger.js";
import type {ExecutiveSummaryRow} from "../contracts/report-composer.js";
const provenance={candidate:"source",deployment:"images",settings:"baseline"};
function fixture(){
  const row={tenantCode:"TenantD",paymentProvider:"Razorpay",runtimeTarget:"azure-dev",journeyOutcome:"completed",verificationOutcome:"failed",cleanupOutcome:"reset",adapterMode:"sandbox",customerOrderId:"ORDER-1",orderId:1,orderReferenceId:"reference",orderAmount:200,orderCurrencyCode:"INR"} as ExecutiveSummaryRow;
  const request={runtimeTarget:"azure-dev",runtime:"azure" as const,environment:"dev" as const,profile:"https" as const,tenantCode:"TenantD",runPrefix:"fixture",customerOrderId:"ORDER-1",orderReferenceId:"reference",providerPaymentId:"pay_fixture",sqlAuthenticationMode:"entra" as const,startedUtc:"2026-11-15T08:00:00Z",finishedUtc:"2026-11-15T08:01:00Z"};
  const checkpoint:MatrixCheckpoint={schemaVersion:1,binding:"binding",provenance,plannedKeys:["tenantd|razorpay"],cases:[{key:"tenantd|razorpay",state:"verification-pending",row,request,ledgerPath:"TenantD/razorpay/case-ledger.json"}]};
  const ledger:PaymentCaseLedger={schemaVersion:1,tenantCode:"TenantD",provider:"Razorpay",runtimeTarget:"azure-dev",runPrefix:"fixture",startedUtc:request.startedUtc,finishedUtc:"2026-11-15T08:03:00Z",mutation:"provider-confirmed",journey:"completed",verification:"blocked",restoration:"passed",row,anchors:{customerOrderId:"ORDER-1",orderReferenceId:"reference",providerPaymentId:"pay_fixture"}};
  const proof:OriginalPaymentProof={tenant:"TenantD",orderId:1,orderReferenceId:"reference",amount:200,currency:"INR",adapterMode:"sandbox",confirmation:{paymentId:"pay_fixture",status:"completed",remoteStatusConfirmed:true,isSuccess:true,isPending:false,isFailure:false,providerAmount:200,providerCurrency:"INR"}};
  const names=["Q8 bleed","Q9 bleed","API log -> DB charge IDs","UI telemetry -> callbacks present where expected","App Insights query execution","Provider payment IDs -> request/dependency correlation",...["Pre-flight 3DS","Q2 rows","Q5 steps","Successful charge","Paid order"].map(name=>`${name} [TenantD]`)];
  const rawReport={SchemaVersion:1,EvidenceKind:"payment-correlation",Runtime:"azure",Environment:"dev",RunPrefix:"fixture",GeneratedUtc:new Date().toISOString(),ChargeCorrelation:[{Tenant:"TenantD",CustomerOrderId:"ORDER-1",InDb:true,DbStatus:"completed",UiCallbackExpected:true,UiCallbackLogged:true}],Checks:Object.fromEntries(names.map(name=>[name,{Expected:1,Actual:1,Outcome:"PASS"}]))};
  return {checkpoint,ledger,proof,rawReport};
}
test("verification-only recovery promotes a copy without repeating a payment",async()=>{
  const f=fixture();let calls=0;
  const output=await reconcilePaymentCheckpoint(f.checkpoint,provenance,async()=>f,async request=>{calls++;assert.equal(request.providerPaymentId,"pay_fixture");return {outcome:"passed",summary:"mock",rawReport:f.rawReport};});
  assert.equal(calls,1);assert.equal(output.checkpoint.cases[0].state,"verified-restored");assert.equal(f.checkpoint.cases[0].state,"verification-pending");
});
test("a green command without required report evidence cannot promote recovery",async()=>{
  const f=fixture();const output=await reconcilePaymentCheckpoint(f.checkpoint,provenance,async()=>f,async()=>({outcome:"passed",summary:"empty",rawReport:{}}));
  assert.equal(output.checkpoint.cases[0].state,"verification-pending");assert.equal(output.reports[0].result.outcome,"failed");
});
async function refusesFault(fault:string){
    const f=fixture();let calls=0;const current={...provenance};
    if(fault==="candidate")current.candidate="changed";
    if(fault==="restoration")f.ledger.restoration="blocked";
    if(fault==="ambiguous-submission")f.checkpoint.cases[0].state="started";
    if(fault==="terms")f.proof.amount=201;
    if(fault==="tenant")f.checkpoint.cases[0].request!.tenantCode="Other";
    if(fault==="auth-mode")f.checkpoint.cases[0].request!.sqlAuthenticationMode="key-vault";
    if(fault==="duplicate")f.checkpoint.cases.push(f.checkpoint.cases[0]);
    if(fault==="missing-id")f.proof.confirmation.paymentId="";
    await assert.rejects(()=>reconcilePaymentCheckpoint(f.checkpoint,current,async()=>f,async()=>{calls++;return {outcome:"passed",summary:"must not execute"};}));
    assert.equal(calls,0);
}
test("recovery refuses changed candidate before verification",()=>refusesFault("candidate"));
test("recovery refuses unrestored settings before verification",()=>refusesFault("restoration"));
test("recovery refuses ambiguous submission before verification",()=>refusesFault("ambiguous-submission"));
test("recovery refuses mismatched terms before verification",()=>refusesFault("terms"));
test("recovery refuses cross-tenant anchors before verification",()=>refusesFault("tenant"));
test("recovery refuses alternate credential mode before verification",()=>refusesFault("auth-mode"));
test("recovery refuses duplicate cases before verification",()=>refusesFault("duplicate"));
test("recovery refuses missing provider ID before verification",()=>refusesFault("missing-id"));
