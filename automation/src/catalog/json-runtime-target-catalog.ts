import runtimeTargetsDocument from "../../config/runtime-targets.json" with { type: "json" };
import type { RuntimeTargetCatalog, RuntimeTargetDefinition } from "../contracts/runtime-target-catalog.js";

const runtimeTargets = runtimeTargetsDocument as { targets: RuntimeTargetDefinition[] };

export class JsonRuntimeTargetCatalog implements RuntimeTargetCatalog {
  public async resolve(targetKey: string): Promise<RuntimeTargetDefinition> {
    const target = runtimeTargets.targets.find((candidate) => candidate.key === targetKey);

    if (!target) {
      throw new Error(`Unknown runtime target: ${targetKey}`);
    }

    return target;
  }
}
