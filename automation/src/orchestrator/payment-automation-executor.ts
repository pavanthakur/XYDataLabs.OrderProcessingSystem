import http from "node:http";
import https from "node:https";
import { spawn } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { CleanupOutcome } from "../contracts/payment-fixture-provisioner.js";
import type { ExecutiveSummaryRow } from "../contracts/report-composer.js";
import { JsonRuntimeTargetCatalog } from "../catalog/json-runtime-target-catalog.js";
import { StaticTenantExecutionCatalog } from "../catalog/static-tenant-execution-catalog.js";
import { PaymentJourneyRunner } from "../browser/payment-journey-runner.js";
import { FileReportComposer } from "../report/file-report-composer.js";
import { buildCustomerOrderId, buildRunPrefix } from "../support/customer-order-id.js";
import { PowerShellVerificationAdapter } from "../verification/powershell-verification-adapter.js";

export interface ExecutePaymentAutomationRunOptions {
  target: string;
  tenantCodes: string[];
  allowPartialExecution: boolean;
  dryRun: boolean;
  headless: boolean;
  verify: boolean;
  sandboxOtpCode: string;
  tenantTimeoutMs: number;
  runPrefix?: string;
  startedAt?: Date;
  autoStopLocalSessions?: boolean;
  logger?: (message: string) => void;
}

export interface PaymentAutomationRunOutput {
  runId: string;
  runPrefix: string;
  reportDirectory: string;
  rows: ExecutiveSummaryRow[];
  verificationSummary: string;
}

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const automationRoot = path.resolve(currentDirectory, "../..");

export async function executePaymentAutomationRun(
  options: ExecutePaymentAutomationRunOptions
): Promise<PaymentAutomationRunOutput> {
  const runtimeTargetCatalog = new JsonRuntimeTargetCatalog();
  const tenantExecutionCatalog = new StaticTenantExecutionCatalog();
  const reportComposer = new FileReportComposer();
  const verificationAdapter = new PowerShellVerificationAdapter();
  const paymentJourneyRunner = new PaymentJourneyRunner();
  const target = await runtimeTargetCatalog.resolve(options.target);
  const tenantPlan = await tenantExecutionCatalog.resolve(
    options.tenantCodes,
    options.allowPartialExecution || target.supportsPartialExecution
  );

  const log = options.logger ?? (() => undefined);
  const startedAt = options.startedAt ?? new Date();
  const runId = `payment-automation-${startedAt.toISOString().replace(/[.:]/g, "-")}`;
  const runPrefix = options.runPrefix ?? buildRunPrefix(startedAt);
  const reportDirectory = path.join(automationRoot, "reports", runId);

  await mkdir(reportDirectory, { recursive: true });
  log(`Starting payment automation run ${runId} with prefix ${runPrefix}.`);
  await waitForTargetReadiness(`${target.baseUrl}${target.paymentPagePath}`, target.ignoreHttpsErrors, log);

  const rows: ExecutiveSummaryRow[] = [];
  for (const tenantCode of tenantPlan.resolvedTenantCodes) {
    const tenantStartedAt = new Date();
    const customerOrderId = buildCustomerOrderId(runPrefix, tenantCode, target.profile, target.runtime);
    const tenantDiagnosticsDirectory = path.join(reportDirectory, tenantCode);
    let journeyOutcome = options.dryRun ? "dry_run" : "failed";
    let challengeOutcome: ExecutiveSummaryRow["challengeOutcome"] = "not-applicable";
    let evidenceReference = `customerOrderId:${customerOrderId}`;

    try {
      if (!options.dryRun) {
        log(`Running tenant ${tenantCode} with order id ${customerOrderId}.`);
        const journeyResult = await withTimeout(
          paymentJourneyRunner.execute({
            tenantCode,
            target,
            customerOrderId,
            sandboxOtpCode: options.sandboxOtpCode,
            headless: options.headless,
            diagnosticsDirectory: tenantDiagnosticsDirectory,
            logger: (message) => {
              log(`[${tenantCode}] ${message}`);
            }
          }),
          options.tenantTimeoutMs,
          `Tenant ${tenantCode} exceeded ${options.tenantTimeoutMs}ms.`
        );

        journeyOutcome = journeyResult.journeyOutcome;
        challengeOutcome = journeyResult.challengeOutcome;
        evidenceReference = `${customerOrderId} -> ${journeyResult.finalUrl}`;
      }

      rows.push({
        runId,
        runtimeTarget: target.key,
        tenantCode,
        challengeOutcome,
        journeyOutcome,
        verificationOutcome: options.verify && !options.dryRun ? "pending" : "skipped",
        cleanupOutcome: resolveCleanupOutcome(),
        startedUtc: tenantStartedAt.toISOString(),
        finishedUtc: new Date().toISOString(),
        evidenceReference,
        threeDsExpectation: target.challengeCapability,
        paymentProvider: "OpenPay"
      });
    }
    catch (error) {
      rows.push({
        runId,
        runtimeTarget: target.key,
        tenantCode,
        challengeOutcome,
        journeyOutcome: error instanceof Error ? `failed: ${error.message}` : "failed",
        verificationOutcome: "skipped",
        cleanupOutcome: resolveCleanupOutcome(),
        startedUtc: tenantStartedAt.toISOString(),
        finishedUtc: new Date().toISOString(),
        evidenceReference,
        threeDsExpectation: target.challengeCapability,
        paymentProvider: "OpenPay"
      });

      if (!options.allowPartialExecution) {
        break;
      }
    }
  }

  const hasAnyReachableJourney = rows.some((row) => !row.journeyOutcome.startsWith("failed:"));

  let verificationSummary = "Verification skipped.";
  if (options.verify && !options.dryRun && hasAnyReachableJourney) {
    log(`Running verification for prefix ${runPrefix}.`);
    try {
      const verificationResult = await verificationAdapter.execute({
        runtimeTarget: target.key,
        runtime: target.runtime,
        environment: target.environment,
        profile: target.profile,
        runPrefix
      });

      verificationSummary = verificationResult.summary;
      for (const row of rows) {
        row.verificationOutcome = verificationResult.outcome;
      }

      await writeFile(
        path.join(reportDirectory, "verification-report.json"),
        JSON.stringify(verificationResult.rawReport ?? {}, null, 2),
        "utf8"
      );
    }
    catch (error) {
      verificationSummary = error instanceof Error ? error.message : "Verification failed unexpectedly.";
      for (const row of rows) {
        row.verificationOutcome = "failed";
      }
    }
  }
  else if (options.verify && !options.dryRun) {
    verificationSummary = "Verification skipped because no tenant journey reached the payment flow.";
    for (const row of rows) {
      row.verificationOutcome = "skipped";
    }
  }

  const markdownSummary = await reportComposer.compose(rows);
  const output: PaymentAutomationRunOutput = {
    runId,
    runPrefix,
    reportDirectory,
    rows,
    verificationSummary
  };

  await writeFile(path.join(reportDirectory, "summary.md"), markdownSummary, "utf8");
  await writeFile(path.join(reportDirectory, "summary.json"), JSON.stringify(output, null, 2), "utf8");

  if (options.autoStopLocalSessions !== false && target.runtime === "local" && !options.dryRun) {
    await stopLocalSessions(target.profile, log);
  }

  return output;
}

function resolveCleanupOutcome(): CleanupOutcome {
  return "reset";
}

async function withTimeout<T>(promise: Promise<T>, timeoutMs: number, message: string): Promise<T> {
  let timeoutHandle: NodeJS.Timeout | undefined;

  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        timeoutHandle = setTimeout(() => {
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

async function waitForTargetReadiness(
  targetUrl: string,
  ignoreHttpsErrors: boolean,
  log: (message: string) => void
): Promise<void> {
  const deadline = Date.now() + 30000;
  let reportedWait = false;

  while (Date.now() < deadline) {
    if (await isUrlReachable(targetUrl, ignoreHttpsErrors)) {
      return;
    }

    if (!reportedWait) {
      reportedWait = true;
      log(`Waiting for target readiness at ${targetUrl}.`);
    }

    await sleep(1000);
  }

  log(`Target readiness check timed out for ${targetUrl}; continuing with browser navigation.`);
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
      stdio: ["ignore", "pipe", "pipe"]
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk: Buffer | string) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk: Buffer | string) => {
      stderr += chunk.toString();
    });

    child.on("error", (error) => {
      reject(error);
    });

    child.on("exit", (exitCode) => {
      const combinedOutput = [stdout.trim(), stderr.trim()].filter(Boolean).join("\n");
      if (combinedOutput) {
        log(combinedOutput);
      }

      if (exitCode === 0) {
        resolve();
        return;
      }

      reject(new Error(`Automatic local ${profile} session stop exited with code ${exitCode}.`));
    });
  });
}