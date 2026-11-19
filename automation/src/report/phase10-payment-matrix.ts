import type { EvidenceStatus } from "./phase10-report.js";

export type PaymentMatrixKind = "deterministic" | "sandbox-positive" | "sandbox-negative";

export interface PaymentMatrixCase {
  tenant: string;
  provider: string;
  outcome: string;
  status: EvidenceStatus;
  mode: "deterministic" | "sandbox" | "UNKNOWN";
  threeDs: "enabled" | "disabled" | "UNKNOWN";
  challenge: "presented" | "not-presented" | "unknown";
  verification: "PASS" | "FAIL" | "BLOCKED";
  cleanup: "PASS" | "FAIL" | "BLOCKED";
  orderId: number | null;
  reference: string | null;
  amount: string | null;
  currency: string | null;
}

export interface PaymentMatrixReport {
  kind: PaymentMatrixKind;
  status: EvidenceStatus;
  expected: number | null;
  observed: number;
  summarySha256: string | null;
  seedContractSha256: string | null;
  cases: PaymentMatrixCase[];
  issues: string[];
}

type JsonRecord = Record<string, unknown>;

function asRecord(value: unknown): JsonRecord | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord : undefined;
}

function safeLabel(value: unknown, pattern: RegExp): string | null {
  return typeof value === "string" && pattern.test(value) ? value : null;
}

function sha256(value: unknown): string | null {
  return typeof value === "string" && /^[a-f0-9]{64}$/i.test(value) ? value.toLowerCase() : null;
}

function boolWord(value: unknown): PaymentMatrixCase["threeDs"] {
  return value === true || value === "enabled" ? "enabled"
    : value === false || value === "disabled" ? "disabled" : "UNKNOWN";
}

function normalizeCase(kind: PaymentMatrixKind, row: JsonRecord, mode: unknown): PaymentMatrixCase | null {
  const tenant = safeLabel(row.tenantCode, /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/);
  const provider = safeLabel(row.paymentProvider, /^[A-Za-z][A-Za-z0-9_-]{1,39}$/);
  if (!tenant || !provider) return null;
  const journey = safeLabel(row.journeyOutcome, /^[a-z][a-z-]{1,39}$/) ?? "unknown";
  const verification = row.verificationOutcome === "passed" ? "PASS"
    : row.verificationOutcome === "failed" ? "FAIL" : "BLOCKED";
  const cleanup = row.cleanupOutcome === "reset" || row.cleanupOutcome === "restored" ? "PASS"
    : row.cleanupOutcome === "failed" ? "FAIL" : "BLOCKED";
  const normalizedMode = mode === "deterministic" || mode === "sandbox" ? mode : "UNKNOWN";
  const expectedJourney = kind === "sandbox-negative"
    ? journey === "expected-failure" || journey === "expected-cancelled"
    : journey === "completed";
  const orderId = Number.isSafeInteger(row.orderId) && Number(row.orderId) > 0 ? Number(row.orderId) : null;
  const reference = typeof row.orderReferenceId === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(row.orderReferenceId)
    ? row.orderReferenceId : null;
  const amountValue = typeof row.orderAmount === "number" ? row.orderAmount
    : typeof row.orderAmount === "string" && /^\d+(?:\.\d{1,4})?$/.test(row.orderAmount) ? Number(row.orderAmount) : NaN;
  const amount = Number.isFinite(amountValue) && amountValue > 0 ? amountValue.toFixed(2) : null;
  const currency = safeLabel(row.orderCurrencyCode, /^[A-Z]{3}$/);
  const providerVerification = typeof row.providerVerification === "string" && (
    (kind === "deterministic" && row.providerVerification === "deterministic:completed") ||
    (kind === "sandbox-negative" && journey === "expected-failure" && row.providerVerification === "sandbox:failed") ||
    (kind === "sandbox-negative" && journey === "expected-cancelled" && row.providerVerification === "checkout-dismissed:order-unpaid") ||
    (kind === "sandbox-positive" && /^sandbox:(?:completed|captured|paid)$/i.test(row.providerVerification))
  );
  const complete = row.executionEvidence === "fresh" && normalizedMode !== "UNKNOWN" &&
    normalizedMode === (kind === "deterministic" ? "deterministic" : "sandbox") &&
    expectedJourney && verification === "PASS" && cleanup === "PASS" && orderId !== null &&
    reference !== null && amount !== null && currency !== null && providerVerification;
  const failed = journey === "failed" || verification === "FAIL" || cleanup === "FAIL";
  return {
    tenant,
    provider,
    outcome: journey,
    status: failed ? "FAIL" : complete ? "PASS" : "BLOCKED",
    mode: normalizedMode,
    threeDs: boolWord(row.threeDsSetting),
    challenge: row.observedChallenge === "presented" ? "presented"
      : row.observedChallenge === "not-presented" ? "not-presented" : "unknown",
    verification,
    cleanup,
    orderId,
    reference,
    amount,
    currency
  };
}

export function normalizePaymentMatrix(kind: PaymentMatrixKind, summaryInput: unknown, seedInput: unknown,
  summaryDigest?: string, seedDigest?: string): PaymentMatrixReport {
  const issues: string[] = [];
  const summary = asRecord(summaryInput);
  const seed = asRecord(seedInput);
  const expectedMode = kind === "deterministic" ? "deterministic" : "sandbox";
  if (!summary || summary.mode !== expectedMode || typeof summary.negative !== "boolean" ||
      summary.negative !== (kind === "sandbox-negative")) issues.push("Payment matrix summary is missing or has a contradictory mode.");
  if (summary && summary.status !== "passed" && summary.status !== "failed" && summary.status !== "partial") {
    issues.push("Payment matrix runner status is missing or invalid.");
  }
  if (!seed || seed.status !== "passed" || !Array.isArray(seed.tenants) || !Array.isArray(seed.supportedProviders)) {
    issues.push("Payment matrix seed contract is missing, malformed or unsuccessful.");
  }
  const tenants = (Array.isArray(seed?.tenants) ? seed.tenants : [])
    .map(asRecord).filter((tenant): tenant is JsonRecord => tenant?.status === "Active");
  const supportedProviders = (Array.isArray(seed?.supportedProviders) ? seed.supportedProviders : [])
    .filter((item): item is string => typeof item === "string" && /^[A-Za-z][A-Za-z0-9_-]{1,39}$/.test(item));
  const tenantCodes = tenants.map(tenant => safeLabel(tenant.tenant, /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/));
  if (tenants.length === 0 || tenantCodes.some(code => !code) || new Set(tenantCodes).size !== tenantCodes.length) {
    issues.push("Active tenant inventory is empty, malformed or duplicated.");
  }
  if (!Number.isSafeInteger(seed?.activeTenantCount) || seed?.activeTenantCount !== tenants.length) {
    issues.push("Declared active tenant count does not match the active tenant inventory.");
  }
  if (supportedProviders.length === 0 || new Set(supportedProviders).size !== supportedProviders.length ||
      tenants.some(tenant => !Array.isArray(tenant.providers) || supportedProviders.some(provider =>
        (tenant.providers as unknown[]).map(asRecord).filter(item => item?.provider === provider).length !== 1))) {
    issues.push("Supported provider inventory is empty, malformed, duplicated or incomplete for an active tenant.");
  }

  const configuredThreeDs = (tenantCode: string, provider: string): boolean | null => {
    const tenant = tenants.find(item => item.tenant === tenantCode);
    const providerRecord = Array.isArray(tenant?.providers)
      ? (tenant.providers as unknown[]).map(asRecord).find(item => item?.provider === provider) : undefined;
    return typeof providerRecord?.threeDs === "boolean" ? providerRecord.threeDs : null;
  };
  const expectations = kind === "sandbox-negative"
    ? tenantCodes.filter((code): code is string => code !== null).flatMap(tenant => ["expected-failure", "expected-cancelled"].map(outcome => ({ tenant, provider: "Razorpay", outcome, threeDs: configuredThreeDs(tenant, "Razorpay") })))
    : tenantCodes.filter((code): code is string => code !== null).flatMap(tenant => supportedProviders.map(provider => ({ tenant, provider, outcome: "completed", threeDs: configuredThreeDs(tenant, provider) })));
  const rows: PaymentMatrixCase[] = [];
  const observedRunIds = new Set<string>();
  for (const entry of Array.isArray(summary?.results) ? summary.results : []) {
    const result = asRecord(entry);
    if (!result) { issues.push("Payment matrix contains a malformed result record."); continue; }
    if (result.rows === undefined || (Array.isArray(result.rows) && result.rows.length === 0)) continue;
    if (!Array.isArray(result.rows) || result.rows.length !== 1) { issues.push("Payment result must contain exactly one case row."); continue; }
    const row = asRecord(result.rows[0]);
    const normalized = row && normalizeCase(kind, row, row.adapterMode);
    if (!normalized) { issues.push("Payment matrix contains a malformed or unsafe case identity."); continue; }
    const validRunId = (value: unknown): value is string => typeof value === "string" &&
      /^payment-automation-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z$/.test(value);
    if (!validRunId(result.runId) || !validRunId(row.runId) || result.runId !== row.runId || observedRunIds.has(result.runId)) {
      issues.push("Payment case run identity is missing, contradictory or reused.");
    } else observedRunIds.add(result.runId);
    if (kind === "sandbox-negative" && normalized.provider !== "Razorpay") {
      issues.push("Negative sandbox coverage contains a provider outside its approved case scope.");
    }
    rows.push(normalized);
  }
  const byKey = new Map<string, PaymentMatrixCase[]>();
  for (const row of rows) {
    const key = `${row.tenant}\0${row.provider}\0${kind === "sandbox-negative" ? row.outcome : ""}`;
    byKey.set(key, [...(byKey.get(key) ?? []), row]);
    if (!expectations.some(expected => expected.tenant === row.tenant && expected.provider === row.provider &&
        (kind !== "sandbox-negative" || expected.outcome === row.outcome))) {
      issues.push("Payment matrix contains a case outside the seed-derived expected inventory.");
    }
  }
  const cases: PaymentMatrixCase[] = expectations.map(expected => {
    const key = `${expected.tenant}\0${expected.provider}\0${kind === "sandbox-negative" ? expected.outcome : ""}`;
    const matches = byKey.get(key) ?? [];
    if (matches.length > 1) {
      issues.push("Payment matrix contains duplicate case identities.");
      return { tenant: expected.tenant, provider: expected.provider, outcome: expected.outcome, status: "BLOCKED",
        mode: expectedMode, threeDs: "UNKNOWN", challenge: "unknown", verification: "BLOCKED", cleanup: "BLOCKED",
        orderId: null, reference: null, amount: null, currency: null };
    }
    const match = matches[0];
    if (!match) return { tenant: expected.tenant, provider: expected.provider, outcome: expected.outcome, status: "NOT-RUN",
      mode: expectedMode, threeDs: "UNKNOWN", challenge: "unknown", verification: "BLOCKED", cleanup: "BLOCKED",
      orderId: null, reference: null, amount: null, currency: null };
    if (expected.threeDs === null || match.threeDs !== boolWord(expected.threeDs)) {
      issues.push("Observed payment 3DS setting does not match the seed-contract provider setting.");
      return { ...match, outcome: expected.outcome, status: "BLOCKED" };
    }
    return { ...match, outcome: expected.outcome };
  });
  const expected = issues.length === 0 ? expectations.length : null;
  const summaryCount = summary?.caseCount;
  if (summaryCount !== expectations.length || summary?.expectedCaseCount !== expectations.length || summary?.coveragePassed !== true ||
      summary?.primaryPassed !== true ||
      (summary?.status !== "passed" && summary?.status !== "failed") || !Array.isArray(summary?.skippedTenants) || summary.skippedTenants.length > 0) {
    issues.push("Payment summary does not prove a successful primary result and complete seed-derived matrix coverage.");
  }
  if (rows.length !== expectations.length) issues.push("Observed payment case count does not match the seed-derived expected matrix.");
  const hasObservedFailure = cases.some(item => item.status === "FAIL") || summary?.status === "failed";
  const status: EvidenceStatus = hasObservedFailure && issues.length === 0 ? "FAIL"
    : issues.length > 0 ? "BLOCKED"
      : cases.every(item => item.status === "PASS") ? "PASS" : cases.some(item => item.status === "NOT-RUN") ? "NOT-RUN" : "BLOCKED";
  const summarySha256 = sha256(summaryDigest);
  const seedContractSha256 = sha256(seedDigest);
  if (!summarySha256 || !seedContractSha256) issues.push("Payment evidence file digests are missing or invalid.");
  return { kind, status: issues.length ? "BLOCKED" : status, expected, observed: rows.length,
    summarySha256, seedContractSha256, cases, issues };
}
