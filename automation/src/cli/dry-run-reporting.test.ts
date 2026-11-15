import test, {type TestContext} from "node:test";
import assert from "node:assert/strict";
import {mkdtemp,readFile,mkdir,writeFile,rm,unlink} from "node:fs/promises";
import {execFileSync} from "node:child_process";
import path from "node:path";
import {fileURLToPath} from "node:url";
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"../../..");
async function assertDryRun(t:TestContext,cli:string,target:string){
    const results=path.join(root,"TestResults");await mkdir(results,{recursive:true});
    const fixture=await mkdtemp(path.join(results,"dry-run-contract-"));
    const dryMarker=path.join(results,"Playwright/latest-playwright-dry-run.txt");
    const priorDry=await readFile(dryMarker,"utf8").catch(()=>null);
    t.after(async()=>{
      const current=await readFile(dryMarker,"utf8").catch(()=>null);
      if(current?.startsWith(fixture+path.sep)){
        if(priorDry===null)await unlink(dryMarker);else await writeFile(dryMarker,priorDry);
      }
      await rm(fixture,{recursive:true,force:true});
    });
    const matrix=path.join(fixture,"matrix");await mkdir(matrix);
    const live=path.join(matrix,"latest-playwright-matrix.txt");await writeFile(live,"accepted-live-fixture\n");
    const globalLive=path.join(results,"Playwright/latest-playwright-run.txt");
    const before=await readFile(globalLive,"utf8").catch(()=>null);
    const env:NodeJS.ProcessEnv={...process.env,PHASE10_RUN_ROOT:fixture};delete env.NODE_TEST_CONTEXT;
    execFileSync(process.execPath,[path.join(root,"automation/node_modules/tsx/dist/cli.mjs"),path.join(root,"automation/src/cli",cli),"--target",target,"--dry-run"],{cwd:root,env,stdio:"pipe",maxBuffer:2*1024*1024});
    assert.equal(await readFile(live,"utf8"),"accepted-live-fixture\n");
    assert.equal(await readFile(globalLive,"utf8").catch(()=>null),before);
    const reportRoot=(await readFile(path.join(matrix,"latest-playwright-matrix-dry-run.txt"),"utf8")).trim();
    const report=JSON.parse(await readFile(path.join(reportRoot,"summary.json"),"utf8"));
    assert.equal(report.status,"dry-run-complete");assert.equal(report.executionMode,"dry-run");
    assert.ok(report.targetRuns.flatMap((run:{rows:Array<{journeyOutcome:string}>})=>run.rows).every((row:{journeyOutcome:string})=>row.journeyOutcome==="dry_run"));
    assert.match(await readFile(path.join(reportRoot,"summary.md"),"utf8"),/DRY-RUN — NOT PAYMENT ACCEPTANCE EVIDENCE/);
}
test("local-http dry run is labelled and cannot replace live pointers",t=>assertDryRun(t,"run-local-matrix.ts","local-http"));
test("docker-dev-http dry run is labelled and cannot replace live pointers",t=>assertDryRun(t,"run-docker-matrix.ts","docker-dev-http"));
