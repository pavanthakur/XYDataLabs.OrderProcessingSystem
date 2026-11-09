import assert from "node:assert/strict";
import {test} from "node:test";
import {chromium} from "playwright";
import {OpenPaySandboxChallengeHandler} from "./openpay-sandbox-challenge-handler.js";
import {assertSandboxConfirmation} from "./payment-evidence.js";
import {safePaymentDiagnostic} from "../support/payment-diagnostics.js";

test("controlled challenge navigation/rejection/timeout never prove provider success",async()=>{
  const browser=await chromium.launch({headless:true});
  try{
    for(const outcome of ["submitted","rejected","cancelled","timeout"]){
      const page=await browser.newPage();
      await page.route("http://challenge.fixture/**",async route=>{
        if(new URL(route.request().url()).pathname!=="/start") return route.fulfill({contentType:"text/html",body:`<p>${outcome}</p>`});
        const body=outcome==="timeout"?"<p>Waiting for bank</p>":`<form name="form3DSecure" action="/${outcome}"><input name="codevalidation" type="password"/><button type="submit">Verify</button></form>`;
        await route.fulfill({contentType:"text/html",body});
      });
      await page.goto("http://challenge.fixture/start");
      const result=await new OpenPaySandboxChallengeHandler().execute(page,{tenantCode:"FixtureTenant",sandboxOtpCode:"fixture-code",challengeTimeoutMs:50,submissionTimeoutMs:100});
      assert.notEqual(result,"passed",`${outcome} must not count as verified authentication`);
      assert.equal(result,outcome==="timeout"?"partial":"submitted");
      assert.throws(()=>assertSandboxConfirmation(undefined));
      await page.close();
    }
  }finally{await browser.close();}
});
test("payment diagnostics strip checkout session query strings",()=>{
  const output=safePaymentDiagnostic("frame:https://api.razorpay.com/v1/checkout/public?session_token=private-fixture&key=fixture");
  assert.equal(output,"frame:https://api.razorpay.com/v1/checkout/public");
  assert.ok(!output.includes("private-fixture"));
});
