import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import type { VerificationAdapter, VerificationRequest, VerificationResult } from "../contracts/verification-adapter.js";

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(currentDirectory, "../../..");

export class PowerShellVerificationAdapter implements VerificationAdapter {
  public async execute(request: VerificationRequest): Promise<VerificationResult> {
    if (request.runtime === "azure") {
      return this.executeAzure(request);
    }

    return this.executePhysical(request);
  }

  private async executePhysical(request: VerificationRequest): Promise<VerificationResult> {
    const scriptPath = path.join(repoRoot, "scripts", "verify-payment-run-physical.ps1");
    const stdout = await this.invokePowerShell([
      "-NoProfile",
      "-File",
      scriptPath,
      "-Runtime",
      request.runtime,
      "-Environment",
      request.environment,
      "-Profile",
      request.profile,
      "-RunPrefix",
      request.runPrefix,
      "-OutputFormat",
      "Json"
    ]);

    const rawReport = parseJsonPayload(stdout) as { Checks?: Record<string, { Outcome?: string }> };
    const outcomes = Object.values(rawReport.Checks ?? {}).map((value) => value.Outcome ?? "");
    const hasFailure = outcomes.includes("FAIL");
    const hasInconclusive = outcomes.includes("INCONCLUSIVE");

    return {
      outcome: hasFailure ? "failed" : hasInconclusive ? "partial" : "passed",
      summary: `Physical verification completed for ${request.runPrefix}.`,
      rawReport
    };
  }

  private async executeAzure(request: VerificationRequest): Promise<VerificationResult> {
    const scriptPath = path.join(repoRoot, "scripts", "verify-payment-run-azure.ps1");
    const stdout = await this.invokePowerShell([
      "-NoProfile",
      "-File",
      scriptPath,
      "-Environment",
      request.environment,
      "-RunPrefix",
      request.runPrefix,
      "-OutputFormat",
      "Json"
    ]);

    const rawReport = parseJsonPayload(stdout) as { Checks?: Record<string, { Outcome?: string }> };
    const outcomes = Object.values(rawReport.Checks ?? {}).map((value) => value.Outcome ?? "");
    const hasFailure = outcomes.includes("FAIL");
    const hasInconclusive = outcomes.includes("INCONCLUSIVE");

    return {
      outcome: hasFailure ? "failed" : hasInconclusive ? "partial" : "passed",
      summary: `Azure verification completed for ${request.runPrefix}.`,
      rawReport
    };
  }

  private async invokePowerShell(argumentsList: string[]): Promise<string> {
    return new Promise((resolve, reject) => {
      const child = spawn("pwsh", argumentsList, {
        cwd: repoRoot,
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
        if (exitCode === 0) {
          resolve(stdout.trim());
          return;
        }

        reject(new Error(stderr.trim() || `PowerShell verification exited with code ${exitCode}.`));
      });
    });
  }
}

function parseJsonPayload(stdout: string): unknown {
  const trimmedOutput = stdout.trim();

  try {
    return JSON.parse(trimmedOutput);
  }
  catch {
  }

  for (let index = trimmedOutput.lastIndexOf("{"); index >= 0; index = trimmedOutput.lastIndexOf("{", index - 1)) {
    const candidate = trimmedOutput.slice(index).trim();

    try {
      return JSON.parse(candidate);
    }
    catch {
    }
  }

  throw new Error("Unable to parse verification JSON from PowerShell output.");
}
