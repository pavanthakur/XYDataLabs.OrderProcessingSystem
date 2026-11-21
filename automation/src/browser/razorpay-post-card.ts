export type RazorpayPostCardState = "callback" | "mock-bank" | "save-card" | "validation-error" | "timeout";

/** Observe the checkout after a single submission; this routine cannot submit a card. */
export async function finishRazorpayPostCard(
  observe: (allowSaveCard: boolean) => Promise<RazorpayPostCardState>,
  skipSavingCard: () => Promise<void>,
  completeMockBank: () => Promise<void>
): Promise<boolean> {
  let state = await observe(true);
  if (state === "save-card") {
    await skipSavingCard();
    state = await observe(false);
  }
  if (state === "callback") return false;
  if (state === "mock-bank") {
    await completeMockBank();
    return true;
  }
  if (state === "validation-error") {
    throw new Error("Razorpay displayed card field validation after Continue; provider outcome was not confirmed. Do not resubmit.");
  }
  throw new Error("Razorpay checkout did not show a recognized transition after one Continue click; provider outcome is unknown. Do not resubmit.");
}
