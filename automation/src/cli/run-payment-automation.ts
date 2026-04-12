import type { ExecutePaymentAutomationRunOptions } from "../orchestrator/payment-automation-executor.js";
import { executePaymentAutomationRun } from "../orchestrator/payment-automation-executor.js";

async function main(): Promise<void> {
  const options = parseCliOptions(process.argv.slice(2));
  const output = await executePaymentAutomationRun({
    ...options,
    logger: (message) => {
      process.stdout.write(`${message}\n`);
    }
  });

  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
}

function parseCliOptions(argumentsList: string[]): ExecutePaymentAutomationRunOptions {
  let target = "local-http";
  const tenantCodes: string[] = [];
  let allowPartialExecution = false;
  let dryRun = false;
  let headless = true;
  let verify = true;
  let sandboxOtpCode = "999";
  let tenantTimeoutMs = 180000;
  let runPrefix: string | undefined;
  let autoStopLocalSessions = true;

  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = argumentsList[index];

    switch (argument) {
      case "--target":
        target = argumentsList[index + 1] ?? target;
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
      case "--run-prefix":
        runPrefix = argumentsList[index + 1] ?? runPrefix;
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
    target,
    tenantCodes,
    allowPartialExecution,
    dryRun,
    headless,
    verify,
    sandboxOtpCode,
    tenantTimeoutMs,
    runPrefix,
    autoStopLocalSessions
  };
}

void main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : "Payment automation runner failed.";
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
});
