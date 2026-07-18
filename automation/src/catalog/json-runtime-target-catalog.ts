import runtimeTargetsDocument from "../../config/runtime-targets.json" with { type: "json" };
import type { RuntimeTargetCatalog, RuntimeTargetDefinition } from "../contracts/runtime-target-catalog.js";

const runtimeTargets = runtimeTargetsDocument as { targets: RuntimeTargetDefinition[] };

export class JsonRuntimeTargetCatalog implements RuntimeTargetCatalog {
  public async resolve(targetKey: string): Promise<RuntimeTargetDefinition> {
    const target = runtimeTargets.targets.find((candidate) => candidate.key === targetKey);

    if (!target) {
      throw new Error(`Unknown runtime target: ${targetKey}`);
    }

    return applyRuntimeOverrides(target);
  }
}

function applyRuntimeOverrides(target: RuntimeTargetDefinition): RuntimeTargetDefinition {
  const environmentKey = normalizeEnvironmentKey(target.key);
  const baseUrl = process.env[`XYDATALABS_RUNTIME_TARGET_${environmentKey}_BASE_URL`];
  const apiBaseUrl = process.env[`XYDATALABS_RUNTIME_TARGET_${environmentKey}_API_BASE_URL`];

  if (!baseUrl && !apiBaseUrl) {
    return target;
  }

  return {
    ...target,
    baseUrl: baseUrl?.trim() || target.baseUrl,
    apiBaseUrl: apiBaseUrl?.trim() || target.apiBaseUrl
  };
}

function normalizeEnvironmentKey(value: string): string {
  return value.trim().toUpperCase().replace(/[^A-Z0-9]+/g, "_");
}
