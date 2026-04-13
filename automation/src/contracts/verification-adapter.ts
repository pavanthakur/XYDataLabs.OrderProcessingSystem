import type { EnvironmentName, RuntimeKind, RuntimeProfile } from "./runtime-target-catalog.js";
import type { ThreeDsSetting } from "./report-composer.js";

export interface VerificationRequest {
  runtimeTarget: string;
  runtime: RuntimeKind;
  environment: EnvironmentName;
  profile: RuntimeProfile;
  runPrefix: string;
}

export interface VerificationResult {
  outcome: "passed" | "failed" | "partial" | "skipped";
  summary: string;
  threeDsByTenant?: Partial<Record<string, ThreeDsSetting>>;
  rawReport?: unknown;
}

export interface VerificationAdapter {
  execute(request: VerificationRequest): Promise<VerificationResult>;
}
