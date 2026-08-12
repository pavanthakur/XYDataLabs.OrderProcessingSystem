import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { JsonRuntimeTargetCatalog } from "../catalog/json-runtime-target-catalog.js";
import type { ExecutePaymentAutomationRunOptions, PaymentAutomationRunOutput } from "../orchestrator/payment-automation-executor.js";
import { executePaymentAutomationRun, startLocalProfile } from "../orchestrator/payment-automation-executor.js";
import { FileReportComposer } from "../report/file-report-composer.js";
import { buildRunPrefix } from "../support/customer-order-id.js";
import { resolveEnvironmentKey } from "../support/environment-key.js";

interface LocalMatrixOptions {
  targets: string[];
  tenantCodes: string[];
  requestedProviders: string[];
  allowPartialExecution: boolean;
  dryRun: boolean;
  headless: boolean;
  verify: boolean;
  sandboxOtpCode: string;
  tenantTimeoutMs: number;
  autoStopLocalSessions: boolean;
  tenantLimit: number | null;
}

interface LocalMatrixOutput {
  matrixRunId: string;
  reportDirectory: string;
  environmentKey: string;
  startedUtc: string;
  finishedUtc: string;
  startedIst: string;
  finishedIst: string;
  currentStep?: string;
  status?: "running" | "passed" | "failed";
  targetCount: number;
  targets: string[];
  targetRuns: PaymentAutomationRunOutput[];
}

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const automationRoot = path.resolve(currentDirectory, "../..");
const workspaceRoot = path.resolve(automationRoot, "..");
const statusWriterPath = path.join(workspaceRoot, "scripts", "write-playwright-run-status.ps1");
const defaultEnvironmentKey = "local-http";
const phase10RunRoot = process.env.PHASE10_RUN_ROOT?.trim();

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

function formatIstStamp(date: Date): string {
  return formatIstTimestamp(date).replace(/[:+,]/g, "-").replace(/\./g, "-");
}

async function main(): Promise<void> {
  const options = parseCliOptions(process.argv.slice(2));
  const startedAt = new Date();
  const matrixRunId = `payment-automation-local-matrix-${formatIstStamp(startedAt)}_matrix`;
  const runtimeTargetCatalog = new JsonRuntimeTargetCatalog();
  const normalizedProviders = normalizeRequestedProviders(options.requestedProviders);
  const effectiveProviders = normalizedProviders.length > 0
    ? normalizedProviders
    : getDefaultMatrixProviders();
  const environmentKey = options.targets.length === 1
    ? resolveEnvironmentKey(await runtimeTargetCatalog.resolve(options.targets[0]))
    : defaultEnvironmentKey;
  const playrightRoot = path.join(workspaceRoot, "TestResults", "Playwright");
  const environmentRoot = phase10RunRoot
    ? path.join(phase10RunRoot, "matrix")
    : path.join(playrightRoot, environmentKey);
  const reportDirectory = path.join(environmentRoot, matrixRunId);
  const latestPointerPath = path.join(environmentRoot, "latest-playwright-matrix.txt");
  const rootMarkerPath = path.join(playrightRoot, "latest-playwright-run.txt");
  const runPlanPath = path.join(reportDirectory, "run-plan.txt");
  const startupLogPath = path.join(reportDirectory, "startup.log");
  const progressLogPath = path.join(reportDirectory, "progress.log");
  const currentStepPath = path.join(reportDirectory, "current-step.txt");
  const reportComposer = new FileReportComposer();
  const matrixOutput: LocalMatrixOutput = {
    matrixRunId,
    reportDirectory,
    environmentKey,
    startedUtc: startedAt.toISOString(),
    finishedUtc: startedAt.toISOString(),
    startedIst: formatIstTimestamp(startedAt),
    finishedIst: formatIstTimestamp(startedAt),
    status: "running",
    targetCount: 0,
    targets: options.targets,
    targetRuns: []
  };

  await mkdir(reportDirectory, { recursive: true });
  await mkdir(path.dirname(latestPointerPath), { recursive: true });
  await mkdir(path.dirname(rootMarkerPath), { recursive: true });
  await writeFile(latestPointerPath, `${reportDirectory}\n`, "utf8");
  await writeFile(rootMarkerPath, `${reportDirectory}\n`, "utf8");
  try {
    await appendStatus(environmentKey, "local-http-matrix", "started", `runDir=${reportDirectory}`);
    await writeFile(runPlanPath, [
    "Local HTTP matrix sanity run",
    "Goal: confirm local tenant/provider discovery and browser/payment execution across the active matrix.",
    `Environment: ${environmentKey}`,
    `Targets: ${options.targets.join(", ")}`,
    `Requested providers: ${effectiveProviders.join(", ")}`,
    `Tenant limit: ${options.tenantLimit ?? "none"}`,
    `Dry run: ${options.dryRun ? "yes" : "no"}`,
    `Verification: ${options.verify ? "yes" : "no"}`,
    `Auto-stop local sessions: ${options.autoStopLocalSessions ? "yes" : "no"}`,
    "",
    "Stages:",
    "1. Create the run folder and latest pointer files.",
    "2. Resolve the runtime target and tenant plan.",
    "3. Start the local profile if needed.",
    "4. Execute each tenant/provider item in order.",
    "5. Write summary.json and summary.md at the end."
  ].join("\n"), "utf8");
  await writeFile(startupLogPath, [
    `[${formatIstTimestamp(new Date())}] Matrix startup`,
    `environment=${environmentKey}`,
    `targets=${options.targets.join(",")}`,
    `requestedProviders=${effectiveProviders.join(",")}`,
    `tenantLimit=${options.tenantLimit ?? "none"}`,
    `dryRun=${options.dryRun}`,
    `verify=${options.verify}`,
    `autoStopLocalSessions=${options.autoStopLocalSessions}`,
    `state=created-run-folder`
  ].join("\n") + "\n", "utf8");
  await writeFile(progressLogPath, "Matrix progress log initialized.\n", "utf8");
  matrixOutput.currentStep = "initialized";
  await writeFile(path.join(reportDirectory, "summary.json"), JSON.stringify({ ...matrixOutput, status: "running" }, null, 2), "utf8");
  await writeFile(currentStepPath, "initialized\n", "utf8");
  await writeRunMessage(startupLogPath, progressLogPath, `Starting local payment matrix ${matrixRunId}.`);

  const targetRuns: PaymentAutomationRunOutput[] = [];
  for (const [index, target] of options.targets.entries()) {
    const targetStart = new Date(startedAt.getTime() + (index * 1000));
    const targetRunPrefix = buildRunPrefix(targetStart);
    matrixOutput.currentStep = `target:${target}`;
    await writeFile(path.join(reportDirectory, "summary.json"), JSON.stringify({ ...matrixOutput, status: "running" }, null, 2), "utf8");
    await writeFile(currentStepPath, `${matrixOutput.currentStep}\n`, "utf8");
    await writeRunMessage(startupLogPath, progressLogPath, `Executing target ${target} with prefix ${targetRunPrefix}.`);
    await writeRunMessage(startupLogPath, progressLogPath, `[${formatIstTimestamp(new Date())}] target=${target} state=starting-target`);
    await writeFile(
      path.join(reportDirectory, `progress-${index + 1}-${target}.txt`),
      `Starting ${target} at ${formatIstTimestamp(new Date())}\n`,
      "utf8"
    );

    const runtimeTarget = await runtimeTargetCatalog.resolve(target);
    await writeRunMessage(startupLogPath, progressLogPath, `[${formatIstTimestamp(new Date())}] target=${target} state=resolved-target runtime=${runtimeTarget.runtime} profile=${runtimeTarget.profile}`);
    if (!options.dryRun && runtimeTarget.runtime === "local") {
      await writeRunMessage(startupLogPath, progressLogPath, `[${formatIstTimestamp(new Date())}] target=${target} state=starting-local-profile`);
      await startLocalProfile(runtimeTarget.profile, (message) => {
        void writeRunMessage(startupLogPath, progressLogPath, `[${target}] ${message}`).catch(() => undefined);
      });
      await writeRunMessage(startupLogPath, progressLogPath, `[${formatIstTimestamp(new Date())}] target=${target} state=local-profile-ready`);
    }

    await writeRunMessage(startupLogPath, progressLogPath, `[${formatIstTimestamp(new Date())}] target=${target} state=starting-automation-run`);
    const run = await executePaymentAutomationRun({
      target,
      tenantCodes: options.tenantCodes,
      requestedProviders: effectiveProviders,
      allowPartialExecution: options.allowPartialExecution,
      dryRun: options.dryRun,
      headless: options.headless,
      verify: options.verify,
      sandboxOtpCode: options.sandboxOtpCode,
      tenantTimeoutMs: options.tenantTimeoutMs,
      autoStartLocalSessions: false,
      autoStopLocalSessions: options.autoStopLocalSessions,
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
      const journeyFailed = !row.journeyOutcome.startsWith("completed") && row.journeyOutcome !== "dry_run";
      const verificationFailed = options.verify && !options.dryRun && row.verificationOutcome !== "passed";
      return journeyFailed || verificationFailed;
    })
  );
  matrixOutput.finishedUtc = new Date().toISOString();
  matrixOutput.finishedIst = formatIstTimestamp(new Date());
  matrixOutput.currentStep = "completed";
  matrixOutput.status = hasFailures ? "failed" : "passed";
  matrixOutput.targetCount = targetRuns.length;
  matrixOutput.targetRuns = targetRuns;

  const targetSections = targetRuns.flatMap((targetRun) => [
    `- ${targetRun.rows[0]?.runtimeTarget ?? "unknown"}: prefix ${targetRun.runPrefix}`,
    `  report: ${targetRun.reportDirectory}`,
    `  verification: ${targetRun.verificationSummary}`
  ]);

  await writeFile(
    path.join(reportDirectory, "summary.md"),
    [
      "# Local Payment Automation Matrix",
      "",
      `Started: ${matrixOutput.startedUtc}`,
      `Finished: ${matrixOutput.finishedUtc}`,
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
  await writeRunMessage(startupLogPath, progressLogPath, `[${formatIstTimestamp(new Date())}] state=completed-matrix`);

  await writeRunMessage(startupLogPath, progressLogPath, JSON.stringify(matrixOutput, null, 2));
  await appendStatus(environmentKey, "local-http-matrix", hasFailures ? "failed" : "passed", `reportDirectory=${reportDirectory}`);

  if (hasFailures) {
    throw new Error("Local payment matrix completed with failed tenant journey(s).");
  }
  }
  catch (error) {
    await appendStatus(environmentKey, "local-http-matrix", "failed", error instanceof Error ? error.message : "Local matrix failed");
    throw error;
  }
}

async function writeRunMessage(startupLogPath: string, progressLogPath: string, line: string): Promise<void> {
  process.stdout.write(`${line}\n`);
  await writeFile(progressLogPath, `${line}\n`, { flag: "a" });
  await writeFile(startupLogPath, `${line}\n`, { flag: "a" });
}

async function appendStatus(environmentKey: string, taskName: string, status: "started" | "passed" | "failed" | "info", message: string): Promise<void> {
  await import("node:child_process").then(({ execFileSync }) => {
    execFileSync("pwsh", [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      statusWriterPath,
      "-EnvironmentKey",
      environmentKey,
      "-TaskName",
      taskName,
      "-Status",
      status,
      "-Message",
      message
    ], { stdio: "inherit" });
  });
}

function parseCliOptions(argumentsList: string[]): LocalMatrixOptions {
  const targets: string[] = [];
  const tenantCodes: string[] = [];
  const requestedProviders: string[] = [];
  let allowPartialExecution = false;
  let dryRun = false;
  let headless = true;
  let verify = true;
  let sandboxOtpCode = "999";
  let tenantTimeoutMs = 180000;
  let autoStopLocalSessions = false;
  let tenantLimit: number | null = null;

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
      case "--stop-local-sessions":
        autoStopLocalSessions = true;
        break;
      case "--keep-local-sessions":
        autoStopLocalSessions = false;
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
    : ["local-http", "local-https"];

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
    autoStopLocalSessions,
    tenantLimit
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

function getDefaultMatrixProviders(): string[] {
  return ["OpenPay", "Razorpay"];
}

void main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : "Local payment matrix runner failed.";
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
});
