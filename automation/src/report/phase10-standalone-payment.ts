import { createHash } from "node:crypto";
import { lstat, readFile } from "node:fs/promises";
import { basename, join } from "node:path";
import { normalizePaymentMatrix, type PaymentMatrixKind, type PaymentMatrixReport } from "./phase10-payment-matrix.js";
import { phase10ImageSetsMatch, validatePhase10ImageManifest, type Phase10ImageManifest } from "./phase10-images.js";
import { isDeepStrictEqual } from "node:util";

export interface StandalonePaymentEvidence {
  kind: PaymentMatrixKind;
  status: "PASS" | "FAIL" | "BLOCKED";
  report: PaymentMatrixReport;
  configurationMatched: boolean;
  seed?: unknown;
  restored?: unknown;
  before?: Phase10ImageManifest;
  after?: Phase10ImageManifest;
  runId: string;
}

type JsonRecord = Record<string, unknown>;
function record(value: unknown): JsonRecord | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : undefined;
}
function parse(bytes: Buffer | undefined): unknown {
  if (!bytes) return undefined;
  try { return JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, "")) as unknown; }
  catch (error) { if (error instanceof SyntaxError) return undefined; throw error; }
}

async function bounded(root: string, relativePath: string): Promise<Buffer | undefined> {
  if (!relativePath || relativePath.startsWith("/") || relativePath.includes("\\") ||
      relativePath.split("/").some(part => !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(part) || part === "." || part === "..")) return undefined;
  let cursor = root;
  for (const part of relativePath.split("/")) {
    cursor = join(cursor, part);
    try {
      const info = await lstat(cursor);
      if (info.isSymbolicLink() || (cursor === join(root, relativePath) ? !info.isFile() || info.size > 2 * 1024 * 1024 : !info.isDirectory())) return undefined;
    } catch (error) {
      if (error instanceof Error && "code" in error && error.code === "ENOENT") return undefined;
      throw error;
    }
  }
  return readFile(cursor);
}

/** Verifies the standalone wrapper seal, matrix identities, provider artifacts, settings restoration and clean image provenance. */
export async function verifyStandalonePaymentEvidence(root: string, expectedKind: PaymentMatrixKind,
  expectedCommit: string): Promise<StandalonePaymentEvidence | undefined> {
  let rootInfo: import("node:fs").Stats;
  try { rootInfo = await lstat(root); }
  catch (error) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") return undefined;
    throw error;
  }
  if (!rootInfo.isDirectory() || rootInfo.isSymbolicLink()) return undefined;
  const runId = basename(root);
  const sealBytes = await bounded(root, "payment-evidence-seal.json");
  const seal = record(parse(sealBytes));
  const hashes = record(seal?.sha256);
  if (!seal || seal.schema !== "phase10-payment-evidence-v1" || seal.runId !== runId || !hashes ||
      Object.keys(hashes).length < 5 || Object.keys(hashes).length > 1000) return undefined;
  const loaded = new Map<string, Buffer>();
  let totalBytes = 0;
  for (const [name, digest] of Object.entries(hashes)) {
    if (typeof digest !== "string" || !/^[a-f0-9]{64}$/.test(digest)) return undefined;
    const bytes = await bounded(root, name);
    if (!bytes || createHash("sha256").update(bytes).digest("hex") !== digest) return undefined;
    totalBytes += bytes.length;
    if (totalBytes > 64 * 1024 * 1024) return undefined;
    loaded.set(name, bytes);
  }
  const required = ["payment-run.json", "seed-contract.json", "restoration-contract.json",
    "docker-image-identities-before.json", "docker-image-identities-after.json"];
  if (required.some(name => !loaded.has(name))) return undefined;
  const paymentRun = record(parse(loaded.get("payment-run.json")));
  const finalizedRestoration = paymentRun?.schema === "phase10-sealed-payment-run-v2";
  if (!(finalizedRestoration || paymentRun?.schema === "phase10-sealed-payment-run-v1") ||
      paymentRun?.runId !== runId || paymentRun.matrix !== expectedKind || !Number.isInteger(paymentRun.rawExitCode) ||
      !((paymentRun.status === "passed" && paymentRun.rawExitCode === 0 && (!finalizedRestoration || paymentRun.restorationVerified === true)) ||
        (paymentRun.status === "failed" && (paymentRun.rawExitCode !== 0 || (finalizedRestoration && paymentRun.restorationVerified === false))))) return undefined;
  if (paymentRun.status === "failed") {
    const seed = parse(loaded.get("seed-contract.json"));
    return { kind: expectedKind, status: "FAIL", report: normalizePaymentMatrix(expectedKind, undefined, seed),
      configurationMatched: false, runId };
  }
  const summaryPaths = [...loaded.keys()].filter(name => /^payments\/[A-Za-z0-9._-]+\/summary\.json$/.test(name));
  if (summaryPaths.length !== 1) return undefined;
  const summaryBytes = loaded.get(summaryPaths[0])!;
  const summary = parse(summaryBytes);
  const seedBytes = loaded.get("seed-contract.json")!;
  const seed = parse(seedBytes);
  const normalized = normalizePaymentMatrix(expectedKind, summary, seed,
    createHash("sha256").update(summaryBytes).digest("hex"), createHash("sha256").update(seedBytes).digest("hex"));
  if (normalized.status !== "PASS") return undefined;

  // Require the case-level evidence that supports each matrix row, not just a green summary.
  const matrixRoot = summaryPaths[0].slice(0, summaryPaths[0].lastIndexOf("/"));
  const groups = record(summary)?.results;
  if (!Array.isArray(groups)) return undefined;
  for (const groupValue of groups) {
    const group = record(groupValue);
    if (group?.rows === undefined && group?.status === "blocked" &&
        (expectedKind === "sandbox-positive" && group.provider === "Razorpay" && group.threeDs === true ||
         expectedKind === "sandbox-negative" && group.provider === "OpenPay")) continue;
    const rows = Array.isArray(group?.rows) ? group.rows.map(record).filter((item): item is JsonRecord => !!item) : [];
    if (rows.length !== 1) return undefined;
    const row = rows[0];
    const tenant = String(row.tenantCode ?? "");
    const provider = String(row.paymentProvider ?? "").toLowerCase();
    const caseRunId = String(row.runId ?? "");
    const caseBase = [...loaded.keys()].find(name => name.startsWith(`${matrixRoot}/`) &&
      name.endsWith(`/${caseRunId}/${tenant}/${provider}/case-ledger.json`));
    if (!caseBase || !caseRunId || basename(caseRunId) !== caseRunId) return undefined;
    const caseDirectory = caseBase.slice(0, -"case-ledger.json".length - 1);
    const tenantDirectory = caseDirectory.slice(0, caseDirectory.lastIndexOf("/"));
    const reportDirectory = tenantDirectory.slice(0, tenantDirectory.lastIndexOf("/"));
    if (basename(reportDirectory) !== caseRunId) return undefined;
    const reportSummary = record(parse(loaded.get(`${reportDirectory}/summary.json`)));
    const validatedRowsValue = parse(loaded.get(`${reportDirectory}/acceptance-validated-rows.json`));
    const validatedRows = Array.isArray(validatedRowsValue) ? validatedRowsValue.map(record).filter((item): item is JsonRecord => !!item) : [];
    const ledger = record(parse(loaded.get(caseBase)));
    const anchors = record(ledger?.anchors);
    const ledgerRow = record(ledger?.row);
    const success = row.journeyOutcome === "completed";
    const sqlName = success ? "positive-sql-proof.json" : "negative-sql-proof.json";
    const sqlPath = `${reportDirectory}/${sqlName}`;
    const sql = record(parse(loaded.get(sqlPath)));
    if (!reportSummary || reportSummary.runId !== caseRunId || group?.runId !== caseRunId || !validatedRows.some(item => item.runId === caseRunId &&
        item.tenantCode === tenant && item.paymentProvider === row.paymentProvider && item.orderId === row.orderId &&
        item.orderReferenceId === row.orderReferenceId && item.journeyOutcome === row.journeyOutcome) ||
        !ledger || !anchors || !ledgerRow || !sql || ledger.schemaVersion !== 1 || ledger.runtimeTarget !== "docker-dev-http" ||
        typeof group.runPrefix !== "string" || !group.runPrefix || ledger.runPrefix !== group.runPrefix || ledger.tenantCode !== tenant ||
        ledger.provider !== row.paymentProvider || anchors.orderId !== row.orderId || anchors.orderReferenceId !== row.orderReferenceId ||
        anchors.amount !== row.orderAmount || anchors.currency !== row.orderCurrencyCode || ledger.verification !== "passed" ||
        ledger.restoration !== "passed" || ledgerRow.runId !== caseRunId || ledgerRow.tenantCode !== tenant || ledgerRow.orderId !== row.orderId ||
        ledgerRow.orderReferenceId !== row.orderReferenceId || ledgerRow.journeyOutcome !== row.journeyOutcome ||
        ledger.mutation !== (success ? "provider-confirmed" : "submission-started") ||
        sql.tenantCode !== tenant || sql.orderId !== row.orderId || sql.status !== "passed") return undefined;
    const dependencyPath = `${reportDirectory}/provider-dependencies.json`;
    const dependencies = record(parse(loaded.get(dependencyPath)));
    const evidence = Array.isArray(dependencies?.evidence) ? dependencies.evidence.filter((item): item is string => typeof item === "string") : [];
    const expectedSimulation = expectedKind === "deterministic" ? "Simulation=True" : "Simulation=False";
    const dependency = (operation: string, id?: string) => evidence.some(line =>
      line.includes(`Provider=${row.paymentProvider}`) && line.includes(expectedSimulation) &&
      line.includes(`Operation=${operation}`) && (!id || line.includes(`ProviderPaymentId=${id}`)));
    if (dependencies?.mode !== row.adapterMode || !dependency("create-charge")) return undefined;
    if (success) {
      const confirmation = record(parse(loaded.get(`${caseDirectory}/provider-confirmation.json`)));
      const result = record(confirmation?.confirmation);
      const verification = record(parse(loaded.get(`${reportDirectory}/${tenant}-${provider}-verification-report.json`)));
      const checks = record(verification?.Checks);
      const correlations = Array.isArray(verification?.ChargeCorrelation)
        ? verification.ChargeCorrelation.map(record).filter((item): item is JsonRecord => !!item) : [];
      const paymentId = typeof result?.paymentId === "string" ? result.paymentId : "";
      if (!confirmation || !result || result.status !== "completed" || result.remoteStatusConfirmed !== true ||
          result.isSuccess !== true || result.providerAmount !== row.orderAmount || sql.expectedOutcome !== "success" ||
          sql.orderStatus !== "Paid" || sql.successfulCharges !== 1 || sql.allAttempts !== 1 || sql.failedAttempts !== 0 ||
          sql.allPayinLogs !== 1 || confirmation.tenant !== tenant || confirmation.orderId !== row.orderId ||
          confirmation.orderReferenceId !== row.orderReferenceId || confirmation.amount !== row.orderAmount ||
          confirmation.currency !== row.orderCurrencyCode || confirmation.adapterMode !== row.adapterMode ||
          !paymentId || anchors.providerPaymentId !== paymentId || !checks || !correlations.length ||
          Object.values(checks).some(check => record(check)?.Outcome !== "PASS") ||
          !correlations.some(item => item.Tenant === tenant && item.CustomerOrderId === row.customerOrderId &&
            item.ChargeId === paymentId && item.InDb === true && item.UiCallbackLogged === true) ||
          (expectedKind === "sandbox-positive" && (result.providerCurrency !== row.orderCurrencyCode ||
            !dependency("fetch-charge", paymentId) || (row.paymentProvider === "Razorpay"
              ? typeof result.providerOrderId !== "string" || !result.providerOrderId || !dependency("create-charge", result.providerOrderId)
              : !dependency("create-charge", paymentId))))) return undefined;
    }
    if (!success && (expectedKind !== "sandbox-negative" || row.paymentProvider !== "Razorpay" ||
        (row.journeyOutcome !== "expected-failure" && row.journeyOutcome !== "expected-cancelled") ||
        (sql.expectedOutcome !== "failure" && sql.expectedOutcome !== "cancelled") ||
        (row.journeyOutcome === "expected-failure" ? sql.expectedOutcome !== "failure" : sql.expectedOutcome !== "cancelled") ||
        sql.orderStatus !== "Created" || sql.successfulCharges !== 0 || sql.allAttempts !== 1 || sql.allPayinLogs !== 1 ||
        sql.failedAttempts !== (row.journeyOutcome === "expected-failure" ? 1 : 0) ||
        (row.journeyOutcome === "expected-failure" && !dependency("fetch-charge")))) return undefined;
  }
  const before = validatePhase10ImageManifest(parse(loaded.get("docker-image-identities-before.json")), runId, "before");
  const after = validatePhase10ImageManifest(parse(loaded.get("docker-image-identities-after.json")), runId, "after");
  const restoration = parse(loaded.get("restoration-contract.json"));
  const seedContract = record(seed);
  const settings = parse(loaded.get("seed-contract.json"));
  const restorationContract = record(restoration);
  const beforeSettings = record(settings);
  const afterSettings = record(restoration);
  const seedProjection = (value: JsonRecord | undefined) => value && ({ scope: value.scope, status: value.status,
    activeTenantCount: value.activeTenantCount, supportedProviders: value.supportedProviders,
    tenants: finalizedRestoration && Array.isArray(value.tenants) ? value.tenants.map(tenant => {
      const entry = record(tenant);
      return entry ? Object.fromEntries(Object.entries(entry).filter(([key]) => key !== "customerCount")) : tenant;
    }) : value.tenants });
  const configurationMatched = !!beforeSettings && !!afterSettings &&
    isDeepStrictEqual(seedProjection(beforeSettings), seedProjection(afterSettings));
  if (before.status !== "PASS" || after.status !== "PASS" || before.manifest.candidate.commit !== expectedCommit ||
      after.manifest.candidate.commit !== expectedCommit || before.manifest.candidate.worktree !== "clean" ||
      after.manifest.candidate.worktree !== "clean" || !phase10ImageSetsMatch(before.manifest, after.manifest) ||
      !seedContract || restorationContract?.status !== "passed" || !configurationMatched) return undefined;
  return { kind: expectedKind, status: "PASS", report: normalized, configurationMatched,
    before: before.manifest, after: after.manifest, runId, seed, restored: restoration };
}
