import type {
  ServiceAutomationAdapter,
  ServiceAutomationAdapterResult
} from "../../contracts/service-automation-adapter.js";

export class NoopServiceAutomationAdapter implements ServiceAutomationAdapter {
  public readonly name = "noop-service-adapter";

  public async execute(runtimeTarget: string): Promise<ServiceAutomationAdapterResult> {
    return {
      adapterName: this.name,
      outcome: "noop",
      summary: `No-op service automation executed for ${runtimeTarget}`
    };
  }
}
