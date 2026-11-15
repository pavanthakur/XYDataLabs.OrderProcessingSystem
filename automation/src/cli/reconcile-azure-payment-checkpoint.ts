import {realpath} from "node:fs/promises";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {randomUUID} from "node:crypto";
import {candidateIdentity,readCheckpoint,readBoundedEvidence,saveCheckpoint,writeAtomicEvidence} from "../support/azure-matrix-checkpoint.js";
import {reconcilePaymentCheckpoint,type OriginalPaymentProof} from "../support/reconcile-payment-checkpoint.js";
import type {PaymentCaseLedger} from "../support/payment-case-ledger.js";
import {PowerShellVerificationAdapter} from "../verification/powershell-verification-adapter.js";

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"../../..");
async function main(){
  const args=process.argv.slice(2);
  if(args.length!==2||args[0]!=="--checkpoint"||!args[1]) throw new Error("Use --checkpoint <existing local Azure-dev checkpoint.json>; no browser or charge path exists in this command.");
  if(!process.env.EXPECTED_AZURE_SUBSCRIPTION_ID) throw new Error("Explicit subscription selection is required; use the operator wrapper Reconcile mode.");
  const checkpoint=await readCheckpoint(args[1],path.join(root,"TestResults/Playwright"));
  const directory=path.dirname(await realpath(args[1]));
  const readEvidence=async(file:string)=>{
    return await readBoundedEvidence(path.resolve(directory,file),directory);
  };
  const adapter=new PowerShellVerificationAdapter();
  const output=await reconcilePaymentCheckpoint(checkpoint,{candidate:await candidateIdentity(root),deployment:process.env.XYDATALABS_AZURE_DEV_DEPLOYMENT_IDENTITY??"UNKNOWN",settings:process.env.XYDATALABS_AZURE_DEV_SETTINGS_IDENTITY??"UNKNOWN"},
    async entry=>({ledger:await readEvidence(entry.ledgerPath!) as PaymentCaseLedger,proof:await readEvidence(path.join(path.dirname(entry.ledgerPath!),"provider-confirmation.json")) as OriginalPaymentProof}),async request=>{
      try{return await adapter.execute(request);}catch{return {outcome:"failed",summary:"Read-only verification unavailable; raw diagnostics omitted. No charge retried."};}
    });
  const file=path.join(directory,`checkpoint-reconciled-${randomUUID()}.json`);
  await saveCheckpoint(file,output.checkpoint);
  // Separate versioned evidence sidecar; original matrix/ledger/checkpoint remain unchanged.
  const summaryFile=file.replace(/\.json$/,"-evidence.json");
  await writeAtomicEvidence(summaryFile,{schemaVersion:1,evidenceKind:"read-only-reconciliation",reports:output.reports.map(entry=>({key:entry.key,outcome:entry.result.outcome,scope:"Versioned mandatory checks re-evaluated; original provider/browser evidence retained separately. No new payment."}))});
  process.stdout.write(`Read-only reconciliation packet: ${file}\n`);
  if(output.checkpoint.cases.some(entry=>entry.state!=="verified-restored")) process.exitCode=1;
}
void main().catch(()=>{process.stderr.write("Read-only checkpoint reconciliation failed. Original evidence preserved; no browser or charge was started.\n");process.exitCode=1;});
