export type CleanupOutcome = "deleted" | "reset" | "manual-review";

export interface FixturePrepareResult {
  fixtureIds: string[];
  baselineName: string;
}

export interface FixtureCleanupResult {
  outcome: CleanupOutcome;
  residualIds: string[];
}

export interface PaymentFixtureProvisioner {
  prepare(tenantCode: string): Promise<FixturePrepareResult>;
  cleanup(tenantCode: string, fixtureIds: string[]): Promise<FixtureCleanupResult>;
}
