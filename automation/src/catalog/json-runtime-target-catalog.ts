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

  if (target.publicUrlMode === "generated") {
    if (target.key !== "azure-dev" || !baseUrl || !apiBaseUrl) {
      throw new Error(`Runtime target ${target.key} requires both live Azure-generated URL overrides.`);
    }
    const hostSuffixes: string[] = [];
    for (const [label, value, appName] of [["UI", baseUrl, target.azureUiContainerAppName], ["API", apiBaseUrl, target.azureGatewayContainerAppName]]) {
      if (!value || !appName) throw new Error(`Runtime target ${target.key} is missing generated ${label} origin metadata.`);
      const url = new URL(value);
      const prefix = `${appName}.`;
      if (url.protocol !== "https:" || !url.hostname.startsWith(prefix) || !url.hostname.endsWith(".azurecontainerapps.io") || url.pathname !== "/" || url.search || url.hash || url.port || url.username || url.password || url.origin !== value.trim()) {
        throw new Error(`Runtime target ${target.key} has an invalid generated ${label} origin.`);
      }
      hostSuffixes.push(url.hostname.slice(prefix.length));
    }
    if (hostSuffixes[0] !== hostSuffixes[1]) throw new Error(`Runtime target ${target.key} generated origins belong to different ACA environments.`);
    return { ...target, baseUrl: baseUrl.trim(), apiBaseUrl: apiBaseUrl.trim(), publicUiBaseUrl: baseUrl.trim(), publicApiBaseUrl: apiBaseUrl.trim() };
  }

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
