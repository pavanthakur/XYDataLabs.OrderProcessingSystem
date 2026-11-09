import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type {
  FixtureCleanupResult,
  FixturePrepareResult,
  PaymentFixtureProvisioner
} from "../../contracts/payment-fixture-provisioner.js";
import type { RuntimeTargetDefinition } from "../../contracts/runtime-target-catalog.js";

interface ProviderActivationResult {
  tenantCode: string;
  database: string;
  previousProviderType: string;
  currentProviderType: string;
}

export interface PowerShellPaymentProviderProvisionerOptions {
  target: RuntimeTargetDefinition;
  requestedProvider: string;
  threeDs?: boolean;
  logger?: (message: string) => void;
}

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(currentDirectory, "../../../..");

export class PowerShellPaymentProviderProvisioner implements PaymentFixtureProvisioner {
  private readonly logger: (message: string) => void;

  public constructor(private readonly options: PowerShellPaymentProviderProvisionerOptions) {
    this.logger = options.logger ?? (() => undefined);
  }

  public async prepare(tenantCode: string): Promise<FixturePrepareResult> {
    if (this.options.target.runtime === "docker" && this.options.target.environment === "dev") {
      const manifestPath = path.join(repoRoot, "TestResults", "DockerStorage", "payment-state", `${randomUUID()}.json`);
      await this.invokePowerShell(["-NoProfile", "-File", path.join(repoRoot,"scripts/local-payment-test-state.ps1"),
        "-Action","Prepare","-ManifestPath",manifestPath,"-TenantCode",tenantCode,"-ProviderType",this.options.requestedProvider,
        "-ThreeDs",this.options.threeDs === undefined ? "unchanged" : String(this.options.threeDs)]);
      return {fixtureIds:[manifestPath],baselineName:"exact-local-snapshot"};
    }
    if (this.options.threeDs !== undefined) throw new Error("3DS fixture overrides are supported only on verified local Docker dev.");
    const result = await this.activateProvider(tenantCode, this.options.requestedProvider);
    this.logger(
      `Activated provider ${result.currentProviderType} for ${tenantCode} in ${result.database} (previous: ${result.previousProviderType}).`
    );

    return {
      fixtureIds: result.previousProviderType ? [result.previousProviderType] : [],
      baselineName: `provider:${result.previousProviderType || "unknown"}`
    };
  }

  public async cleanup(tenantCode: string, fixtureIds: string[]): Promise<FixtureCleanupResult> {
    if (this.options.target.runtime === "docker" && this.options.target.environment === "dev") {
      if (!fixtureIds[0]) throw new Error("Missing local recovery manifest. Manual review required.");
      await this.invokePowerShell(["-NoProfile","-File",path.join(repoRoot,"scripts/local-payment-test-state.ps1"),
        "-Action","Restore","-ManifestPath",fixtureIds[0]]);
      return {outcome:"reset",residualIds:[]};
    }
    const previousProvider = fixtureIds[0];
    if (!previousProvider || this.providersMatch(previousProvider, this.options.requestedProvider)) {
      return {
        outcome: "reset",
        residualIds: []
      };
    }

    const result = await this.activateProvider(tenantCode, previousProvider);
    this.logger(
      `Restored provider ${result.currentProviderType} for ${tenantCode} in ${result.database}.`
    );

    return {
      outcome: "reset",
      residualIds: []
    };
  }

  private async activateProvider(tenantCode: string, providerType: string): Promise<ProviderActivationResult> {
    if (this.options.target.runtime !== "local" && this.options.target.runtime !== "docker" && this.options.target.runtime !== "azure") {
      throw new Error(`Provider override is not supported for runtime ${this.options.target.runtime}.`);
    }

    const scriptPath = path.join(repoRoot, "scripts", "set-tenant-payment-provider.ps1");
    const stdout = await this.invokePowerShell([
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      scriptPath,
      "-Runtime",
      this.options.target.runtime,
      "-Environment",
      this.options.target.environment,
      "-TenantCode",
      tenantCode,
      "-ProviderType",
      providerType,
      "-OutputFormat",
      "Json"
    ]);

    return this.parseJsonPayload(stdout) as ProviderActivationResult;
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

        reject(new Error(stderr.trim() || `Provider override PowerShell exited with code ${exitCode}.`));
      });
    });
  }

  private parseJsonPayload(stdout: string): unknown {
    const trimmedOutput = stdout.trim();

    try {
      return JSON.parse(trimmedOutput);
    }
    catch {
      return JSON.parse(trimmedOutput.slice(trimmedOutput.lastIndexOf("{")));
    }
  }

  private providersMatch(left: string, right: string): boolean {
    return left.trim().localeCompare(right.trim(), undefined, { sensitivity: "accent" }) === 0;
  }
}
