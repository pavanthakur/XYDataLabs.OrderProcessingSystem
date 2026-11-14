import { mkdir, readFile, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { JsonRuntimeTargetCatalog } from "../catalog/json-runtime-target-catalog.js";
import type { PaymentAutomationRunOutput } from "../orchestrator/payment-automation-executor.js";
import { executePaymentAutomationRun } from "../orchestrator/payment-automation-executor.js";
import { FileReportComposer } from "../report/file-report-composer.js";
import { buildRunPrefix } from "../support/customer-order-id.js";
import { resolveEnvironmentKey } from "../support/environment-key.js";

interface AzureMatrixOptions {
  targets: string[];
  tenantCodes: string[];
  requestedProviders: string[];
  allowPartialExecution: boolean;
  dryRun: boolean;
  headless: boolean;
  verify: boolean;
  sandboxOtpCode: string;
  tenantTimeoutMs: number;
  tenantLimit: number | null;
  operatorAssistedEntra: boolean;
  authPreflightOnly: boolean;
  servicePreflightOnly: boolean;
}

interface AzureMatrixOutput {
  matrixRunId: string;
  reportDirectory: string;
  environmentKey: string;
  startedUtc: string;
  finishedUtc: string;
  startedIst: string;
  finishedIst: string;
  currentStep?: string;
  status?: "running" | "passed" | "preflight-passed" | "failed";
  executionMode: "payment-matrix" | "auth-preflight-only" | "service-preflight-only";
  targetCount: number;
  targets: string[];
  servicePreflights: Array<{ target: string; status: string; reportPath: string }>;
  targetRuns: PaymentAutomationRunOutput[];
}

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const automationRoot = path.resolve(currentDirectory, "../..");
const workspaceRoot = path.resolve(automationRoot, "..");

function formatIstTimestamp(date: Date): string {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone: "Asia/Kolkata",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    fractionalSecondDigits: 3,
    hour12: false
  }).format(date).replace(" ", "T") + "+05:30";
}

async function main(): Promise<void> {
  const options = parseCliOptions(process.argv.slice(2));
  const startedAt = new Date();
  const matrixRunId = `payment-automation-azure-matrix-${startedAt.toISOString().replace(/[.:]/g, "-")}`;
  const reportComposer = new FileReportComposer();
  const runtimeTargetCatalog = new JsonRuntimeTargetCatalog();
  const resolvedTargets = await Promise.all(options.targets.map((target) => runtimeTargetCatalog.resolve(target)));
  const invalidTargets = resolvedTargets.filter((target) =>
    target.runtime !== "azure" || target.expectedTenantSource !== "runtime-configuration"
  );
  if (invalidTargets.length > 0) {
    throw new Error(
      "Azure payment matrix targets must be Azure runtime targets with expectedTenantSource=runtime-configuration in automation/config/runtime-targets.json. " +
      `Invalid targets: ${invalidTargets.map((target) => `${target.key}(${target.runtime}/${target.expectedTenantSource})`).join(", ")}.`
    );
  }

  const environmentKey = resolvedTargets.length === 1
    ? resolveEnvironmentKey(resolvedTargets[0])
    : "azure-https";
  const playwrightRoot = path.join(workspaceRoot, "TestResults", "Playwright");
  const environmentRoot = path.join(playwrightRoot, environmentKey);
  const reportDirectory = path.join(environmentRoot, matrixRunId);
  const latestPointerPath = path.join(environmentRoot, "latest-playwright-matrix.txt");
  const rootMarkerPath = path.join(playwrightRoot, "latest-playwright-run.txt");
  const runPlanPath = path.join(reportDirectory, "run-plan.txt");
  const startupLogPath = path.join(reportDirectory, "startup.log");
  const progressLogPath = path.join(reportDirectory, "progress.log");
  const currentStepPath = path.join(reportDirectory, "current-step.txt");
  const normalizedProviders = normalizeRequestedProviders(options.requestedProviders);
  if (normalizedProviders.length > 0) {
    throw new Error(
      "Azure payment automation follows each tenant's authoritative provider assignment. " +
      "Provider overrides are not supported by the promotion workflow; update the runtime target/deployment configuration instead."
    );
  }
  const effectiveProviders: string[] = [];
  const matrixOutput: AzureMatrixOutput = {
    matrixRunId,
    reportDirectory,
    environmentKey,
    startedUtc: startedAt.toISOString(),
    finishedUtc: startedAt.toISOString(),
    startedIst: formatIstTimestamp(startedAt),
    finishedIst: formatIstTimestamp(startedAt),
    status: "running",
    executionMode: options.servicePreflightOnly ? "service-preflight-only" : options.authPreflightOnly ? "auth-preflight-only" : "payment-matrix",
    targetCount: 0,
    targets: options.targets,
    servicePreflights: [],
    targetRuns: []
  };

  await mkdir(reportDirectory, { recursive: true });
  await mkdir(path.dirname(latestPointerPath), { recursive: true });
  await mkdir(path.dirname(rootMarkerPath), { recursive: true });
  await writeFile(latestPointerPath, `${reportDirectory}\n`, "utf8");
  await writeFile(rootMarkerPath, `${reportDirectory}\n`, "utf8");
  await writeFile(runPlanPath, [
    options.servicePreflightOnly ? "Azure service access preflight run" : options.authPreflightOnly ? "Azure Entra authorization preflight run" : "Azure payment automation matrix run",
    "Goal: confirm Azure target discovery and browser automation flow for every active tenant using the provider resolved from runtime configuration.",
    `Environment: ${environmentKey}`,
    "Runtime target config: automation/config/runtime-targets.json",
    `Targets: ${options.targets.join(", ")}`,
    "Provider selection: runtime configuration -> tenant registry API (no override)",
    `Tenant selection: ${options.tenantCodes.length > 0 ? options.tenantCodes.join(", ") : "runtime default"}`,
    `Tenant limit: ${options.tenantLimit ?? "none"}`,
    `Dry run: ${options.dryRun ? "yes" : "no"}`,
    `Execution mode: ${options.servicePreflightOnly ? "service access preflight only (no browser, order, or payment mutations)" : options.authPreflightOnly ? "Entra authorization preflight only (no order/payment mutations)" : "payment matrix"}`,
    `Verification: ${options.verify ? "yes" : "no"}`,
    "",
    "Stages:",
    "1. Create the run folder and latest pointer files.",
    "2. Resolve the runtime target and tenant plan.",
    options.servicePreflightOnly ? "3. Stop after the no-payment dependency preflight (including temporary SQL firewall lease creation and cleanup); do not start browser automation." : "3. Execute each tenant/provider item in order.",
    "4. Write summary.json and summary.md at the end."
  ].join("\n"), "utf8");
  await writeFile(startupLogPath, [
    `[${formatIstTimestamp(new Date())}] Matrix startup`,
    `environment=${environmentKey}`,
    "runtimeTargetConfig=automation/config/runtime-targets.json",
    `targets=${options.targets.join(",")}`,
    "providerSelection=runtime-configuration-tenant-registry",
    `tenantCodes=${options.tenantCodes.length > 0 ? options.tenantCodes.join(",") : "runtime default"}`,
    `tenantLimit=${options.tenantLimit ?? "none"}`,
    `dryRun=${options.dryRun}`,
    `verify=${options.verify}`,
    `state=created-run-folder`
  ].join("\n") + "\n", "utf8");
  await writeFile(progressLogPath, "Matrix progress log initialized.\n", "utf8");
  await writeFile(currentStepPath, "initialized\n", "utf8");
  await writeFile(path.join(reportDirectory, "summary.json"), JSON.stringify({ ...matrixOutput, status: "running" }, null, 2), "utf8");
  await writeRunMessage(startupLogPath, progressLogPath, `Starting azure payment matrix ${matrixRunId}.`);

  const targetRuns: PaymentAutomationRunOutput[] = [];
  for (const [index, target] of options.targets.entries()) {
    const targetStart = new Date(startedAt.getTime() + (index * 1000));
    const targetRunPrefix = buildRunPrefix(targetStart);
    matrixOutput.currentStep = `target:${target}`;
    await writeFile(path.join(reportDirectory, "summary.json"), JSON.stringify({ ...matrixOutput, status: "running" }, null, 2), "utf8");
    await writeFile(currentStepPath, `${matrixOutput.currentStep}\n`, "utf8");
    await writeRunMessage(startupLogPath, progressLogPath, `Executing target ${target} with prefix ${targetRunPrefix}.`);

    const runtimeTarget = resolvedTargets[index];

    await writeRunMessage(startupLogPath, progressLogPath, `[${formatIstTimestamp(new Date())}] target=${target} state=resolved-target runtime=${runtimeTarget.runtime} profile=${runtimeTarget.profile} expectedTenantSource=${runtimeTarget.expectedTenantSource}`);
    if (!options.dryRun) {
      const environment = runtimeTarget.environment;
      const safeTarget = target.replace(/[^a-z0-9_-]/gi, "-");
      const preflightPath = path.join(reportDirectory, `verification-preflight-${safeTarget}.json`);
      await writeRunMessage(startupLogPath, progressLogPath, `[${formatIstTimestamp(new Date())}] target=${target} state=verification-service-preflight-started mode=${options.operatorAssistedEntra ? "Entra" : "KeyVault"}`);
      try {
        const preflight = await runAzureVerificationServicePreflight({
          environment,
          sqlAuthenticationMode: options.operatorAssistedEntra ? "Entra" : "KeyVault",
          reportPath: preflightPath,
          runId: process.env.GITHUB_RUN_ID ?? matrixRunId,
          attempt: process.env.GITHUB_RUN_ATTEMPT ?? "1"
        });
        matrixOutput.servicePreflights.push({ target, status: preflight.status, reportPath: path.relative(workspaceRoot, preflightPath).replaceAll(path.sep, "/") });
        await writeRunMessage(startupLogPath, progressLogPath, `[${formatIstTimestamp(new Date())}] target=${target} state=verification-service-preflight-passed tenants=${preflight.tenantCount}`);
      } catch {
        matrixOutput.servicePreflights.push({ target, status: "FAIL", reportPath: path.relative(workspaceRoot, preflightPath).replaceAll(path.sep, "/") });
        matrixOutput.finishedUtc = new Date().toISOString();
        matrixOutput.finishedIst = formatIstTimestamp(new Date());
        matrixOutput.currentStep = `preflight-failed:${target}`;
        matrixOutput.status = "failed";
        await writeFile(path.join(reportDirectory, "summary.json"), JSON.stringify(matrixOutput, null, 2), "utf8");
        await writeFile(path.join(reportDirectory, "summary.md"), [
          options.servicePreflightOnly ? "# Azure Service Access Preflight (No Payment)" : options.authPreflightOnly ? "# Azure Entra Authorization Preflight (No Payment)" : "# Azure Payment Automation Matrix",
          "",
          `Status: ${matrixOutput.status}`,
          "",
          "## Verification service preflight",
          "",
          `FAIL — ${target}. No browser payment journey was started. See ${path.basename(preflightPath)} and the preflight step log.`
        ].join("\n"), "utf8");
        await writeFile(currentStepPath, `${matrixOutput.currentStep}\n`, "utf8");
        await writeRunMessage(startupLogPath, progressLogPath, `[${formatIstTimestamp(new Date())}] target=${target} state=verification-service-preflight-failed; payment execution blocked`);
        throw new Error(`Azure verification service preflight failed for ${target}; payment execution was not started.`);
      }
      if (options.servicePreflightOnly) {
        await writeRunMessage(startupLogPath, progressLogPath, `[${formatIstTimestamp(new Date())}] target=${target} state=service-preflight-only-complete; browser and payment automation skipped`);
        continue;
      }
    }
    const run = await executePaymentAutomationRun({
      target,
      tenantCodes: options.tenantCodes,
      requestedProviders: effectiveProviders,
      allowPartialExecution: options.allowPartialExecution,
      dryRun: options.dryRun,
      headless: options.headless,
      verify: options.verify,
      operatorAssistedEntra: options.operatorAssistedEntra,
      authPreflightOnly: options.authPreflightOnly,
      sandboxOtpCode: options.sandboxOtpCode,
      tenantTimeoutMs: options.tenantTimeoutMs,
      tenantLimit: options.tenantLimit ?? undefined,
      reportDirectoryRoot: environmentRoot,
      startedAt: targetStart,
      runPrefix: targetRunPrefix,
      logger: (message) => {
        void writeRunMessage(startupLogPath, progressLogPath, `[${target}] ${message}`).catch(() => undefined);
      }
    });

    targetRuns.push(run);
    await writeRunMessage(startupLogPath, progressLogPath, `[${formatIstTimestamp(new Date())}] target=${target} state=completed-automation-run`);
  }

  const rows = targetRuns.flatMap((targetRun) => targetRun.rows);
  const markdownSummary = await reportComposer.compose(rows);
  const hasFailures = targetRuns.some((targetRun) =>
    targetRun.rows.some((row) => {
      const journeyFailed = options.authPreflightOnly
        ? row.journeyOutcome !== "auth-preflight-passed"
        : !row.journeyOutcome.startsWith("completed") && row.journeyOutcome !== "dry_run";
      const verificationFailed = !options.authPreflightOnly && options.verify && !options.dryRun && row.verificationOutcome !== "passed";
      return journeyFailed || verificationFailed;
    })
  );
  matrixOutput.finishedUtc = new Date().toISOString();
  matrixOutput.finishedIst = formatIstTimestamp(new Date());
  matrixOutput.currentStep = "completed";
  matrixOutput.status = hasFailures ? "failed" : (options.authPreflightOnly || options.servicePreflightOnly) ? "preflight-passed" : "passed";
  matrixOutput.targetCount = options.servicePreflightOnly ? matrixOutput.servicePreflights.length : targetRuns.length;
  matrixOutput.targetRuns = targetRuns;

  const targetSections: string[] = [];
  for (const targetRun of targetRuns) {
    const runtimeTarget = targetRun.rows[0]?.runtimeTarget ?? "unknown";
    targetSections.push(`### ${runtimeTarget} (prefix: ${targetRun.runPrefix})`);
    targetSections.push("");
    targetSections.push("| Tenant | Provider | Journey | Challenge | Verification | Cleanup |");
    targetSections.push("|---|---|---|---|---|---|");
    for (const row of targetRun.rows) {
      targetSections.push(
        `| ${row.tenantCode} | ${row.paymentProvider} | ${row.journeyOutcome} | ${row.challengeOutcome} | ${row.verificationOutcome} | ${row.cleanupOutcome} |`
      );
    }
    if (targetRun.rows.length === 0) {
      targetSections.push("| — | — | no tenants ran | — | — | — |");
    }
    const cleanVerificationSummary = stripAnsiCodes(targetRun.verificationSummary);
    if (cleanVerificationSummary && cleanVerificationSummary !== "Verification skipped.") {
      targetSections.push("");
      for (const segment of cleanVerificationSummary.split(" | ")) {
        const trimmed = segment.trim();
        if (trimmed) {
          targetSections.push(`> ${trimmed}`);
        }
      }
    }
    targetSections.push("");
  }

  await writeFile(
    path.join(reportDirectory, "summary.md"),
    [
      options.servicePreflightOnly ? "# Azure Service Access Preflight (No Payment)" : options.authPreflightOnly ? "# Azure Entra Authorization Preflight (No Payment)" : "# Azure Payment Automation Matrix",
      "",
      `Started: ${matrixOutput.startedUtc}`,
      `Finished: ${matrixOutput.finishedUtc}`,
      `Started IST: ${matrixOutput.startedIst}`,
      `Finished IST: ${matrixOutput.finishedIst}`,
      `Status: ${matrixOutput.status}`,
      "",
      "## Verification service preflights",
      "",
      "| Target | Status | Evidence |",
      "|---|---|---|",
      ...matrixOutput.servicePreflights.map((item) => `| ${item.target} | ${item.status} | ${item.reportPath} |`),
      "",
      "## Target Runs",
      "",
      ...targetSections,
      "",
      markdownSummary
    ].join("\n"),
    "utf8"
  );
  await writeFile(path.join(reportDirectory, "summary.json"), JSON.stringify(matrixOutput, null, 2), "utf8");
  await writeFile(currentStepPath, "completed\n", "utf8");
  await writeFile(latestPointerPath, `${reportDirectory}\n`, "utf8");
  await writeFile(rootMarkerPath, `${reportDirectory}\n`, "utf8");
  await writeRunMessage(startupLogPath, progressLogPath, `[${formatIstTimestamp(new Date())}] state=completed-matrix`);

  process.stdout.write(`${JSON.stringify(matrixOutput, null, 2)}\n`);

  if (hasFailures) {
    throw new Error("Azure payment matrix completed with failed tenant journey(s).");
  }
}

async function writeRunMessage(startupLogPath: string, progressLogPath: string, line: string): Promise<void> {
  process.stdout.write(`${line}\n`);
  await writeFile(progressLogPath, `${line}\n`, { flag: "a" });
  await writeFile(startupLogPath, `${line}\n`, { flag: "a" });
}

async function runAzureVerificationServicePreflight(input: {
  environment: string;
  sqlAuthenticationMode: "Entra" | "KeyVault";
  reportPath: string;
  runId: string;
  attempt: string;
}): Promise<{ status: string; tenantCount: number }> {
  const allowedEnvironments = new Set(["dev", "staging", "stg", "prod"]);
  if (!allowedEnvironments.has(input.environment)) {
    throw new Error(`Unsupported Azure preflight environment: ${input.environment}`);
  }

  const scriptPath = path.join(workspaceRoot, "scripts", "verify-payment-run-azure.ps1");
  const argumentsList = [
    "-NoProfile",
    "-File", scriptPath,
    "-Environment", input.environment,
    "-SqlAuthenticationMode", input.sqlAuthenticationMode,
    "-PreflightOnly",
    "-PreflightReportPath", input.reportPath,
    "-OutputFormat", "Json"
  ];

  const exitCode = await new Promise<number>((resolve) => {
    const child = spawn("pwsh", argumentsList, {
      cwd: workspaceRoot,
      env: {
        ...process.env,
        PHASE10_FIREWALL_RUN_ID: input.runId,
        PHASE10_FIREWALL_RUN_ATTEMPT: input.attempt
      },
      stdio: "ignore"
    });
    child.once("error", () => resolve(-1));
    child.once("close", (code) => resolve(code ?? -1));
  });

  if (exitCode !== 0 && !(await fileExists(input.reportPath))) {
    const failure = {
      schemaVersion: "phase10-azure-verification-preflight-v1",
      status: "FAIL",
      environment: input.environment,
      sourceRevision: "UNKNOWN",
      sourceDirty: "UNKNOWN",
      checks: [{ service: "Preflight initialization", status: "FAIL", detail: "Verifier exited before writing structured results. No browser journey or payment was started." }]
    };
    await mkdir(path.dirname(input.reportPath), { recursive: true });
    await writeFile(input.reportPath, JSON.stringify(failure, null, 2), "utf8");
    await writeFile(path.join(path.dirname(input.reportPath), `${path.basename(input.reportPath, ".json")}.md`), [
      "# Azure Verification Preflight",
      "",
      "- Status: **FAIL**",
      `- Environment: ${input.environment}`,
      "- Detail: verifier exited before writing structured results. No browser journey or payment was started."
    ].join("\n"), "utf8");
  }

  if (!(await fileExists(input.reportPath))) {
    throw new Error("Azure verification preflight did not produce a structured report.");
  }
  const report = JSON.parse(await readFile(input.reportPath, "utf8")) as { status?: string; tenantCount?: number };
  if (exitCode !== 0 || report.status !== "PASS") {
    throw new Error("Azure verification service preflight failed; no browser payment journey was started.");
  }
  return { status: report.status, tenantCount: report.tenantCount ?? 0 };
}

async function fileExists(filePath: string): Promise<boolean> {
  try {
    await readFile(filePath);
    return true;
  } catch {
    return false;
  }
}

// eslint-disable-next-line no-control-regex
const ansiCodePattern = /\x1B\[[0-9;]*[mGKHF]/g;

function stripAnsiCodes(text: string): string {
  return text.replace(ansiCodePattern, "");
}

function parseCliOptions(argumentsList: string[]): AzureMatrixOptions {
  const targets: string[] = [];
  const tenantCodes: string[] = [];
  const requestedProviders: string[] = [];
  let allowPartialExecution = false;
  let dryRun = false;
  let headless = true;
  let verify = true;
  let sandboxOtpCode = "999";
  let tenantTimeoutMs = 180000;
  let tenantLimit: number | null = null;
  let operatorAssistedEntra = false;
  let authPreflightOnly = false;
  let servicePreflightOnly = false;

  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = argumentsList[index];

    switch (argument) {
      case "--target":
        if (argumentsList[index + 1]) {
          targets.push(argumentsList[index + 1]);
        }
        index += 1;
        break;
      case "--tenant":
        if (argumentsList[index + 1]) {
          tenantCodes.push(argumentsList[index + 1]);
        }
        index += 1;
        break;
      case "--provider":
        if (argumentsList[index + 1]) {
          requestedProviders.push(argumentsList[index + 1]);
        }
        index += 1;
        break;
      case "--allow-partial":
        allowPartialExecution = true;
        break;
      case "--dry-run":
        dryRun = true;
        verify = false;
        break;
      case "--headed":
        headless = false;
        break;
      case "--operator-assisted-entra":
        operatorAssistedEntra = true;
        break;
      case "--auth-preflight-only":
        authPreflightOnly = true;
        break;
      case "--service-preflight-only":
        servicePreflightOnly = true;
        break;
      case "--skip-verification":
        verify = false;
        break;
      case "--sandbox-otp":
        sandboxOtpCode = argumentsList[index + 1] ?? sandboxOtpCode;
        index += 1;
        break;
      case "--tenant-timeout-ms":
        tenantTimeoutMs = Number(argumentsList[index + 1] ?? tenantTimeoutMs);
        index += 1;
        break;
      case "--tenant-limit":
        tenantLimit = Number(argumentsList[index + 1] ?? tenantLimit);
        index += 1;
        break;
      default:
        break;
    }
  }

  const normalizedTargets = targets.length > 0
    ? Array.from(new Set(targets.map((target) => target.trim()).filter(Boolean)))
    : [
      "azure-dev",
      "azure-stg",
      "azure-prod"
    ];

  if (operatorAssistedEntra && (headless || normalizedTargets.length !== 1 || normalizedTargets[0] !== "azure-dev" || (authPreflightOnly ? tenantCodes.length > 1 : tenantCodes.length < 1))) {
    throw new Error("--operator-assisted-entra requires --headed and exactly --target azure-dev; payment mode requires one or more explicit --tenant values, while auth-preflight-only accepts zero or one. It cannot run against staging or production.");
  }
  if (operatorAssistedEntra && new Set(tenantCodes.map((code) => code.toLowerCase())).size !== tenantCodes.length) {
    throw new Error("--operator-assisted-entra does not accept duplicate --tenant values.");
  }
  if (authPreflightOnly && !operatorAssistedEntra) {
    throw new Error("--auth-preflight-only requires --operator-assisted-entra; it never creates an order or submits a payment.");
  }
  if (servicePreflightOnly && (operatorAssistedEntra || authPreflightOnly || dryRun || normalizedTargets.length !== 1 || normalizedTargets[0] !== "azure-dev" || tenantCodes.length > 0 || requestedProviders.length > 0)) {
    throw new Error("--service-preflight-only is a hosted, no-payment dependency check that may create and remove a temporary SQL firewall lease; use exactly --target azure-dev without tenant/provider filters, dry-run, or operator-assisted browser authentication.");
  }
  if (operatorAssistedEntra) tenantTimeoutMs = Math.max(tenantTimeoutMs, 420000);

  return {
    targets: normalizedTargets,
    tenantCodes,
    requestedProviders,
    allowPartialExecution,
    dryRun,
    headless,
    verify,
    sandboxOtpCode,
    tenantTimeoutMs,
    tenantLimit,
    operatorAssistedEntra,
    authPreflightOnly,
    servicePreflightOnly
  };
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

void main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : "Azure payment matrix runner failed.";
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
});
