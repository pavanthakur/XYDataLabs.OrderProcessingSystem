import http from "node:http";
import https from "node:https";
import { spawn } from "node:child_process";
import { mkdir, readFile, writeFile, open, unlink } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { CleanupOutcome } from "../contracts/payment-fixture-provisioner.js";
import { assertAssignedSandboxRoutes, type NonAdminSandboxIdentity } from "../support/non-admin-sandbox.js";
import type { PaymentFixtureProvisioner } from "../contracts/payment-fixture-provisioner.js";
import type { ExecutiveSummaryRow } from "../contracts/report-composer.js";
import { PowerShellPaymentProviderProvisioner } from "../adapters/fixtures/powershell-payment-provider-provisioner.js";
import { ApiTenantExecutionCatalog } from "../catalog/api-tenant-execution-catalog.js";
import { JsonRuntimeTargetCatalog } from "../catalog/json-runtime-target-catalog.js";
import { StaticTenantExecutionCatalog } from "../catalog/static-tenant-execution-catalog.js";
import { PaymentJourneyRunner } from "../browser/payment-journey-runner.js";
import { FileReportComposer } from "../report/file-report-composer.js";
import { buildCustomerOrderId, buildRunPrefix } from "../support/customer-order-id.js";
import { PowerShellVerificationAdapter } from "../verification/powershell-verification-adapter.js";
import {safePaymentDiagnostic} from "../support/payment-diagnostics.js";
import { assertResumeSafe, candidateIdentity, matrixBinding, readCheckpoint, saveCheckpoint, type MatrixCheckpoint } from "../support/azure-matrix-checkpoint.js";
import { isAuthPreflightSignOutVerified } from "../support/operator-sign-out.js";
import {recordCaseProgress,saveCaseLedger,verificationOnlyRecoveryEligible,type PaymentCaseLedger} from "../support/payment-case-ledger.js";
import type {VerificationRequest} from "../contracts/verification-adapter.js";

export interface ExecutePaymentAutomationRunOptions {
  target: string;
  tenantCodes: string[];
  allowPartialExecution: boolean;
  dryRun: boolean;
  headless: boolean;
  verify: boolean;
  sandboxOtpCode: string;
  tenantTimeoutMs: number;
  requestedProviders?: string[];
  runPrefix?: string;
  startedAt?: Date;
  reportDirectoryRoot?: string;
  autoStartLocalSessions?: boolean;
  autoStopLocalSessions?: boolean;
  tenantLimit?: number;
  logger?: (message: string) => void;
  expectedAdapterMode?: "sandbox" | "deterministic";
  threeDs?: boolean;
  loginUsername?: string;
  operatorAssistedEntra?: boolean;
  nonAdminSandboxIdentities?: Record<string, NonAdminSandboxIdentity>;
  authPreflightOnly?: boolean;
  manualEntry?: boolean;
  challengeRequired?: boolean;
  expectedOutcome?: "failure" | "cancelled";
  resumeCheckpoint?: string;
  continueAfterVerificationFailure?: boolean;
}

export interface PaymentAutomationRunOutput {
  runId: string;
  runPrefix: string;
  reportDirectory: string;
  rows: ExecutiveSummaryRow[];
  verificationSummary: string;
  verificationSafety?: "established" | "unknown";
  operatorAuthPreflight?: { status: "PASS" | "FAIL"; startedUtc: string; finishedUtc: string; evidence: string; error?: string };
  operatorSignOut?: { status: "PASS" | "FAIL"; error?: string };
}

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const automationRoot = path.resolve(currentDirectory, "../..");

interface ExecutionItem {
  tenantCode: string;
  tenantTier: string;
  registryProviderCode?: string | null;
  paymentProviderCode?: string | null;
  shouldPrepareProviderFixture: boolean;
  executionRunPrefix: string;
}

interface TenantTopologyArtifactItem {
  tenantCode: string;
  active: boolean;
  tier: string;
  providerCode: string | null;
  dedicatedDatabaseName: string | null;
  dedicatedConnectionSecret: string | null;
  providerPrivateKeyAlias: string | null;
  contractStatus: string;
}

export async function executePaymentAutomationRun(
  options: ExecutePaymentAutomationRunOptions
): Promise<PaymentAutomationRunOutput> {
  const runtimeTargetCatalog = new JsonRuntimeTargetCatalog();
  const reportComposer = new FileReportComposer();
  const verificationAdapter = new PowerShellVerificationAdapter();
  const paymentJourneyRunner = new PaymentJourneyRunner();
  const log = (message:string) => options.logger?.(safePaymentDiagnostic(message));
  log(`Resolving runtime target ${options.target}.`);
  const target = await runtimeTargetCatalog.resolve(options.target);
  const operatorLockPath = path.resolve(automationRoot, "../TestResults/Playwright/azure-operator-session.lock");
  let operatorLock: Awaited<ReturnType<typeof open>> | undefined;
  if (options.operatorAssistedEntra) {
    await mkdir(path.dirname(operatorLockPath), { recursive: true });
    operatorLock = await open(operatorLockPath, "wx").catch(() => { throw new Error("Azure operator session lock exists or is inaccessible. Review the active/interrupted run; never delete its lock automatically."); });
  }
  try {
  log(`Resolved runtime target ${target.key} (${target.runtime}/${target.profile}).`);
  log(`Resolving tenant execution plan for ${options.target}.`);
  const tenantExecutionCatalog = options.dryRun && target.runtime !== "azure"
    ? new StaticTenantExecutionCatalog()
    : new ApiTenantExecutionCatalog(target);
  const tenantPlan = await tenantExecutionCatalog.resolve(
    options.tenantCodes,
    options.allowPartialExecution || target.supportsPartialExecution,
    log
  );
  log(`Resolved ${tenantPlan.resolvedTenants.length} tenant(s); skipped ${tenantPlan.skippedTenantCodes.length}.`);
  const resolvedTenants = applyTenantLimit(tenantPlan.resolvedTenants, options.tenantLimit, log);
  const nonAdmin = options.nonAdminSandboxIdentities;
  if (nonAdmin) {
    if (target.key !== "azure-dev" || !options.operatorAssistedEntra || options.headless || !options.verify ||
        options.dryRun || options.requestedProviders?.length || options.resumeCheckpoint ||
        options.allowPartialExecution || options.expectedOutcome || options.continueAfterVerificationFailure ||
        options.expectedAdapterMode === "deterministic" || options.tenantLimit !== undefined) {
      throw new Error("Non-admin checkout requires a full, verified Azure-dev assigned-provider run.");
    }
    assertAssignedSandboxRoutes(resolvedTenants, options.tenantCodes);
    if (resolvedTenants.some(tenant => !nonAdmin[tenant.tenantCode])) throw new Error("A verified non-admin identity mapping is missing.");
    resolvedTenants.sort((a, b) => a.tenantCode.localeCompare(b.tenantCode));
    log("Non-admin assigned-provider mode: one verified session per mapped tenant, no provider fixtures.");
  }
  const startedAt = options.startedAt ?? new Date();
  const runId = `payment-automation-${startedAt.toISOString().replace(/[.:]/g, "-")}`;
  const runPrefix = options.runPrefix ?? buildRunPrefix(startedAt);
  const reportDirectory = path.join(options.reportDirectoryRoot ?? path.join(automationRoot, "reports"), runId);
  const allExecutionItems = buildExecutionItems(
    resolvedTenants,
    normalizeRequestedProviders(options.requestedProviders ?? []),
    startedAt,
    runPrefix
  );
  const executionItems = options.authPreflightOnly ? allExecutionItems.slice(0, 1) : allExecutionItems;

  await mkdir(reportDirectory, { recursive: true });
  const tenantTopology = await buildTenantTopologyArtifact(target.runtime, target.environment, tenantPlan.resolvedTenants);
  await writeFile(path.join(reportDirectory, "tenant-topology.json"), JSON.stringify(tenantTopology, null, 2), "utf8");
  await writeFile(
    path.join(reportDirectory, "execution-plan.json"),
    JSON.stringify(
      executionItems.map((item) => ({
        tenantCode: item.tenantCode,
        tenantTier: item.tenantTier,
        registryProviderCode: item.registryProviderCode ?? null,
        executionProviderCode: item.paymentProviderCode ?? null,
        usesProviderOverride: item.shouldPrepareProviderFixture,
        executionRunPrefix: item.executionRunPrefix
      })),
      null,
      2
    ),
    "utf8"
  );
  log(`Starting payment automation run ${runId} with prefix ${runPrefix}.`);

  const targetUrl = `${target.baseUrl}${target.paymentPagePath}`;
  if (!options.dryRun) {
    log(`Checking target readiness at ${targetUrl}.`);
    if (target.runtime === "local" && options.autoStartLocalSessions !== false) {
      log(`Target runtime is local and auto-start is enabled; ensuring local target readiness.`);
      await ensureLocalTargetReady(target.profile, targetUrl, target.ignoreHttpsErrors, log);
    }
    else {
      log(`Waiting for target readiness without auto-start.`);
      await waitForTargetReadiness(targetUrl, target.ignoreHttpsErrors, log);
    }
  }
  log(`Target readiness phase completed for ${target.key}.`);

  const rows: ExecutiveSummaryRow[] = [];
  const verificationSummaries: string[] = [];
  const verificationSafetySignals:boolean[]=[];
  const checkpointEnabled = target.runtime === "azure" && options.operatorAssistedEntra && !options.authPreflightOnly && !options.dryRun;
  if (options.resumeCheckpoint && !checkpointEnabled) throw new Error("Resume requires the headed Azure-dev payment matrix.");
  const caseKey = (item: ExecutionItem) => `${item.tenantCode.toLowerCase()}|${(item.paymentProviderCode ?? "resolved").toLowerCase()}`;
  const checkpointPath = path.join(reportDirectory, "checkpoint.json");
  const provenance=checkpointEnabled?{
    candidate:await candidateIdentity(path.resolve(automationRoot,"..")),
    deployment: process.env.XYDATALABS_AZURE_DEV_DEPLOYMENT_IDENTITY ?? "UNKNOWN",
    settings: process.env.XYDATALABS_AZURE_DEV_SETTINGS_IDENTITY ?? "UNKNOWN"
  }:undefined;
  const binding = checkpointEnabled ? matrixBinding({
    ...provenance,
    target, topology: tenantTopology, providers: providersForCheckpoint(options), threeDs: options.threeDs
  }) : "";
  let checkpoint: MatrixCheckpoint = { schemaVersion: 1, binding, cases: [],provenance,plannedKeys:executionItems.map(caseKey) };
  if (options.resumeCheckpoint) {
    if (!process.env.XYDATALABS_AZURE_DEV_DEPLOYMENT_IDENTITY || !process.env.XYDATALABS_AZURE_DEV_SETTINGS_IDENTITY) throw new Error("Deployment/settings identity is UNKNOWN; resume through the operator wrapper only.");
    checkpoint = await readCheckpoint(options.resumeCheckpoint, path.resolve(automationRoot, "../TestResults/Playwright"));
    assertResumeSafe(checkpoint, binding, executionItems.map(caseKey));
    rows.push(...checkpoint.cases.map((item) => ({...item.row!,executionEvidence:item.row!.executionEvidence==="read-only-reconciled"?"read-only-reconciled" as const:"carried-forward" as const})));
    verificationSummaries.push(`Carried forward ${rows.length} previously verified/restored receipts under unchanged identity; these are not newly submitted payments.`);
    log(`Resume: preserving ${rows.length} verified/restored case receipts. No prior payment will be submitted again.`);
  }
  if (checkpointEnabled) await saveCheckpoint(checkpointPath, checkpoint);

  let operatorAuthPreflight: PaymentAutomationRunOutput["operatorAuthPreflight"];
  const providersForRun = normalizeRequestedProviders(options.requestedProviders ?? []);
  const requiresSingleSessionPreflight = target.runtime === "azure" && target.environment === "dev"
    && options.operatorAssistedEntra === true && !options.authPreflightOnly
    && providersForRun.length === 2
    && providersForRun.some((provider) => provider.toLowerCase() === "razorpay")
    && providersForRun.some((provider) => provider.toLowerCase() === "openpay");
  if (requiresSingleSessionPreflight) {
    const preflightStartedUtc = new Date().toISOString();
    const preflightTenant = executionItems[0]?.tenantCode;
    try {
      if (!preflightTenant) throw new Error("No active tenant was available for the Entra preflight.");
      const preflightResult = await paymentJourneyRunner.execute({
        tenantCode: preflightTenant,
        target,
        customerOrderId: "not-created",
        sandboxOtpCode: options.sandboxOtpCode,
        headless: false,
        expectedAdapterMode: "sandbox",
        operatorAssistedEntra: true,
        reuseEntraSession: true,
        authPreflightOnly: true,
        retainOperatorSessionAfterAuthPreflight: true,
        logger: (message) => log(`[Entra no-charge preflight] ${message}`)
      });
      if (preflightResult.journeyOutcome !== "auth-preflight-passed") {
        throw new Error("The authenticated tenant/access preflight did not return its required PASS outcome.");
      }
      operatorAuthPreflight = {
        status: "PASS",
        startedUtc: preflightStartedUtc,
        finishedUtc: new Date().toISOString(),
        evidence: safePaymentDiagnostic(preflightResult.statusMessage)
      };
    } catch (error) {
      operatorAuthPreflight = {
        status: "FAIL",
        startedUtc: preflightStartedUtc,
        finishedUtc: new Date().toISOString(),
        evidence: "No order or payment was attempted; the complete provider matrix was blocked before fixture mutation.",
        error: safePaymentDiagnostic(error instanceof Error ? error.message : "Entra no-charge preflight failed.")
      };
      log(`[Entra no-charge preflight] Failed; all payment cases are blocked: ${operatorAuthPreflight.error}`);
    }
    await writeFile(path.join(reportDirectory, "operator-auth-preflight.json"), JSON.stringify(operatorAuthPreflight, null, 2), "utf8");
  }

  const runnableExecutionItems = operatorAuthPreflight?.status === "FAIL" ? [] : executionItems;
  let nonAdminSignOuts = 0;
  for (const executionItem of runnableExecutionItems) {
    if (checkpointEnabled && checkpoint.cases.some((item) => item.key === caseKey(executionItem))) continue;
    // Durable intent precedes fixture or order mutation. An interrupted intent is never auto-retried.
    if (checkpointEnabled) {
      checkpoint.cases.push({ key: caseKey(executionItem), state: "started" });
      await saveCheckpoint(checkpointPath, checkpoint);
    }
    const tenantStartedAt = new Date();
    log(`Starting tenant ${executionItem.tenantCode} (${executionItem.tenantTier}${executionItem.paymentProviderCode ? `, provider ${executionItem.paymentProviderCode}` : ""}).`);
    const syntheticCustomerOrderId = buildCustomerOrderId(
      executionItem.executionRunPrefix,
      executionItem.tenantCode,
      target.profile,
      target.runtime,
      executionItem.paymentProviderCode ?? undefined
    );
    let customerOrderId = options.authPreflightOnly ? "not-created" : syntheticCustomerOrderId;
    let orderId = 0;
    let orderReferenceId = options.authPreflightOnly ? "not-created" : "not-available";
    let orderAmount = 0;
    let orderCurrencyCode = options.authPreflightOnly ? "not-applicable" : "unknown";
    const tenantDiagnosticsDirectory = path.join(
      reportDirectory,
      executionItem.tenantCode,
      normalizeProviderForPath(executionItem.paymentProviderCode ?? "resolved")
    );
    let journeyOutcome = options.dryRun ? "dry_run" : "failed";
    let challengeOutcome: ExecutiveSummaryRow["challengeOutcome"] = "not-applicable";
    let threeDsSetting: ExecutiveSummaryRow["threeDsSetting"] = "unknown";
    let paymentEvidence: Partial<ExecutiveSummaryRow> = {};
    let paymentProvider = executionItem.paymentProviderCode ?? "unresolved";
    let verificationOutcome = options.authPreflightOnly ? "not-applicable" : options.verify && !options.dryRun ? "pending" : "skipped";
    let cleanupOutcome: CleanupOutcome = "not-applicable";
    let evidenceReference = options.authPreflightOnly
      ? "Auth preflight only; no customer, order, or payment mutation was attempted."
      : `customerOrderId:${syntheticCustomerOrderId} | runPrefix:${executionItem.executionRunPrefix}`;
    let outcomeMessage = "";
    let errorDetail = "";
    let fixtureIds: string[] = [];
    let provisioner: PaymentFixtureProvisioner | undefined;
    let stopAfterCurrentItem = false;
    let verificationRequest:VerificationRequest|undefined;
    let caseVerificationSafety=false;
    const ledgerPath=path.join(tenantDiagnosticsDirectory,"case-ledger.json");
    const ledger:PaymentCaseLedger={schemaVersion:1,tenantCode:executionItem.tenantCode,provider:paymentProvider,runtimeTarget:target.key,
      runPrefix:executionItem.executionRunPrefix,startedUtc:tenantStartedAt.toISOString(),mutation:"preparing",journey:"pending",verification:"pending",restoration:"pending"};
    const ledgerEnabled=!options.dryRun&&!options.authPreflightOnly;
    if(ledgerEnabled){await mkdir(tenantDiagnosticsDirectory,{recursive:true});await saveCaseLedger(ledgerPath,ledger);}

    try {
      if (!options.dryRun && executionItem.paymentProviderCode && (executionItem.shouldPrepareProviderFixture || options.threeDs !== undefined)) {
        provisioner = new PowerShellPaymentProviderProvisioner({
          target,
          requestedProvider: executionItem.paymentProviderCode,
          threeDs: options.threeDs,
          logger: (message) => {
            log(`[${executionItem.tenantCode}/${executionItem.paymentProviderCode}] ${message}`);
          }
        });

        const fixturePrepareResult = await provisioner.prepare(executionItem.tenantCode);
        fixtureIds = fixturePrepareResult.fixtureIds;
        if (fixtureIds.length > 0) cleanupOutcome = "manual-review";
        evidenceReference = `${evidenceReference} | baseline:${fixturePrepareResult.baselineName}`;
      }

      if (!options.dryRun) {
        log(
          `Running tenant ${executionItem.tenantCode} (tier ${executionItem.tenantTier}${executionItem.paymentProviderCode ? `, provider ${executionItem.paymentProviderCode}` : ""}) and order id ${customerOrderId}.`
        );
        const journeyAbort=new AbortController();
        const journey=paymentJourneyRunner.execute({
            tenantCode: executionItem.tenantCode,
            target,
            customerOrderId,
            sandboxOtpCode: options.sandboxOtpCode,
            headless: options.headless,
            requestedProvider: executionItem.paymentProviderCode ?? undefined,
            diagnosticsDirectory: tenantDiagnosticsDirectory,
            expectedAdapterMode: options.expectedAdapterMode ?? "sandbox",
            challengeRequired: options.challengeRequired,
            expectedThreeDs: options.threeDs,
            loginUsername: options.loginUsername,
            operatorAssistedEntra: options.operatorAssistedEntra,
            nonAdminIdentity: nonAdmin?.[executionItem.tenantCode],
            reuseEntraSession: options.operatorAssistedEntra,
            authPreflightOnly: options.authPreflightOnly,
            retainOperatorSessionAfterAuthPreflight: !!nonAdmin && options.authPreflightOnly === true,
            manualEntry: options.manualEntry,
            expectedOutcome: options.expectedOutcome,
            signal:journeyAbort.signal,
            onProgress:ledgerEnabled?async progress=>{
              recordCaseProgress(ledger,progress);
              await saveCaseLedger(ledgerPath,ledger);
              if(progress.orderId!==undefined) orderId=progress.orderId;
              if(progress.customerOrderId) customerOrderId=progress.customerOrderId;
              if(progress.orderReferenceId) orderReferenceId=progress.orderReferenceId;
              if(progress.amount!==undefined) orderAmount=progress.amount;
              if(progress.currency) orderCurrencyCode=progress.currency;
            }:undefined,
            logger: (message) => {
              log(`[${executionItem.tenantCode}] ${message}`);
            }
          });
        const journeyResult = await withTimeout(journey,
          options.tenantTimeoutMs,
          `Tenant ${executionItem.tenantCode} exceeded ${options.tenantTimeoutMs}ms.`,()=>journeyAbort.abort()
        );

        journeyOutcome = journeyResult.journeyOutcome;
        challengeOutcome = journeyResult.challengeOutcome;
        threeDsSetting = journeyResult.threeDsSetting;
        paymentEvidence = {adapterMode:journeyResult.adapterMode,collectionMode:journeyResult.collectionMode,
          observedChallenge:journeyResult.observedChallenge,providerVerification:journeyResult.providerVerification,
          tenantPreflightResults:journeyResult.tenantPreflightResults};
        paymentProvider = journeyResult.paymentProvider;
        customerOrderId = journeyResult.customerOrderId;
        orderId = journeyResult.orderId;
        orderReferenceId = journeyResult.orderReferenceId;
        orderAmount = journeyResult.orderAmount;
        orderCurrencyCode = journeyResult.orderCurrencyCode;
        outcomeMessage = journeyResult.statusMessage;
        evidenceReference = `customerOrderId:${customerOrderId} | orderId:${orderId} | orderRef:${orderReferenceId} | amount:${orderAmount} ${orderCurrencyCode} -> ${journeyResult.finalUrl}`;
        const providerPaymentId = extractProviderPaymentId(journeyResult.finalUrl);

        if(options.expectedOutcome) verificationOutcome="passed"; // Runner verifies provider failure/cancellation and authoritative unpaid order independently.
        if (options.verify && !options.expectedOutcome && !options.authPreflightOnly) {
          try {
            log(
              `[${executionItem.tenantCode}] Verification anchor customerOrderId=${customerOrderId} runPrefix=${executionItem.executionRunPrefix}.`
            );
            verificationRequest={
              runtimeTarget: target.key,
              runtime: target.runtime,
              environment: target.environment,
              profile: target.profile,
              runPrefix: executionItem.executionRunPrefix,
              tenantCode: executionItem.tenantCode,
              customerOrderId,
              orderReferenceId,
              providerPaymentId,
              startedUtc: tenantStartedAt.toISOString(),
              finishedUtc: new Date().toISOString(),
              sqlAuthenticationMode: options.operatorAssistedEntra ? "entra" : "key-vault"
            };
            const verificationResult = await verificationAdapter.execute(verificationRequest);

            verificationOutcome = verificationResult.outcome;
            caseVerificationSafety=verificationResult.safetyEstablished===true;
            verificationSafetySignals.push(caseVerificationSafety);
            if (verificationOutcome !== "passed" && !options.allowPartialExecution) stopAfterCurrentItem = true;
            verificationSummaries.push(verificationResult.summary);

            // The setting was captured before submission; never overwrite it with
            // current DB routing/flags after callback or infer it from navigation.

            await writeFile(
              path.join(
                reportDirectory,
                `${executionItem.tenantCode}-${normalizeProviderForPath(paymentProvider)}-verification-report.json`
              ),
              JSON.stringify(verificationResult.rawReport ?? {}, null, 2),
              "utf8"
            );
          }
          catch (error) {
            verificationSafetySignals.push(false);
            verificationOutcome = "failed";
            const verificationMessage = error instanceof Error ? error.message : "Verification failed.";
            verificationSummaries.push(`Verification failed for ${executionItem.tenantCode}: ${verificationMessage}`);
            log(`[${executionItem.tenantCode}] Verification failed: ${verificationMessage}`);
            if (!options.allowPartialExecution) {
              stopAfterCurrentItem = true;
              log(`Stopping the payment matrix after ${executionItem.tenantCode}; required provider/SQL verification failed, so no further tenant payment will be submitted.`);
            }
          }
        }
      }
    }
    catch (error) {
      const errorMessage = safePaymentDiagnostic(error instanceof Error ? error.message : "Unknown error.");
      journeyOutcome = `failed: ${errorMessage}`;
      errorDetail = errorMessage;
      verificationOutcome = options.authPreflightOnly ? "not-applicable" : "skipped";
      if (!options.allowPartialExecution) {
        stopAfterCurrentItem = true;
      }
    }
    finally {
      if (nonAdmin) {
        try {
          await paymentJourneyRunner.closeOperatorAssistedSession(log, true);
          nonAdminSignOuts++;
        } catch {
          stopAfterCurrentItem = true;
          log(`[${executionItem.tenantCode}] Non-admin identity sign-out was not verified. No further cases will run.`);
        }
      }
      if (provisioner && fixtureIds.length > 0) {
        try {
          const fixtureCleanupResult = await provisioner.cleanup(executionItem.tenantCode, fixtureIds);
          cleanupOutcome = fixtureCleanupResult.outcome;
        }
        catch (error) {
          cleanupOutcome = "manual-review";
          stopAfterCurrentItem = true;
          const cleanupMessage = error instanceof Error ? error.message : "Cleanup failed.";
          evidenceReference = `${evidenceReference} | cleanup:${cleanupMessage}`;
          log(`[${executionItem.tenantCode}/${executionItem.paymentProviderCode}] Fixture restoration failed; the provider matrix is stopping immediately.`);
        }
      }

      rows.push({
        runId,
        runtimeTarget: target.key,
        tenantCode: executionItem.tenantCode,
        challengeOutcome,
        journeyOutcome,
        verificationOutcome,
        cleanupOutcome,
        executionEvidence:options.dryRun?"planned":"fresh",
        customerOrderId,
        orderId,
        orderReferenceId,
        orderAmount,
        orderCurrencyCode,
        outcomeMessage,
        errorDetail,
        startedUtc: tenantStartedAt.toISOString(),
        finishedUtc: new Date().toISOString(),
        evidenceReference,
        threeDsSetting,
        paymentProvider
        ,...paymentEvidence
      });

      if(ledgerEnabled){
        const row=rows.at(-1)!;
        ledger.journey=row.journeyOutcome==="completed"?"completed":"blocked";
        ledger.verification=row.verificationOutcome==="passed"?"passed":"blocked";
        ledger.restoration=row.cleanupOutcome==="reset"||row.cleanupOutcome==="not-applicable"?"passed":"blocked";
        ledger.finishedUtc=row.finishedUtc;
        ledger.row={...row,outcomeMessage:"See original journey report.",errorDetail:"",evidenceReference:"Durable case ledger; not a new submission."};
        await saveCaseLedger(ledgerPath,ledger);
        await writeFile(path.join(reportDirectory,"partial-summary.json"),JSON.stringify({runId,rows},null,2),"utf8");
      }

      if (checkpointEnabled) {
        const row = rows.at(-1)!;
        const receipt = checkpoint.cases.find((item) => item.key === caseKey(executionItem))!;
        if (row.journeyOutcome.startsWith("completed") && row.verificationOutcome === "passed"
          && (row.cleanupOutcome === "reset" || (nonAdmin && row.cleanupOutcome === "not-applicable")) && row.adapterMode === "sandbox") {
          receipt.state = "verified-restored";
          // Explicit field projection: no URLs, arbitrary errors, tokens or raw provider payloads.
          receipt.row = {
            runId: row.runId, runtimeTarget: row.runtimeTarget, tenantCode: row.tenantCode, paymentProvider: row.paymentProvider,
            customerOrderId: row.customerOrderId, orderId: row.orderId, orderReferenceId: row.orderReferenceId,
            orderAmount: row.orderAmount, orderCurrencyCode: row.orderCurrencyCode, threeDsSetting: row.threeDsSetting,
            adapterMode: row.adapterMode, collectionMode: row.collectionMode, observedChallenge: row.observedChallenge,
            journeyOutcome: row.journeyOutcome, challengeOutcome: row.challengeOutcome, verificationOutcome: row.verificationOutcome,
            cleanupOutcome: row.cleanupOutcome, startedUtc: row.startedUtc, finishedUtc: row.finishedUtc,
            outcomeMessage: "Previously verified sandbox case; see original runId evidence.", errorDetail: "",
            evidenceReference: "Preserved verified/restored checkpoint receipt; not a newly executed payment."
          };
        } else if(verificationOnlyRecoveryEligible(ledger) && verificationRequest){
          receipt.state="verification-pending";
          receipt.row=ledger.row;
          receipt.request=verificationRequest;
          receipt.ledgerPath=path.relative(reportDirectory,ledgerPath);
        }
        await saveCheckpoint(checkpointPath, checkpoint);
        await writeFile(path.join(reportDirectory, "partial-summary.json"), JSON.stringify({ runId, rows }, null, 2), "utf8");
      }

      log(
        `Tenant summary: ${executionItem.tenantCode} | provider=${paymentProvider} | tier=${executionItem.tenantTier} | journey=${journeyOutcome} | verification=${verificationOutcome} | cleanup=${cleanupOutcome}.`
      );
    }

    if(stopAfterCurrentItem && options.continueAfterVerificationFailure && caseVerificationSafety && verificationOnlyRecoveryEligible(ledger) && ledger.verification==="blocked"){
      try {
        const health=await paymentJourneyRunner.execute({tenantCode:executionItem.tenantCode,target,customerOrderId:"not-created",
          sandboxOtpCode:options.sandboxOtpCode,headless:false,expectedAdapterMode:"sandbox",operatorAssistedEntra:true,
          reuseEntraSession:true,authPreflightOnly:true,retainOperatorSessionAfterAuthPreflight:true,logger:log});
        if(health.journeyOutcome!=="auth-preflight-passed") throw new Error("Authenticated safety recheck failed.");
        stopAfterCurrentItem=false;
        log("Payment is confirmed and settings restored; verification remains BLOCKED. Authenticated safety recheck passed; continuing independent cases without resubmission.");
      }catch{log("Authentication/shared safety could not be revalidated; all further submissions remain stopped.");}
    }

    if (stopAfterCurrentItem) {
      log(`Stopping after tenant ${executionItem.tenantCode} due to failure and partial execution disabled.`);
      break;
    }
  }

  let operatorSignOut: PaymentAutomationRunOutput["operatorSignOut"];
  if (options.operatorAssistedEntra && !options.dryRun && operatorAuthPreflight?.status !== "FAIL") {
    if (nonAdmin) {
      operatorSignOut = nonAdminSignOuts === executionItems.length ? { status: "PASS" }
        : { status: "FAIL", error: "Not every non-admin account case completed and verified sign-out." };
    } else if (options.authPreflightOnly) {
      if (isAuthPreflightSignOutVerified(rows)) {
        operatorSignOut = { status: "PASS" };
      } else {
        const message = "No-charge Entra preflight did not verify application sign-out.";
        operatorSignOut = { status: "FAIL", error: message };
        log(message);
      }
    } else {
      try {
        await paymentJourneyRunner.closeOperatorAssistedSession(log, true);
        operatorSignOut = { status: "PASS" };
      } catch (error) {
        const message = safePaymentDiagnostic(error instanceof Error ? error.message : "Entra sign-out verification failed.");
        operatorSignOut = { status: "FAIL", error: message };
        log(message);
      }
    }
  }

  const verificationSummary = verificationSummaries.length > 0
    ? verificationSummaries.join(" | ")
    : "Verification skipped.";

  const markdownSummary = await reportComposer.compose(rows);
  const output: PaymentAutomationRunOutput = {
    runId,
    runPrefix,
    reportDirectory,
    rows,
    verificationSummary,
    verificationSafety:verificationSafetySignals.length>0&&verificationSafetySignals.every(Boolean)?"established":"unknown",
    ...(operatorAuthPreflight ? { operatorAuthPreflight } : {}),
    ...(operatorSignOut ? { operatorSignOut } : {})
  };

  await writeFile(path.join(reportDirectory, "summary.md"), markdownSummary, "utf8");
  await writeFile(path.join(reportDirectory, "summary.json"), JSON.stringify(output, null, 2), "utf8");

  if (options.autoStopLocalSessions !== false && target.runtime === "local" && !options.dryRun) {
    await stopLocalSessions(target.profile, log);
  }

  return output;
  } finally {
    // Also close the browser on unexpected checkpoint/report errors. A hard kill leaves the lock for review.
    if (operatorLock) {
      try { await paymentJourneyRunner.closeOperatorAssistedSession(log); }
      finally { await operatorLock.close(); await unlink(operatorLockPath); }
    }
  }
}

function providersForCheckpoint(options: ExecutePaymentAutomationRunOptions): string[] {
  return normalizeRequestedProviders(options.requestedProviders ?? []).map((provider) => provider.toLowerCase()).sort();
}

function extractProviderPaymentId(finalUrl: string): string | undefined {
  try {
    const callbackUrl = new URL(finalUrl);
    return callbackUrl.searchParams.get("razorpay_payment_id")
      ?? callbackUrl.searchParams.get("id")
      ?? undefined;
  }
  catch {
    return undefined;
  }
}

function applyTenantLimit(
  tenants: Array<{ tenantCode: string; tenantTier: string; paymentProviderCode: string | null }>,
  tenantLimit: number | undefined,
  log: (message: string) => void
): Array<{ tenantCode: string; tenantTier: string; paymentProviderCode: string | null }> {
  if (tenantLimit === undefined || !Number.isFinite(tenantLimit) || tenantLimit <= 0) {
    return tenants;
  }

  const normalizedLimit = Math.floor(tenantLimit);
  if (tenants.length <= normalizedLimit) {
    return tenants;
  }

  const limitedTenants = tenants.slice(0, normalizedLimit);
  const skippedTenantCodes = tenants.slice(normalizedLimit).map((tenant) => tenant.tenantCode);
  log(`Tenant limit applied: using ${limitedTenants.length} of ${tenants.length} tenant(s). Skipped: ${skippedTenantCodes.join(", ")}.`);
  return limitedTenants;
}

function buildExecutionItems(
  tenants: Array<{ tenantCode: string; tenantTier: string; paymentProviderCode: string | null }>,
  requestedProviders: string[],
  startedAt: Date,
  defaultRunPrefix: string
): ExecutionItem[] {
  if (requestedProviders.length === 0) {
    return tenants.map((tenant, index) => ({
      tenantCode: tenant.tenantCode,
      tenantTier: tenant.tenantTier,
      registryProviderCode: tenant.paymentProviderCode,
      paymentProviderCode: tenant.paymentProviderCode,
      shouldPrepareProviderFixture: false,
      executionRunPrefix: index === 0 ? defaultRunPrefix : buildRunPrefix(new Date(startedAt.getTime() + (index * 1000)))
    }));
  }

  return tenants.flatMap((tenant, tenantIndex) =>
    requestedProviders.map((requestedProvider, providerIndex) => {
      const executionIndex = (tenantIndex * requestedProviders.length) + providerIndex;
      const executionStartedAt = new Date(startedAt.getTime() + (executionIndex * 1000));

      return {
        tenantCode: tenant.tenantCode,
        tenantTier: tenant.tenantTier,
        registryProviderCode: tenant.paymentProviderCode,
        paymentProviderCode: requestedProvider,
        shouldPrepareProviderFixture: true,
        executionRunPrefix: executionIndex === 0 ? defaultRunPrefix : buildRunPrefix(executionStartedAt)
      };
    })
  );
}

function normalizeProviderForPath(providerType: string): string {
  return providerType.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-");
}

function normalizeRequestedProviders(requestedProviders: string[]): string[] {
  if (requestedProviders.length === 0) {
    return [];
  }

  return Array.from(
    new Set(
      requestedProviders
        .map((provider) => provider.trim())
        .filter(Boolean)
    )
  );
}

async function buildTenantTopologyArtifact(
  runtime: string,
  environment: string,
  tenants: Array<{ tenantCode: string; tenantTier: string; paymentProviderCode: string | null }>
): Promise<TenantTopologyArtifactItem[]> {
  const dedicatedDatabaseNames = await loadDedicatedDatabaseNames(runtime, environment);

  return tenants.map((tenant) => {
    const normalizedTier = tenant.tenantTier.trim();
    const normalizedProvider = tenant.paymentProviderCode?.trim() ?? null;
    const dedicatedConnectionSecret = normalizedTier.toLowerCase() === "dedicated"
      ? `DedicatedTenantConnectionStrings--${tenant.tenantCode}`
      : null;
    const providerPrivateKeyAlias = normalizedProvider
      ? `PaymentProviders--${tenant.tenantCode}--${normalizedProvider}--PrivateKey`
      : null;
    const dedicatedDatabaseName = dedicatedConnectionSecret
      ? dedicatedDatabaseNames.get(tenant.tenantCode.toLowerCase()) ?? null
      : null;
    const contractStatus = normalizedTier.toLowerCase() === "dedicated" && !dedicatedDatabaseName
      ? "registry-discovered-awaiting-secret-validation"
      : "registry-discovered";

    return {
      tenantCode: tenant.tenantCode,
      active: true,
      tier: normalizedTier,
      providerCode: normalizedProvider,
      dedicatedDatabaseName,
      dedicatedConnectionSecret,
      providerPrivateKeyAlias,
      contractStatus
    };
  });
}

async function loadDedicatedDatabaseNames(runtime: string, environment: string): Promise<Map<string, string>> {
  if (runtime === "azure") {
    return new Map<string, string>();
  }

  const sharedSettingsFileName = runtime === "local"
    ? "sharedsettings.local.json"
    : `sharedsettings.${environment}.json`;
  const sharedSettingsPath = path.join(automationRoot, "..", "Resources", "Configuration", sharedSettingsFileName);
  const sharedSettings = JSON.parse(await readFile(sharedSettingsPath, "utf8")) as {
    DedicatedTenantConnectionStrings?: Record<string, string>;
  };

  const results = new Map<string, string>();
  for (const [tenantCode, connectionString] of Object.entries(sharedSettings.DedicatedTenantConnectionStrings ?? {})) {
    const databaseName = parseDatabaseNameFromConnectionString(connectionString);
    if (databaseName) {
      results.set(tenantCode.trim().toLowerCase(), databaseName);
    }
  }

  return results;
}

function parseDatabaseNameFromConnectionString(connectionString: string): string | null {
  const match = /(?:Initial\s+Catalog|Database)\s*=\s*([^;]+)/i.exec(connectionString);
  return match?.[1]?.trim() || null;
}

async function withTimeout<T>(promise: Promise<T>, timeoutMs: number, message: string, onTimeout:()=>void): Promise<T> {
  let timeoutHandle: NodeJS.Timeout | undefined;

  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        timeoutHandle = setTimeout(async () => {
          onTimeout();
          await promise.catch(()=>undefined);
          reject(new Error(message));
        }, timeoutMs);
      })
    ]);
  }
  finally {
    if (timeoutHandle) {
      clearTimeout(timeoutHandle);
    }
  }
}

async function ensureLocalTargetReady(
  profile: "http" | "https",
  targetUrl: string,
  ignoreHttpsErrors: boolean,
  log: (message: string) => void
): Promise<void> {
  if (await isUrlReachable(targetUrl, ignoreHttpsErrors)) {
    return;
  }

  log(`Local ${profile} target is not reachable yet; starting the profile automatically.`);
  await startLocalProfile(profile, log);

  const targetBecameReady = await waitForTargetReadiness(targetUrl, ignoreHttpsErrors, log, 60000);
  if (!targetBecameReady) {
    throw new Error(`Local ${profile} target did not become ready after automatic startup.`);
  }
}

async function waitForTargetReadiness(
  targetUrl: string,
  ignoreHttpsErrors: boolean,
  log: (message: string) => void,
  timeoutMs = 30000
): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  let reportedWait = false;

  while (Date.now() < deadline) {
    if (await isUrlReachable(targetUrl, ignoreHttpsErrors)) {
      return true;
    }

    if (!reportedWait) {
      reportedWait = true;
      log(`Waiting for target readiness at ${targetUrl}.`);
    }

    await sleep(1000);
  }

  log(`Target readiness check timed out for ${targetUrl}; continuing with browser navigation.`);
  return false;
}

async function isUrlReachable(targetUrl: string, ignoreHttpsErrors: boolean): Promise<boolean> {
  const url = new URL(targetUrl);
  const client = url.protocol === "https:" ? https : http;

  return new Promise<boolean>((resolve) => {
    const request = client.request({
      protocol: url.protocol,
      hostname: url.hostname,
      port: url.port,
      path: `${url.pathname}${url.search}`,
      method: "GET",
      timeout: 5000,
      rejectUnauthorized: !ignoreHttpsErrors
    }, (response) => {
      response.resume();
      resolve(Boolean(response.statusCode && response.statusCode >= 200 && response.statusCode < 400));
    });

    request.on("timeout", () => {
      request.destroy();
      resolve(false);
    });
    request.on("error", () => resolve(false));
    request.end();
  });
}

async function sleep(milliseconds: number): Promise<void> {
  await new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

export async function startLocalProfile(profile: "http" | "https", log: (message: string) => void): Promise<void> {
  const scriptPath = path.resolve(automationRoot, "..", "scripts", "start-local-profile.ps1");

  log(`Starting local ${profile} profile.`);

  await new Promise<void>((resolve, reject) => {
    const child = spawn("pwsh", [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      scriptPath,
      "-Profile",
      profile,
      "-ReturnWhenReady"
    ], {
      cwd: path.resolve(automationRoot, ".."),
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true
    });

    let stdout = "";
    let stderr = "";
    let settled = false;

    const settle = (callback: () => void): void => {
      if (settled) {
        return;
      }

      settled = true;
      child.stdout.removeAllListeners("data");
      child.stderr.removeAllListeners("data");
      child.removeAllListeners("error");
      child.removeAllListeners("exit");
      child.stdout.destroy();
      child.stderr.destroy();
      callback();
    };

    child.stdout.on("data", (chunk: Buffer | string) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk: Buffer | string) => {
      stderr += chunk.toString();
    });

    child.on("error", (error) => {
      settle(() => reject(error));
    });

    child.on("exit", (exitCode) => {
      if (exitCode === 0) {
        settle(resolve);
        return;
      }

      const combinedOutput = [stdout.trim(), stderr.trim()].filter(Boolean).join("\n");
      settle(() => reject(new Error(combinedOutput || `Local ${profile} profile exited unexpectedly with code ${exitCode}.`)));
    });
  });
}

async function stopLocalSessions(profile: "http" | "https", log: (message: string) => void): Promise<void> {
  const scriptPath = path.resolve(automationRoot, "..", "scripts", "stop-local-dev-sessions.ps1");

  log(`Stopping local ${profile} profile sessions after verification.`);

  await new Promise<void>((resolve, reject) => {
    const child = spawn("pwsh", [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      scriptPath,
      "-Profile",
      profile
    ], {
      cwd: path.resolve(automationRoot, ".."),
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true
    });

    let stdout = "";
    let stderr = "";
    let settled = false;

    const settle = (callback: () => void): void => {
      if (settled) {
        return;
      }

      settled = true;
      child.stdout.removeAllListeners("data");
      child.stderr.removeAllListeners("data");
      child.removeAllListeners("error");
      child.removeAllListeners("exit");
      child.stdout.destroy();
      child.stderr.destroy();
      callback();
    };

    child.stdout.on("data", (chunk: Buffer | string) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk: Buffer | string) => {
      stderr += chunk.toString();
    });

    child.on("error", (error) => {
      settle(() => reject(error));
    });

    child.on("exit", (exitCode) => {
      const combinedOutput = [stdout.trim(), stderr.trim()].filter(Boolean).join("\n");
      if (combinedOutput) {
        log(combinedOutput);
      }

      if (exitCode === 0) {
        settle(resolve);
        return;
      }

      settle(() => reject(new Error(`Automatic local ${profile} session stop exited with code ${exitCode}.`)));
    });
  });
}
