import type {MatrixCheckpoint} from "./azure-matrix-checkpoint.js";
import {assertResumeSafe} from "./azure-matrix-checkpoint.js";
import {verificationOnlyRecoveryEligible,type PaymentCaseLedger} from "./payment-case-ledger.js";
import type {VerificationRequest,VerificationResult} from "../contracts/verification-adapter.js";
import {assertSandboxConfirmation,type ProviderConfirmation} from "../browser/payment-evidence.js";
import {validatePaymentVerificationReport} from "../verification/payment-verification-report.js";

export interface OriginalPaymentProof {tenant:string;orderId:number;orderReferenceId:string;amount:number;currency:string;adapterMode:string;confirmation:ProviderConfirmation}
export async function reconcilePaymentCheckpoint(
  checkpoint:MatrixCheckpoint,
  provenance:{candidate:string;deployment:string;settings:string},
  load:(entry:MatrixCheckpoint["cases"][number])=>Promise<{ledger:PaymentCaseLedger;proof:OriginalPaymentProof}>,
  verify:(request:VerificationRequest)=>Promise<VerificationResult>
):Promise<{checkpoint:MatrixCheckpoint;reports:Array<{key:string;result:VerificationResult}>}>{
  if(!checkpoint.provenance || Object.entries(provenance).some(([key,value])=>!value||value==="UNKNOWN"||checkpoint.provenance![key as keyof typeof provenance]!==value)) throw new Error("Candidate/deployment/settings identity changed or is unknown; read-only recovery cannot promote this receipt.");
  const keys=checkpoint.plannedKeys;
  if(checkpoint.schemaVersion!==1||!keys?.length||new Set(keys).size!==keys.length||!Array.isArray(checkpoint.cases)||new Set(checkpoint.cases.map(item=>item.key)).size!==checkpoint.cases.length) throw new Error("Malformed checkpoint plan/case inventory.");
  const copy=structuredClone(checkpoint);
  // Audit every case before issuing even a verification request.
  const pending:Array<{entry:MatrixCheckpoint["cases"][number];request:VerificationRequest}>=[];
  for(const entry of copy.cases){
    if(!keys.includes(entry.key)) throw new Error("Checkpoint case is not part of its original plan.");
    if(entry.state==="verified-restored"){assertResumeSafe({...copy,cases:[entry]},copy.binding,keys);continue;}
    if(entry.state!=="verification-pending"||!entry.request||!entry.ledgerPath||!entry.row) throw new Error("Unresolved submission or incomplete anchors require manual read-only investigation; no automatic recovery.");
    const {ledger,proof}=await load(entry);const request=entry.request;const row=entry.row;
    if(!verificationOnlyRecoveryEligible(ledger)||request.runtimeTarget!=="azure-dev"||request.runtime!=="azure"||request.environment!=="dev"||request.sqlAuthenticationMode!=="entra"
      ||request.tenantCode!==row.tenantCode||request.customerOrderId!==row.customerOrderId||request.orderReferenceId!==row.orderReferenceId
      ||ledger.tenantCode!==row.tenantCode||ledger.provider!==row.paymentProvider||ledger.anchors?.customerOrderId!==row.customerOrderId
      ||ledger.runtimeTarget!==request.runtimeTarget||ledger.runPrefix!==request.runPrefix||request.startedUtc!==ledger.startedUtc
      ||!Number.isFinite(Date.parse(request.finishedUtc??""))||Date.parse(request.finishedUtc!)<Date.parse(ledger.startedUtc)
      ||!Number.isFinite(Date.parse(ledger.finishedUtc??""))||Date.parse(request.finishedUtc!)>Date.parse(ledger.finishedUtc!)
      ||ledger.anchors?.orderReferenceId!==row.orderReferenceId||ledger.anchors?.providerPaymentId!==request.providerPaymentId
      ||proof.tenant!==row.tenantCode||proof.orderId!==row.orderId||proof.orderReferenceId!==row.orderReferenceId||proof.adapterMode!=="sandbox"
      ||proof.amount!==row.orderAmount||proof.currency!==row.orderCurrencyCode||proof.confirmation.paymentId!==request.providerPaymentId
      ||`${row.tenantCode.toLowerCase()}|${row.paymentProvider.toLowerCase()}`!==entry.key) throw new Error("Case ledger/provider proof/request anchors disagree; recovery refused.");
    assertSandboxConfirmation(proof.confirmation,{amount:row.orderAmount,currency:row.orderCurrencyCode});
    pending.push({entry,request});
  }
  const reports:Array<{key:string;result:VerificationResult}>=[];
  for(const {entry,request} of pending){
    let result=await verify(request);
    if(result.outcome==="passed"&&validatePaymentVerificationReport(result.rawReport,request).length) result={...result,outcome:"failed",summary:"Verifier returned incomplete or contradictory evidence; recovery not promoted."};
    reports.push({key:entry.key,result});
    if(result.outcome==="passed"){
      entry.state="verified-restored";entry.row!.verificationOutcome="passed";
      entry.row!.executionEvidence="read-only-reconciled";
      entry.row!.evidenceReference="Original confirmed payment; verification recovered read-only. No resubmission.";
    }
  }
  return {checkpoint:copy,reports};
}
