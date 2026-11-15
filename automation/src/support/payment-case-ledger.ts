import type {ExecutiveSummaryRow} from "../contracts/report-composer.js";
import {randomUUID} from "node:crypto";
import {writeFile,rename} from "node:fs/promises";

export interface PaymentCaseProgress {
  stage: "order-persisted" | "submission-started" | "provider-confirmed";
  orderId?: number; customerOrderId?: string; orderReferenceId?: string; amount?: number; currency?: string;
  providerPaymentId?: string; providerOrderId?: string;
}
export interface PaymentCaseLedger {
  schemaVersion: 1; tenantCode: string; provider: string; runtimeTarget: string; runPrefix: string;
  startedUtc: string; finishedUtc?: string; mutation: "preparing" | PaymentCaseProgress["stage"];
  anchors?: Omit<PaymentCaseProgress,"stage">;
  journey: "pending" | "completed" | "blocked"; verification: "pending" | "passed" | "blocked";
  restoration: "pending" | "passed" | "blocked"; row?: ExecutiveSummaryRow;
}
export async function saveCaseLedger(file:string,ledger:PaymentCaseLedger):Promise<void>{
  const temporary=`${file}.${randomUUID()}.tmp`;
  await writeFile(temporary,JSON.stringify(ledger,null,2),{encoding:"utf8",flag:"wx"});
  await rename(temporary,file);
}
export function recordCaseProgress(ledger:PaymentCaseLedger,progress:PaymentCaseProgress):void{
  const rank={preparing:0,"order-persisted":1,"submission-started":2,"provider-confirmed":3};
  if(rank[progress.stage]!==rank[ledger.mutation]+1) throw new Error("Invalid payment evidence transition; do not resubmit.");
  if(progress.stage==="order-persisted" && (!Number.isInteger(progress.orderId)||progress.orderId!<=0||!progress.orderReferenceId||!progress.customerOrderId||!progress.currency||!(progress.amount!>0))) throw new Error("Persisted order anchors are incomplete.");
  if(progress.stage==="provider-confirmed" && !progress.providerPaymentId) throw new Error("Confirmed provider payment identifier is missing.");
  const {stage,...anchors}=progress;
  ledger.mutation=stage;ledger.anchors={...ledger.anchors,...anchors};
}
export function verificationOnlyRecoveryEligible(ledger:PaymentCaseLedger):boolean{
  return ledger.mutation==="provider-confirmed" && ledger.journey==="completed" && ledger.restoration==="passed"
    && Boolean(ledger.anchors?.providerPaymentId) && ledger.row?.adapterMode==="sandbox";
}
