import assert from "node:assert/strict";
import {test} from "node:test";
import {pollVerification} from "./verification-polling.js";
test("read-only polling waits for evidence rather than sleeping before every check",async()=>{
  let calls=0;
  const result=await pollVerification(async()=>({outcome:++calls===1?"failed":"passed",summary:"fixture"}),100,1);
  assert.equal(calls,2);assert.equal(result.outcome,"passed");
});
test("expired verification never converts missing evidence into PASS",async()=>{
  const result=await pollVerification(async()=>({outcome:"skipped",summary:"no evidence"}),5,1);
  assert.equal(result.outcome,"failed");
  await assert.rejects(()=>pollVerification(async()=>{throw new Error("unavailable");},5,1),/unavailable/);
});
