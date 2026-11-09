export interface ProviderConfirmation {
  paymentId: string;
  status: string;
  remoteStatusConfirmed: boolean;
  isSuccess: boolean;
  isPending: boolean;
  isFailure: boolean;
  providerAmount?: number;
  providerCurrency?: string;
  providerOrderId?: string;
}

export function assertSandboxConfirmation(confirmation: ProviderConfirmation | undefined, expected?: {amount:number;currency:string}): void {
  if (!confirmation?.remoteStatusConfirmed || !confirmation.isSuccess || confirmation.isPending || confirmation.isFailure
    || !["completed","captured","paid"].includes(confirmation.status?.toLowerCase())
    || !confirmation.paymentId || /^(DET-|det-)/i.test(confirmation.paymentId)) {
    throw new Error("Sandbox payment lacks authoritative final provider confirmation; pending/authorized/simulated states cannot pass.");
  }
  if(expected && (confirmation.providerAmount!==expected.amount || confirmation.providerCurrency?.toUpperCase()!==expected.currency.toUpperCase())) {
    throw new Error("Provider-confirmed amount/currency does not match the selected order.");
  }
}

export function assertRuntimeMode(runtime: {adapterMode:string;isProduction:boolean}, expected:"sandbox"|"deterministic"): void {
  if (runtime.adapterMode !== expected || runtime.isProduction) throw new Error("Unexpected payment adapter or live configuration. Refusing test charge.");
}

export function requiredChallengeVerified(required: boolean, observed: string | undefined, outcome: string): boolean {
  return !required || (observed === "presented" && outcome === "passed");
}
