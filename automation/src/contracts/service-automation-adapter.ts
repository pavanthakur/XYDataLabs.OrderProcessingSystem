export interface ServiceAutomationAdapterResult {
  adapterName: string;
  outcome: "noop" | "passed" | "failed";
  summary: string;
}

export interface ServiceAutomationAdapter {
  readonly name: string;
  execute(runtimeTarget: string): Promise<ServiceAutomationAdapterResult>;
}
