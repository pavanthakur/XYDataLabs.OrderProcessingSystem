import type { RuntimeTargetDefinition } from "../contracts/runtime-target-catalog.js";

export function resolveEnvironmentKey(target: RuntimeTargetDefinition): string {
  const profile = target.profile.toLowerCase();

  if (target.runtime === "local") {
    return `local-${profile}`;
  }

  if (target.runtime === "docker") {
    return `docker-${profile}`;
  }

  if (target.runtime === "azure") {
    return `azure-${profile}`;
  }

  return `${target.runtime}-${profile}`;
}
