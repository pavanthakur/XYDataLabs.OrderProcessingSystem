import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { JsonRuntimeTargetCatalog } from "../catalog/json-runtime-target-catalog.js";
import type { PaymentAutomationRunOutput } from "../orchestrator/payment-automation-executor.js";
import { executePaymentAutomationRun } from "../orchestrator/payment-automation-executor.js";
import { FileReportComposer } from "../report/file-report-composer.js";
import { buildRunPrefix } from "../support/customer-order-id.js";

interface AzureMatrixOptions {
  targets: string[];
  tenantCodes: string[];
  allowPartialExecution: boolean;
  dryRun: boolean;
  headless: boolean;
  verify: boolean;
  sandboxOtpCode: string;
  tenantTimeoutMs: number;
}

interface AzureMatrixOutput {
  matrixRunId: string;
  reportDirectory: string;
  startedUtc: string;
  finishedUtc: string;
  targetRuns: PaymentAutomationRunOutput[];
}

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const automationRoot = path.resolve(currentDirectory, "../..");

async function main(): Promise<void> {
  const options = parseCliOptions(process.argv.slice(2));
  const startedAt = new Date();
  const matrixRunId = `payment-automation-azure-matrix-${startedAt.toISOString().replace(/[.:]/g, "-")}`;
  const reportDirectory = path.join(automationRoot, "reports", matrixRunId);
  const reportComposer = new FileReportComposer();
  const runtimeTargetCatalog = new JsonRuntimeTargetCatalog();

  await mkdir(reportDirectory, { recursive: true });
  process.stdout.write(`Starting azure payment matrix ${matrixRunId}.\n`);

  const targetRuns: PaymentAutomationRunOutput[] = [];
  for (const [index, target] of options.targets.entries()) {
    const targetStart = new Date(startedAt.getTime() + (index * 1000));
    const targetRunPrefix = buildRunPrefix(targetStart);
    process.stdout.write(`Executing target ${target} with prefix ${targetRunPrefix}.\n`);

    const runtimeTarget = await runtimeTargetCatalog.resolve(target);
    if (runtimeTarget.runtime !== "azure") {
      throw new Error(`Azure matrix target ${target} resolved to runtime ${runtimeTarget.runtime}.`);
    }

    const run = await executePaymentAutomationRun({
      target,
      tenantCodes: options.tenantCodes,
      allowPartialExecution: options.allowPartialExecution,
      dryRun: options.dryRun,
      headless: options.headless,
      verify: options.verify,
      sandboxOtpCode: options.sandboxOtpCode,
      tenantTimeoutMs: options.tenantTimeoutMs,
      startedAt: targetStart,
      runPrefix: targetRunPrefix,
      logger: (message) => {
        process.stdout.write(`[${target}] ${message}\n`);
      }
    });

    targetRuns.push(run);
  }

  const rows = targetRuns.flatMap((targetRun) => targetRun.rows);
  const markdownSummary = await reportComposer.compose(rows);
  const matrixOutput: AzureMatrixOutput = {
    matrixRunId,
    reportDirectory,
    startedUtc: startedAt.toISOString(),
    finishedUtc: new Date().toISOString(),
    targetRuns
  };

  const targetSections = targetRuns.flatMap((targetRun) => [
    `- ${targetRun.rows[0]?.runtimeTarget ?? "unknown"}: prefix ${targetRun.runPrefix}`,
    `  report: ${targetRun.reportDirectory}`,
    `  verification: ${targetRun.verificationSummary}`
  ]);

  await writeFile(
    path.join(reportDirectory, "summary.md"),
    [
      "# Azure Payment Automation Matrix",
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

  process.stdout.write(`${JSON.stringify(matrixOutput, null, 2)}\n`);
}

function parseCliOptions(argumentsList: string[]): AzureMatrixOptions {
  const targets: string[] = [];
  const tenantCodes: string[] = [];
  let allowPartialExecution = false;
  let dryRun = false;
  let headless = true;
  let verify = true;
  let sandboxOtpCode = "999";
  let tenantTimeoutMs = 180000;

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
      default:
        break;
    }
  }

  return {
    targets: targets.length > 0
      ? targets
      : [
        "azure-dev",
        "azure-stg",
        "azure-prod"
      ],
    tenantCodes,
    allowPartialExecution,
    dryRun,
    headless,
    verify,
    sandboxOtpCode,
    tenantTimeoutMs
  };
}

void main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : "Azure payment matrix runner failed.";
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
});