import type { Page } from "playwright";

export interface CallbackSnapshot {
  loading: boolean;
  errorMessage: string;
  successMessage: string;
  infoMessage: string;
}

export interface CallbackOutcome {
  state: "completed" | "failed" | "pending";
  message: string;
}

export function classifyCallback(snapshot: CallbackSnapshot): CallbackOutcome {
  // An error always wins, even if stale success content is also present.
  if (snapshot.errorMessage.trim()) {
    return { state: "failed", message: snapshot.errorMessage.trim() };
  }
  if (!snapshot.loading && snapshot.successMessage.trim()) {
    return { state: "completed", message: snapshot.successMessage.trim() };
  }
  return { state: "pending", message: snapshot.infoMessage.trim() || "Callback success has not been confirmed." };
}

export async function waitForCallbackOutcome(page: Page, timeoutMs = 60000): Promise<CallbackOutcome> {
  // Do not equate an absent loading panel with success: the callback effect might not
  // have mounted yet, or it might already have finished with a terminal error.
  await page.waitForFunction(() => {
    const error = document.querySelector("p.error-banner")?.textContent?.trim();
    const success = document.querySelector("p.success-banner")?.textContent?.trim();
    return Boolean(error || (success && !document.querySelector(".loading-progress-panel")));
  }, undefined, { timeout: timeoutMs }).catch((error: unknown) => {
    if (!(error instanceof Error) || error.name !== "TimeoutError") { throw error; }
  });
  const snapshot = await page.evaluate(() => ({
    loading: Boolean(document.querySelector(".loading-progress-panel")),
    errorMessage: document.querySelector("p.error-banner")?.textContent ?? "",
    successMessage: document.querySelector("p.success-banner")?.textContent ?? "",
    infoMessage: document.querySelector("p.info-banner")?.textContent ?? ""
  }));
  return classifyCallback(snapshot);
}
