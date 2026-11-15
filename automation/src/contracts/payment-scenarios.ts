/** Same positive business journey in Docker and Azure; identity/evidence adapters differ. */
export const baselinePaymentScenarios = Object.freeze([
  { provider: "Razorpay", threeDs: false, challengeRequired: false, currency: "INR", entryMode: "ui" },
  { provider: "OpenPay", threeDs: false, challengeRequired: false, currency: "MXN", entryMode: "ui" }
] as const);

export function paymentCurrency(provider: string): string {
  const scenario = baselinePaymentScenarios.find(item => item.provider.toLowerCase() === provider.toLowerCase());
  if (!scenario) throw new Error("Provider has no supported payment scenario/currency contract.");
  return scenario.currency;
}
