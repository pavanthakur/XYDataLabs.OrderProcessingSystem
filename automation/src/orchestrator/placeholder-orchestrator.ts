import runtimeTargetsDocument from "../../config/runtime-targets.example.json" with { type: "json" };
import { NoopServiceAutomationAdapter } from "../adapters/service/noop-service-automation-adapter.js";
import type {
  RuntimeTargetCatalog,
  RuntimeTargetDefinition
} from "../contracts/runtime-target-catalog.js";
import { ServiceAutomationRegistry } from "./service-automation-registry.js";

const runtimeTargets = runtimeTargetsDocument as { targets: RuntimeTargetDefinition[] };

class ExampleRuntimeTargetCatalog implements RuntimeTargetCatalog {
  public async resolve(targetKey: string): Promise<RuntimeTargetDefinition> {
    const target = runtimeTargets.targets.find((candidate) => candidate.key === targetKey);

    if (!target) {
      throw new Error(`Unknown runtime target: ${targetKey}`);
    }

    return target;
  }
}

async function main(): Promise<void> {
  const catalog = new ExampleRuntimeTargetCatalog();
  const registry = new ServiceAutomationRegistry();
  const noopAdapter = new NoopServiceAutomationAdapter();

  registry.register(noopAdapter);

  const target = await catalog.resolve("local-http");
  const adapterResults = await Promise.all(
    registry.list().map((adapter) => adapter.execute(target.key))
  );

  const output = {
    resolvedTarget: target,
    adapterResults
  };

  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : "Unknown placeholder orchestrator failure";
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
});
