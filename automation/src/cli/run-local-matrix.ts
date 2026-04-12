import { mkdir, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { JsonRuntimeTargetCatalog } from "../catalog/json-runtime-target-catalog.js";
import type { ExecutePaymentAutomationRunOptions, PaymentAutomationRunOutput } from "../orchestrator/payment-automation-executor.js";
import { executePaymentAutomationRun } from "../orchestrator/payment-automation-executor.js";
import { FileReportComposer } from "../report/file-report-composer.js";
import { buildRunPrefix } from "../support/customer-order-id.js";

interface LocalMatrixOptions {
  targets: string[];
  tenantCodes: string[];
  allowPartialExecution: boolean;
  dryRun: boolean;
  headless: boolean;
  verify: boolean;
  sandboxOtpCode: string;
  tenantTimeoutMs: number;
  autoStopLocalSessions: boolean;
}

interface LocalMatrixOutput {
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
  const matrixRunId = `payment-automation-local-matrix-${startedAt.toISOString().replace(/[.:]/g, "-")}`;
  const reportDirectory = path.join(automationRoot, "reports", matrixRunId);
  const reportComposer = new FileReportComposer();
  const runtimeTargetCatalog = new JsonRuntimeTargetCatalog();

  await mkdir(reportDirectory, { recursive: true });
  process.stdout.write(`Starting local payment matrix ${matrixRunId}.\n`);

  const targetRuns: PaymentAutomationRunOutput[] = [];
  for (const [index, target] of options.targets.entries()) {
    const targetStart = new Date(startedAt.getTime() + (index * 1000));
    const targetRunPrefix = buildRunPrefix(targetStart);
    process.stdout.write(`Executing target ${target} with prefix ${targetRunPrefix}.\n`);

    const runtimeTarget = await runtimeTargetCatalog.resolve(target);
    if (!options.dryRun && runtimeTarget.runtime === "local") {
      await startLocalProfile(runtimeTarget.profile, (message) => {
        process.stdout.write(`[${target}] ${message}\n`);
      });
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
      autoStopLocalSessions: options.autoStopLocalSessions,
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
  const matrixOutput: LocalMatrixOutput = {
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

  process.stdout.write(`${JSON.stringify(matrixOutput, null, 2)}\n`);
}

function parseCliOptions(argumentsList: string[]): LocalMatrixOptions {
  const targets: string[] = [];
  const tenantCodes: string[] = [];
  let allowPartialExecution = false;
  let dryRun = false;
  let headless = true;
  let verify = true;
  let sandboxOtpCode = "999";
  let tenantTimeoutMs = 180000;
  let autoStopLocalSessions = true;

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
      case "--keep-local-sessions":
        autoStopLocalSessions = false;
        break;
      default:
        break;
    }
  }

  return {
    targets: targets.length > 0 ? targets : ["local-http", "local-https"],
    tenantCodes,
    allowPartialExecution,
    dryRun,
    headless,
    verify,
    sandboxOtpCode,
    tenantTimeoutMs,
    autoStopLocalSessions
  };
}

async function startLocalProfile(profile: "http" | "https", log: (message: string) => void): Promise<void> {
  const scriptPath = path.resolve(automationRoot, "..", "scripts", "start-local-profile.ps1");

  log(`Starting local ${profile} profile for matrix target.`);

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

void main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : "Local payment matrix runner failed.";
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
});