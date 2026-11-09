import {mkdir,readFile,writeFile} from "node:fs/promises";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {executePaymentAutomationRun} from "../orchestrator/payment-automation-executor.js";
import {ApiTenantExecutionCatalog} from "../catalog/api-tenant-execution-catalog.js";
import {JsonRuntimeTargetCatalog} from "../catalog/json-runtime-target-catalog.js";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {FileReportComposer} from "../report/file-report-composer.js";
import {requiredChallengeVerified} from "../browser/payment-evidence.js";
import {hasExactPaymentAcceptanceCoverage} from "./payment-acceptance-coverage.js";

// Deliberately local-only: no Azure provisioning, live payments or automatic reset.
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"../../..");
const mode=process.argv.includes("--deterministic") ? "deterministic" : "sandbox";
const negative=process.argv.includes("--negative");
const manualSmoke=process.argv.includes("--manual-smoke");
const acceptanceProfile=process.argv.includes("--acceptance-profile")?process.argv[process.argv.indexOf("--acceptance-profile")+1]:"baseline";
const onlyTenant=process.argv.includes("--tenant")?process.argv[process.argv.indexOf("--tenant")+1]:null;
const onlyProvider=process.argv.includes("--provider")?process.argv[process.argv.indexOf("--provider")+1]:null;
const onlyOutcome=process.argv.includes("--outcome")?process.argv[process.argv.indexOf("--outcome")+1]:null;
const reportRoot=path.resolve(process.env.PHASE10_PAYMENT_REPORT_ROOT ?? path.join(root,"TestResults","DockerStorage"));
if(!reportRoot.startsWith(path.join(root,"TestResults")+path.sep)) throw new Error("Payment reports must stay under project TestResults.");
const directory=path.join(reportRoot,`payment-acceptance-${mode}-${manualSmoke?"manual-":""}${negative?"negative-":""}${Date.now()}`);
await mkdir(directory,{recursive:true});
try {
  await promisify(execFile)("pwsh",["-NoProfile","-File",path.join(root,"scripts/test-phase10-local-seed-contract.ps1"),"-OutputPath",path.join(directory,"seed-contract.json")],{maxBuffer:2*1024*1024});
} catch { throw new Error("Read-only local seed/sandbox-key preflight failed. No payment fixture or charge was started; inspect the sanitized seed contract."); }
const target=await new JsonRuntimeTargetCatalog().resolve("docker-dev-http");
const plan=await new ApiTenantExecutionCatalog(target).resolve([],true);
const tenants=plan.resolvedTenants.map(item=>item.tenantCode);
if(plan.failures.length>0 || plan.skippedTenantCodes.length>0) throw new Error("Acceptance requires complete discovery of every active tenant; partial topology is not accepted.");
if(onlyTenant && !tenants.includes(onlyTenant)) throw new Error("Requested tenant is not in the discovered active topology.");
if(onlyOutcome && !["failure","cancelled"].includes(onlyOutcome)) throw new Error("Unknown negative outcome filter.");
if(!["baseline","extended"].includes(acceptanceProfile)) throw new Error("Acceptance profile must be baseline or extended.");
if(onlyProvider && !["Razorpay","OpenPay"].includes(onlyProvider)) throw new Error("Unknown provider filter.");
const localContract=JSON.parse(await readFile(path.join(root,"Resources/Configuration/tenant-bootstrap.local.json"),"utf8")) as {schemaVersion:number;scope:string;requiredBaselineTenants:string[]};
if(localContract.schemaVersion!==1 || localContract.scope!=="docker-dev") throw new Error("Local tenant bootstrap contract is invalid.");
for(const required of localContract.requiredBaselineTenants) if(!tenants.includes(required)) throw new Error(`Required baseline tenant ${required} missing from discovery.`);
const results:unknown[]=[];
const scenarios:Array<{provider:string;threeDs:boolean;challengeRequired:boolean;expectedOutcome?:"failure"|"cancelled"}>=negative
  ? [{provider:"Razorpay",threeDs:false,challengeRequired:false,expectedOutcome:"failure"},
     {provider:"Razorpay",threeDs:false,challengeRequired:false,expectedOutcome:"cancelled"}]
  : acceptanceProfile==="extended"
    ? [{provider:"Razorpay",threeDs:false,challengeRequired:mode==="sandbox"},
       {provider:"OpenPay",threeDs:true,challengeRequired:mode==="sandbox"},
       {provider:"OpenPay",threeDs:false,challengeRequired:false}]
    : [{provider:"Razorpay",threeDs:false,challengeRequired:false},
       {provider:"OpenPay",threeDs:false,challengeRequired:false}];
const selectedTenants=tenants.filter(tenant=>!onlyTenant || tenant===onlyTenant);
const cases=manualSmoke
  ? selectedTenants.flatMap(tenant=>["Razorpay","OpenPay"].map(provider=>({tenant,scenario:scenarios.find(item=>item.provider===provider)!})))
  : selectedTenants.flatMap(tenant=>scenarios.filter(scenario=>(!onlyOutcome || scenario.expectedOutcome===onlyOutcome) && (!onlyProvider || scenario.provider===onlyProvider)).map(scenario=>({tenant,scenario})));
if(manualSmoke && (negative || mode!=="deterministic")) throw new Error("Manual-equivalent smoke requires deterministic positive mode.");
for(const {tenant,scenario} of cases) {
    const startedUtc=new Date().toISOString();
    const result=await executePaymentAutomationRun({target:"docker-dev-http",tenantCodes:[tenant],allowPartialExecution:false,dryRun:false,
      headless:!process.argv.includes("--headed"),verify:true,sandboxOtpCode:process.env.OPENPAY_SANDBOX_OTP ?? "999",tenantTimeoutMs:420000,
      requestedProviders:[scenario.provider],expectedAdapterMode:mode,threeDs:scenario.threeDs,challengeRequired:scenario.challengeRequired,
      expectedOutcome:scenario.expectedOutcome,
      manualEntry:!negative,loginUsername:"tenant-admin",
      reportDirectoryRoot:directory,autoStartLocalSessions:false,logger:message=>process.stdout.write(`${message}\n`)});
    const logs=await promisify(execFile)("docker",["logs","xy-phase10-payments-1","--since",startedUtc],{maxBuffer:8*1024*1024}).catch(()=>({stdout:"",stderr:""}));
    const providerDependencies=(logs.stdout+logs.stderr).split(/\r?\n/).filter(line=>line.includes("PaymentProviderEvidence"));
    await writeFile(path.join(result.reportDirectory,"provider-dependencies.json"),JSON.stringify({mode,evidence:providerDependencies},null,2));
    if(mode==="sandbox" && result.rows.some(row=>row.journeyOutcome==="completed") &&
      (!providerDependencies.some(line=>line.includes("Simulation=False") && line.includes("Operation=create-charge")) ||
       !providerDependencies.some(line=>line.includes("Simulation=False") && line.includes("Operation=fetch-charge")))) {
      for(const row of result.rows) row.verificationOutcome="failed: server provider dependency evidence missing";
    }
    results.push(result);
    if(mode==="sandbox") for(const row of result.rows.filter(row=>row.journeyOutcome==="completed")) {
      try {
        const proof=JSON.parse(await readFile(path.join(result.reportDirectory,row.tenantCode,row.paymentProvider.toLowerCase(),"provider-confirmation.json"),"utf8"));
        const paymentId=proof.confirmation?.paymentId;
        const createdId=row.paymentProvider==="Razorpay" ? proof.confirmation?.providerOrderId : paymentId;
        const matching=(operation:string,id:string)=>Boolean(id)&&providerDependencies.some(line=>line.includes(`Provider=${row.paymentProvider}`)&&line.includes("Simulation=False")&&line.includes(`Operation=${operation}`)&&line.includes(`ProviderPaymentId=${id}`));
        if(!matching("create-charge",createdId)||!matching("fetch-charge",paymentId)) row.verificationOutcome="failed: dependency IDs do not correlate with this order's provider confirmation";
      } catch { row.verificationOutcome="failed: correlated provider confirmation evidence missing"; }
    }
    if(scenario.expectedOutcome) {
      for(const row of result.rows.filter(row=>row.journeyOutcome.startsWith("expected-"))) {
        try {
          const evidence=await promisify(execFile)("pwsh",["-NoProfile","-File",path.join(root,"scripts/verify-local-payment-state.ps1"),
            "-TenantCode",tenant,"-OrderId",String(row.orderId),"-ExpectedOutcome",scenario.expectedOutcome]);
          await writeFile(path.join(result.reportDirectory,"negative-sql-proof.json"),evidence.stdout);
        }catch{row.verificationOutcome="failed: negative SQL state not proven";}
      }
    }
    else {
      for(const row of result.rows.filter(row=>row.journeyOutcome==="completed")) {
        try {
          const evidence=await promisify(execFile)("pwsh",["-NoProfile","-File",path.join(root,"scripts/verify-local-payment-state.ps1"),
            "-TenantCode",tenant,"-OrderId",String(row.orderId),"-ExpectedOutcome","success","-ExpectedAmount",String(row.orderAmount),
            "-ExpectedCurrency",row.orderCurrencyCode,"-ExpectedReference",row.orderReferenceId]);
          await writeFile(path.join(result.reportDirectory,"positive-sql-proof.json"),evidence.stdout);
        }catch{row.verificationOutcome="failed: Paid order and unique successful transaction not physically proven";}
      }
    }
    for(const row of result.rows) {
      if(row.journeyOutcome==="completed" && row.verificationOutcome==="passed" && !requiredChallengeVerified(scenario.challengeRequired,row.observedChallenge,row.challengeOutcome)) row.verificationOutcome="blocked: required visible provider challenge was not verified; payment confirmation alone is insufficient";
    }
    // Preserve original journey reports; these derived reports include the later dependency/SQL gates.
    await writeFile(path.join(result.reportDirectory,"acceptance-validated-rows.json"),JSON.stringify(result.rows,null,2));
    await writeFile(path.join(result.reportDirectory,"acceptance-executive-summary.md"),await new FileReportComposer().compose(result.rows));
    await writeFile(path.join(directory,"summary.json"),JSON.stringify({mode,status:"running",results},null,2));
    if(result.rows.some(row=>row.cleanupOutcome!=="reset")) throw new Error("Settings restoration failed; stop and recover from the manifest before continuing.");
}
for(const tenant of selectedTenants){
  if(!negative && mode==="sandbox") results.push({tenant,provider:"Razorpay",threeDs:true,status:"blocked",reason:"S2S merchant entitlement has not been confirmed; no direct card submission attempted."});
  else if(negative && mode==="sandbox") results.push({tenant,provider:"OpenPay",status:"blocked",reason:"Real negative challenge fixtures require provider-documented rejection/cancellation behaviour; no OTP or card behaviour is invented."});
}
const runs=results.filter((item:any)=>Array.isArray(item.rows)) as Array<{rows:Array<{tenantCode:string;paymentProvider:string;journeyOutcome:string;verificationOutcome:string}>}>;
const primaryPassed=runs.length>0 && runs.every(run=>run.rows.length>0 && run.rows.every(row=>(negative?row.journeyOutcome.startsWith("expected-"):row.journeyOutcome==="completed") && row.verificationOutcome==="passed"));
const hasFailure=runs.some(run=>run.rows.some(row=>row.journeyOutcome.startsWith("failed") || row.verificationOutcome.startsWith("failed")));
const expectedKeys=cases.map(({tenant,scenario})=>`${tenant}|${scenario.provider}|${scenario.expectedOutcome??"positive"}`);
const actualKeys=runs.flatMap(run=>run.rows.map(row=>`${row.tenantCode}|${row.paymentProvider}|${negative?(row.journeyOutcome==="expected-cancelled"?"cancelled":"failure"):"positive"}`));
const expectedCaseCount=cases.length;
const coveragePassed=runs.length===expectedCaseCount&&runs.every(run=>run.rows.length===1)&&hasExactPaymentAcceptanceCoverage(expectedKeys,actualKeys);
const requiredPassed=primaryPassed&&coveragePassed;
const summary={mode,acceptanceProfile,negative,manualSmoke,caseCount:runs.length,expectedCaseCount,coveragePassed,status:requiredPassed ? "passed" : hasFailure?"failed":"partial",primaryPassed:requiredPassed,
  capabilityAcceptance:mode==="deterministic"?"not-applicable":"blocked",negativeSandboxAcceptance:mode==="deterministic"?"not-applicable":negative?(primaryPassed?"razorpay-passed-openpay-blocked":"failed"):"separate-suite",skippedTenants:plan.skippedTenantCodes,results};
await writeFile(path.join(directory,"summary.json"),JSON.stringify(summary,null,2));
process.stdout.write(`Acceptance evidence: ${directory}\n`);
// Capability/negative gaps never collapse to an overall PASS.
process.exitCode=requiredPassed?0:1;
