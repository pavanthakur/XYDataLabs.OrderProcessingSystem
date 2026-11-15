import test from "node:test";
import assert from "node:assert/strict";
import {baselinePaymentScenarios,paymentCurrency} from "./payment-scenarios.js";
import {FileReportComposer} from "../report/file-report-composer.js";
import type {ExecutiveSummaryRow} from "./report-composer.js";
test("baseline fixes provider/currency/UI entry consistently without naming tenants",()=>{
  assert.deepEqual(baselinePaymentScenarios.map(item=>[item.provider,item.currency,item.entryMode,item.threeDs]),[["Razorpay","INR","ui",false],["OpenPay","MXN","ui",false]]);
  for(const provider of baselinePaymentScenarios) assert.equal(paymentCurrency(provider.provider),provider.currency);
  assert.throws(()=>paymentCurrency("unknown"));
});
test("dry-run reports prominently reject payment-acceptance interpretation",async()=>{
  const report=await new FileReportComposer().compose([{journeyOutcome:"dry_run"} as ExecutiveSummaryRow]);
  assert.match(report,/DRY-RUN — NOT PAYMENT ACCEPTANCE EVIDENCE/);
});
