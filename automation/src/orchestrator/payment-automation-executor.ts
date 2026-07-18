import http from "node:http";
import https from "node:https";
import { spawn } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { CleanupOutcome } from "../contracts/payment-fixture-provisioner.js";
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

interface ExecutionItem {
  tenantCode: string;
  tenantTier: string;
  paymentProviderCode?: string | null;
  executionRunPrefix: string;
}

export async function executePaymentAutomationRun(
  options: ExecutePaymentAutomationRunOptions
): Promise<PaymentAutomationRunOutput> {
  const runtimeTargetCatalog = new JsonRuntimeTargetCatalog();
  const reportComposer = new FileReportComposer();
  const verificationAdapter = new PowerShellVerificationAdapter();
  const paymentJourneyRunner = new PaymentJourneyRunner();
  const log = options.logger ?? (() => undefined);
  log(`Resolving runtime target ${options.target}.`);
  const target = await runtimeTargetCatalog.resolve(options.target);
  log(`Resolved runtime target ${target.key} (${target.runtime}/${target.profile}).`);
  log(`Resolving tenant execution plan for ${options.target}.`);
  const tenantExecutionCatalog = !options.dryRun && target.expectedTenantSource === "runtime-configuration"
    ? new ApiTenantExecutionCatalog(target)
    : new StaticTenantExecutionCatalog();
  const tenantPlan = await tenantExecutionCatalog.resolve(
    options.tenantCodes,
    options.allowPartialExecution || target.supportsPartialExecution,
    log
  );
  log(`Resolved ${tenantPlan.resolvedTenants.length} tenant(s); skipped ${tenantPlan.skippedTenantCodes.length}.`);
  const resolvedTenants = applyTenantLimit(tenantPlan.resolvedTenants, options.tenantLimit, log);
  const startedAt = options.startedAt ?? new Date();
  const runId = `payment-automation-${startedAt.toISOString().replace(/[.:]/g, "-")}`;
  const runPrefix = options.runPrefix ?? buildRunPrefix(startedAt);
  const reportDirectory = path.join(options.reportDirectoryRoot ?? path.join(automationRoot, "reports"), runId);
  const executionItems = buildExecutionItems(
    resolvedTenants,
    normalizeRequestedProviders(options.requestedProviders ?? []),
    startedAt,
    runPrefix
  );

  await mkdir(reportDirectory, { recursive: true });
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

  for (const executionItem of executionItems) {
    const tenantStartedAt = new Date();
    log(`Starting tenant ${executionItem.tenantCode} (${executionItem.tenantTier}${executionItem.paymentProviderCode ? `, provider ${executionItem.paymentProviderCode}` : ""}).`);
    const customerOrderId = buildCustomerOrderId(
      executionItem.executionRunPrefix,
      executionItem.tenantCode,
      target.profile,
      target.runtime,
      executionItem.paymentProviderCode ?? undefined
    );
    const tenantDiagnosticsDirectory = path.join(
      reportDirectory,
      executionItem.tenantCode,
      normalizeProviderForPath(executionItem.paymentProviderCode ?? "resolved")
    );
    let journeyOutcome = options.dryRun ? "dry_run" : "failed";
    let challengeOutcome: ExecutiveSummaryRow["challengeOutcome"] = "not-applicable";
    let threeDsSetting: ExecutiveSummaryRow["threeDsSetting"] = "unknown";
    let paymentProvider = executionItem.paymentProviderCode ?? "unresolved";
    let verificationOutcome = options.verify && !options.dryRun ? "pending" : "skipped";
    let cleanupOutcome = resolveCleanupOutcome();
    let evidenceReference = `customerOrderId:${customerOrderId} | runPrefix:${executionItem.executionRunPrefix}`;
    let fixtureIds: string[] = [];
    let provisioner: PaymentFixtureProvisioner | undefined;
    let stopAfterCurrentItem = false;

    try {
      if (!options.dryRun && executionItem.paymentProviderCode) {
        provisioner = new PowerShellPaymentProviderProvisioner({
          target,
          requestedProvider: executionItem.paymentProviderCode,
          logger: (message) => {
            log(`[${executionItem.tenantCode}/${executionItem.paymentProviderCode}] ${message}`);
          }
        });

        const fixturePrepareResult = await provisioner.prepare(executionItem.tenantCode);
        fixtureIds = fixturePrepareResult.fixtureIds;
        evidenceReference = `${evidenceReference} | baseline:${fixturePrepareResult.baselineName}`;
      }

      if (!options.dryRun) {
        log(
          `Running tenant ${executionItem.tenantCode} (tier ${executionItem.tenantTier}${executionItem.paymentProviderCode ? `, provider ${executionItem.paymentProviderCode}` : ""}) and order id ${customerOrderId}.`
        );
        const journeyResult = await withTimeout(
          paymentJourneyRunner.execute({
            tenantCode: executionItem.tenantCode,
            target,
            customerOrderId,
            sandboxOtpCode: options.sandboxOtpCode,
            headless: options.headless,
            requestedProvider: executionItem.paymentProviderCode ?? undefined,
            diagnosticsDirectory: tenantDiagnosticsDirectory,
            logger: (message) => {
              log(`[${executionItem.tenantCode}] ${message}`);
            }
          }),
          options.tenantTimeoutMs,
          `Tenant ${executionItem.tenantCode} exceeded ${options.tenantTimeoutMs}ms.`
        );

        journeyOutcome = journeyResult.journeyOutcome;
        challengeOutcome = journeyResult.challengeOutcome;
        threeDsSetting = journeyResult.threeDsSetting;
        paymentProvider = journeyResult.paymentProvider;
        evidenceReference = `${customerOrderId} -> ${journeyResult.finalUrl}`;

        if (options.verify) {
          try {
            if (target.runtime === "docker") {
              await new Promise((resolve) => setTimeout(resolve, 15000));
            }

            const verificationResult = await verificationAdapter.execute({
              runtimeTarget: target.key,
              runtime: target.runtime,
              environment: target.environment,
              profile: target.profile,
              runPrefix: executionItem.executionRunPrefix
            });

            verificationOutcome = verificationResult.outcome;
            verificationSummaries.push(verificationResult.summary);

            const verifiedThreeDsSetting = verificationResult.threeDsByTenant?.[executionItem.tenantCode];
            if (verifiedThreeDsSetting) {
              threeDsSetting = verifiedThreeDsSetting;
            }

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
            verificationOutcome = "skipped";
            const verificationMessage = error instanceof Error ? error.message : "Verification failed.";
            verificationSummaries.push(`Verification skipped for ${executionItem.tenantCode}: ${verificationMessage}`);
            log(`[${executionItem.tenantCode}] Verification skipped: ${verificationMessage}`);
          }
        }
      }
    }
    catch (error) {
      journeyOutcome = error instanceof Error ? `failed: ${error.message}` : "failed";
      verificationOutcome = "skipped";
      if (!options.allowPartialExecution) {
        stopAfterCurrentItem = true;
      }
    }
    finally {
      if (provisioner) {
        try {
          const fixtureCleanupResult = await provisioner.cleanup(executionItem.tenantCode, fixtureIds);
          cleanupOutcome = fixtureCleanupResult.outcome;
        }
        catch (error) {
          cleanupOutcome = "manual-review";
          const cleanupMessage = error instanceof Error ? error.message : "Cleanup failed.";
          evidenceReference = `${evidenceReference} | cleanup:${cleanupMessage}`;
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
        startedUtc: tenantStartedAt.toISOString(),
        finishedUtc: new Date().toISOString(),
        evidenceReference,
        threeDsSetting,
        paymentProvider
      });

      log(
        `Tenant summary: ${executionItem.tenantCode} | provider=${paymentProvider} | tier=${executionItem.tenantTier} | journey=${journeyOutcome} | verification=${verificationOutcome} | cleanup=${cleanupOutcome}.`
      );
    }

    if (stopAfterCurrentItem) {
      log(`Stopping after tenant ${executionItem.tenantCode} due to failure and partial execution disabled.`);
      break;
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
    verificationSummary
  };

  await writeFile(path.join(reportDirectory, "summary.md"), markdownSummary, "utf8");
  await writeFile(path.join(reportDirectory, "summary.json"), JSON.stringify(output, null, 2), "utf8");

  if (options.autoStopLocalSessions !== false && target.runtime === "local" && !options.dryRun) {
    await stopLocalSessions(target.profile, log);
  }

  return output;
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

function resolveCleanupOutcome(): CleanupOutcome {
  return "reset";
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
      paymentProviderCode: tenant.paymentProviderCode,
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
        paymentProviderCode: requestedProvider,
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
      profile
    ], {
      cwd: path.resolve(automationRoot, ".."),
      stdio: ["ignore", "pipe", "pipe"]
    });

    let settled = false;
    let stdout = "";
    let stderr = "";

    const finalizeReady = () => {
      if (settled) {
        return;
      }

      settled = true;
      resolve();
    };

    child.stdout.on("data", (chunk: Buffer | string) => {
      const text = chunk.toString();
      stdout += text;

      if (text.includes("Local '") || text.includes("profile is running.")) {
        finalizeReady();
      }
    });

    child.stderr.on("data", (chunk: Buffer | string) => {
      stderr += chunk.toString();
    });

    child.on("error", (error) => {
      if (!settled) {
        settled = true;
        reject(error);
      }
    });

    child.on("exit", (exitCode) => {
      if (settled) {
        return;
      }

      settled = true;
      const combinedOutput = [stdout.trim(), stderr.trim()].filter(Boolean).join("\n");
      reject(new Error(combinedOutput || `Local ${profile} profile exited unexpectedly with code ${exitCode}.`));
    });

    setTimeout(() => {
      finalizeReady();
    }, 3000);
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
