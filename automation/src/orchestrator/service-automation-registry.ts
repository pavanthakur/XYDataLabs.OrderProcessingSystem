import type { ServiceAutomationAdapter } from "../contracts/service-automation-adapter.js";

export class ServiceAutomationRegistry {
  private readonly adapters = new Map<string, ServiceAutomationAdapter>();

  public register(adapter: ServiceAutomationAdapter): void {
    this.adapters.set(adapter.name, adapter);
  }

  public list(): ServiceAutomationAdapter[] {
    return Array.from(this.adapters.values());
  }
}
