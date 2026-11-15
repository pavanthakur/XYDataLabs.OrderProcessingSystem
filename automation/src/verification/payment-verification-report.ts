import type { VerificationRequest } from "../contracts/verification-adapter.js";

/** Historical reports may still be rendered, but cannot satisfy a current execution gate. */
export function validatePaymentVerificationReport(value: unknown, request: VerificationRequest): string[] {
  const findings: string[] = [];
  if (!value || typeof value !== "object" || Array.isArray(value)) return ["Verification report is not an object."];
  const report = value as Record<string, unknown>;
  if (report.SchemaVersion !== 1 || report.EvidenceKind !== "payment-correlation") findings.push("Verification schema/kind is missing or unsupported.");
  if (report.Runtime !== request.runtime || report.Environment !== request.environment) findings.push("Verification environment/runtime does not match the requested case.");
  const anchor=request.runtime==="azure"?request.runPrefix:request.customerOrderId?.trim()||request.runPrefix;
  if(report.RunPrefix!==anchor) findings.push("Verification run/order anchor differs from the requested case.");
  const generated=typeof report.GeneratedUtc==="string"?Date.parse(report.GeneratedUtc):NaN;
  if(!Number.isFinite(generated)||generated>Date.now()+300000||(request.startedUtc&&generated<Date.parse(request.startedUtc))) findings.push("Verification generation time is missing, stale or invalid.");
  if(!request.customerOrderId||!request.orderReferenceId) findings.push("Positive verification requires exact persisted order/reference anchors.");
  const correlation=report.ChargeCorrelation;
  if(!Array.isArray(correlation)||!correlation.length||correlation.some(item=>!item||typeof item!=="object"
    ||item.Tenant!==request.tenantCode||item.CustomerOrderId!==request.customerOrderId||item.InDb!==true||item.DbStatus!=="completed")) findings.push("Charge correlation is missing, pending, cross-tenant or belongs to another order.");
  if(Array.isArray(correlation)&&correlation.length){
    if(correlation.some(item=>item?.UiCallbackExpected!==true)) findings.push("Positive callback requirement was waived or omitted.");
    if(correlation.some(item=>item?.UiCallbackLogged!==true)) findings.push("Required UI callback proof is missing.");
  }
  const checks = report.Checks;
  if (!checks || typeof checks !== "object" || Array.isArray(checks) || Object.keys(checks).length === 0) return [...findings, "Required checks are absent or empty."];
  const required = ["Q8 bleed", "Q9 bleed", "API log -> DB charge IDs", "UI telemetry -> callbacks present where expected"];
  if (!request.tenantCode) findings.push("Positive verification requires an explicit tenant.");
  else required.push(...["Pre-flight 3DS", "Q2 rows", "Q5 steps", "Successful charge", "Paid order"].map(name => `${name} [${request.tenantCode}]`));
  if (request.runtime === "azure") {
    required.push("App Insights query execution", "Provider payment IDs -> request/dependency correlation");
    if (!request.providerPaymentId) findings.push("Azure positive verification requires a provider payment identifier.");
  }
  for (const name of required) if (!Object.hasOwn(checks, name)) findings.push(`Missing required check: ${name}.`);
  for (const [name, check] of Object.entries(checks)) {
    if (!check || typeof check !== "object" || Array.isArray(check)
      || !Object.hasOwn(check, "Expected") || !Object.hasOwn(check, "Actual") || check.Outcome !== "PASS") {
      // Never interpolate report values: malformed external output may include sensitive data.
      findings.push(required.includes(name) ? `Required check did not pass: ${name}.` : "An additional verification check is malformed or did not pass.");
    }
  }
  return findings;
}

/** Only bounded telemetry/history gaps may be isolated from an otherwise proven payment. */
export function verificationSafetyEstablished(value:unknown,request:VerificationRequest):boolean{
  const findings=validatePaymentVerificationReport(value,request);
  const permitted=["App Insights query execution","Provider payment IDs -> request/dependency correlation","UI telemetry -> callbacks present where expected",`Q5 steps [${request.tenantCode}]`]
    .map(name=>`Required check did not pass: ${name}.`);
  return findings.every(item=>item==="Required UI callback proof is missing."||permitted.includes(item));
}
