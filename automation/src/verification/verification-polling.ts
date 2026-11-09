import type {VerificationResult} from "../contracts/verification-adapter.js";

// Read-only verification retries, never payment submission retries.
export async function pollVerification(operation:(remainingMs:number)=>Promise<VerificationResult>,timeoutMs=120000,intervalMs=2000):Promise<VerificationResult>{
  const deadline=Date.now()+timeoutMs;
  let last:VerificationResult|undefined;let lastError:unknown;
  do{
    try {last=await operation(Math.max(1,deadline-Date.now())); if(last.outcome==="passed") return last;}
    catch(error){lastError=error;}
    if(Date.now()>=deadline) break;
    await new Promise(resolve=>setTimeout(resolve,Math.min(intervalMs,deadline-Date.now())));
  }while(Date.now()<deadline);
  if(last) return {...last,outcome:"failed",summary:`${last.summary} Verification deadline reached; incomplete evidence is not PASS.`};
  throw lastError instanceof Error?lastError:new Error("Verification deadline reached without evidence.");
}
