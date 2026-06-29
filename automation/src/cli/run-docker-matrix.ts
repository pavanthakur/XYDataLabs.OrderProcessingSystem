import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { JsonRuntimeTargetCatalog } from "../catalog/json-runtime-target-catalog.js";
import type { PaymentAutomationRunOutput } from "../orchestrator/payment-automation-executor.js";
import { executePaymentAutomationRun } from "../orchestrator/payment-automation-executor.js";
import { FileReportComposer } from "../report/file-report-composer.js";
import { buildRunPrefix } from "../support/customer-order-id.js";
import { resolveEnvironmentKey } from "../support/environment-key.js";

interface DockerMatrixOptions {
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
}

interface DockerMatrixOutput {
  matrixRunId: string;
  reportDirectory: string;
  environmentKey: string;
  startedUtc: string;
  finishedUtc: string;
  startedIst: string;
  finishedIst: string;
  currentStep?: string;
  targetCount: number;
  targets: string[];
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

function formatIstStamp(date: Date): string {
  return formatIstTimestamp(date).replace(/[:+,]/g, "-").replace(/\./g, "-");
}

async function main(): Promise<void> {
  const options = parseCliOptions(process.argv.slice(2));
  const startedAt = new Date();
  const matrixRunId = `payment-automation-docker-matrix-${formatIstStamp(startedAt)}_matrix`;
  const playrightRoot = path.join(workspaceRoot, "TestResults", "Playwright");
  const reportComposer = new FileReportComposer();
  const runtimeTargetCatalog = new JsonRuntimeTargetCatalog();
  const environmentKey = options.targets.length === 1
    ? options.targets[0]
    : "docker-matrix";
  const environmentRoot = path.join(playrightRoot, environmentKey);
  const reportDirectory = path.join(environmentRoot, matrixRunId);
  const latestPointerPath = path.join(environmentRoot, "latest-playwright-matrix.txt");
  const runPlanPath = path.join(reportDirectory, "run-plan.txt");
  const startupLogPath = path.join(reportDirectory, "startup.log");
  const progressLogPath = path.join(reportDirectory, "progress.log");
  const currentStepPath = path.join(reportDirectory, "current-step.txt");
  const matrixOutput: DockerMatrixOutput = {
    matrixRunId,
    reportDirectory,
    environmentKey,
    startedUtc: startedAt.toISOString(),
    finishedUtc: startedAt.toISOString(),
    startedIst: formatIstTimestamp(startedAt),
    finishedIst: formatIstTimestamp(startedAt),
    targetCount: 0,
    targets: options.targets,
    targetRuns: []
  };

  await mkdir(reportDirectory, { recursive: true });
  await mkdir(path.dirname(latestPointerPath), { recursive: true });
  await writeFile(latestPointerPath, `${reportDirectory}\n`, "utf8");
  await writeFile(startupLogPath, [
    `[${formatIstTimestamp(new Date())}] Matrix startup`,
    `environment=${environmentKey}`,
    `targets=${options.targets.join(",")}`,
    `requestedProviders=${options.requestedProviders.length > 0 ? options.requestedProviders.join(",") : "runtime default"}`,
    `tenantLimit=${options.tenantLimit ?? "none"}`,
    `dryRun=${options.dryRun}`,
    `verify=${options.verify}`,
    `state=created-run-folder`
  ].join("\n") + "\n", "utf8");
  await writeFile(progressLogPath, "Matrix progress log initialized.\n", "utf8");
  await writeFile(runPlanPath, [
    "Docker HTTP matrix sanity run",
    `Goal: confirm docker target discovery and basic execution flow.`,
    `Environment: ${environmentKey}`,
    `Targets: ${options.targets.join(", ")}`,
    `Requested providers: ${options.requestedProviders.length > 0 ? options.requestedProviders.join(", ") : "runtime default"}`,
    `Tenant limit: ${options.tenantLimit ?? "none"}`,
    `Dry run: ${options.dryRun ? "yes" : "no"}`,
    `Verification: ${options.verify ? "yes" : "no"}`,
    "",
    "Stages:",
    "1. Create the run folder and latest pointer files.",
    "2. Resolve the runtime target and tenant plan.",
    "3. Execute each tenant/provider item in order.",
    "4. Write summary.json and summary.md at the end."
  ].join("\n"), "utf8");
  await writeFile(path.join(reportDirectory, "summary.json"), JSON.stringify({ ...matrixOutput, status: "running" }, null, 2), "utf8");
  await writeFile(currentStepPath, "initialized\n", "utf8");
  await writeRunMessage(startupLogPath, progressLogPath, `Starting docker payment matrix ${matrixRunId}.`);

  const targetRuns: PaymentAutomationRunOutput[] = [];
  for (const [index, target] of options.targets.entries()) {
    const targetStart = new Date(startedAt.getTime() + (index * 1000));
    const targetRunPrefix = buildRunPrefix(targetStart);
    matrixOutput.currentStep = `target:${target}`;
    await writeFile(path.join(reportDirectory, "summary.json"), JSON.stringify({ ...matrixOutput, status: "running" }, null, 2), "utf8");
    await writeFile(currentStepPath, `${matrixOutput.currentStep}\n`, "utf8");
    await writeRunMessage(startupLogPath, progressLogPath, `Executing target ${target} with prefix ${targetRunPrefix}.`);

    const runtimeTarget = await runtimeTargetCatalog.resolve(target);
    if (runtimeTarget.runtime !== "docker") {
      throw new Error(`Docker matrix target ${target} resolved to runtime ${runtimeTarget.runtime}.`);
    }

    const run = await executePaymentAutomationRun({
      target,
      tenantCodes: options.tenantCodes,
      requestedProviders: options.requestedProviders,
      allowPartialExecution: options.allowPartialExecution,
      dryRun: options.dryRun,
      headless: options.headless,
      verify: options.verify,
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
  }

  const rows = targetRuns.flatMap((targetRun) => targetRun.rows);
  const markdownSummary = await reportComposer.compose(rows);
  matrixOutput.finishedUtc = new Date().toISOString();
  matrixOutput.finishedIst = formatIstTimestamp(new Date());
  matrixOutput.currentStep = "completed";
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
      "# Docker Payment Automation Matrix",
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

  process.stdout.write(`${JSON.stringify(matrixOutput, null, 2)}\n`);
}

async function writeRunMessage(startupLogPath: string, progressLogPath: string, line: string): Promise<void> {
  process.stdout.write(`${line}\n`);
  await writeFile(progressLogPath, `${line}\n`, { flag: "a" });
  await writeFile(startupLogPath, `${line}\n`, { flag: "a" });
}

function parseCliOptions(argumentsList: string[]): DockerMatrixOptions {
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
      case "--tenant-limit":
        tenantLimit = Number(argumentsList[index + 1] ?? tenantLimit);
        index += 1;
        break;
      default:
        break;
    }
  }

  return {
    targets: targets.length > 0
      ? targets
      : [
        "docker-dev-http",
        "docker-dev-https",
        "docker-stg-http",
        "docker-stg-https",
        "docker-prod-http",
        "docker-prod-https"
      ],
    tenantCodes,
    requestedProviders,
    allowPartialExecution,
    dryRun,
    headless,
    verify,
    sandboxOtpCode,
    tenantTimeoutMs,
    tenantLimit
  };
}

void main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : "Docker payment matrix runner failed.";
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
});
