import { chromium } from "playwright";
import type { ChallengeOutcome } from "../contracts/provider-challenge-handler.js";
import type { ThreeDsSetting } from "../contracts/report-composer.js";
import type { RuntimeTargetDefinition } from "../contracts/runtime-target-catalog.js";
import { OpenPaySandboxChallengeHandler } from "./openpay-sandbox-challenge-handler.js";

export interface PaymentJourneyRequest {
  tenantCode: string;
  target: RuntimeTargetDefinition;
  customerOrderId: string;
  sandboxOtpCode: string;
  headless: boolean;
  diagnosticsDirectory?: string;
  logger?: (message: string) => void;
}

export interface PaymentJourneyResult {
  journeyOutcome: string;
  challengeOutcome: ChallengeOutcome;
  threeDsSetting: ThreeDsSetting;
  finalUrl: string;
  statusMessage: string;
}

export class PaymentJourneyRunner {
  private readonly challengeHandler = new OpenPaySandboxChallengeHandler();

  public async execute(request: PaymentJourneyRequest): Promise<PaymentJourneyResult> {
    const log = request.logger ?? (() => undefined);
    log(`Launching browser for ${request.tenantCode} on ${request.target.key}.`);
    const browser = await chromium.launch({ headless: request.headless });

    try {
      const context = await browser.newContext({ ignoreHTTPSErrors: request.target.ignoreHttpsErrors });
      const page = await context.newPage();
      const targetUrl = `${request.target.baseUrl}${request.target.paymentPagePath}?tenantCode=${encodeURIComponent(request.tenantCode)}`;

      log(`Navigating to ${targetUrl}.`);
      await page.goto(targetUrl, { waitUntil: "domcontentloaded" });
      await page.getByRole("heading", { name: /Take a card payment|Collect payment/i }).waitFor({ timeout: 30000 });
      log("Payment page is ready.");

      const tenantPicker = page.getByLabel("Tenant");
      if (await tenantPicker.count() > 0) {
        await tenantPicker.selectOption(request.tenantCode).catch(() => undefined);
      }

      log(`Filling payment form for ${request.customerOrderId}.`);
      await page.getByLabel("Cardholder name").fill("Automation Runner");
      await page.getByLabel("Email").fill("automation.runner@example.com");
      await page.getByLabel("Customer order id").fill(request.customerOrderId);
      await page.getByLabel("Card number").fill("4111111111111111");
      await page.getByLabel("Expiry month").fill("12");
      await page.getByLabel("Expiry year").fill("26");
      await page.getByLabel("CVV").fill("110");
      log("Submitting payment form.");
      await page.getByRole("button", { name: /Process payment/i }).click();

      const redirectHeading = page.getByRole("heading", { name: /Opening the provider OTP challenge/i });
      const callbackHeading = page.getByRole("heading", { name: /Review the final payment outcome/i });

      const nextState = await Promise.race([
        redirectHeading.waitFor({ timeout: 45000 }).then(() => "redirect" as const),
        callbackHeading.waitFor({ timeout: 45000 }).then(() => "callback" as const)
      ]);

      let challengeOutcome: ChallengeOutcome = "not-applicable";
      let threeDsSetting: ThreeDsSetting = "unknown";
      if (nextState === "redirect") {
        threeDsSetting = "enabled";
        log("3DS redirect state detected.");
        const continueLink = page.getByRole("link", { name: /Continue to secure verification now/i });
        const providerUrl = await continueLink.getAttribute("href").catch(() => null);
        if (providerUrl) {
          log(`Waiting for provider challenge via browser redirect to ${providerUrl}.`);
          await this.openProviderChallenge(page, continueLink, request.target.baseUrl, callbackHeading, log);
        }
        else if (await continueLink.count() > 0) {
          log("Opening provider challenge page via click fallback.");
          await continueLink.click();
          await page.waitForURL((url) => !url.toString().startsWith(request.target.baseUrl), { timeout: 60000 }).catch(() => undefined);
        }

        log(`Attempting sandbox OTP challenge with ${request.sandboxOtpCode}.`);
        challengeOutcome = await this.challengeHandler.execute(page, {
          tenantCode: request.tenantCode,
          sandboxOtpCode: request.sandboxOtpCode,
          diagnosticsDirectory: request.diagnosticsDirectory
        });
        log(`Challenge outcome: ${challengeOutcome}. Waiting for callback page.`);
        await page.waitForURL((url) => url.toString().startsWith(request.target.baseUrl), { timeout: 120000 }).catch(() => undefined);
        await callbackHeading.waitFor({ timeout: 120000 });
      }
      else {
        threeDsSetting = "disabled";
        log("Payment flow returned directly to callback page without provider challenge.");
      }

      const callbackSettled = await this.waitForCallbackSettlement(page, log);
      const statusBanner = page.locator("p.success-banner, p.error-banner, p.info-banner").first();
      const statusMessage = (await statusBanner.textContent().catch(() => null))?.trim() || "Payment flow reached callback page.";
      log(`Final callback status: ${statusMessage}`);

      return {
        journeyOutcome: callbackSettled ? "completed" : "callback-pending",
        challengeOutcome,
        threeDsSetting,
        finalUrl: page.url(),
        statusMessage
      };
    }
    finally {
      await browser.close();
    }
  }

  private async openProviderChallenge(
    page: import("playwright").Page,
    continueLink: import("playwright").Locator,
    appBaseUrl: string,
    callbackHeading: import("playwright").Locator,
    log: (message: string) => void
  ): Promise<void> {
    if (await this.waitForProviderOrCallback(page, appBaseUrl, callbackHeading)) {
      return;
    }

    if (await continueLink.count() > 0) {
      log("Automatic provider redirect did not settle; retrying via continue-link click.");
      await continueLink.click();
      if (await this.waitForProviderOrCallback(page, appBaseUrl, callbackHeading)) {
        return;
      }
    }

    throw new Error("Provider challenge did not become ready after automatic redirect and continue-link fallback.");
  }

  private async waitForProviderOrCallback(
    page: import("playwright").Page,
    appBaseUrl: string,
    callbackHeading: import("playwright").Locator
  ): Promise<boolean> {
    const providerForm = page.locator('form[name="form3DSecure"]').first();

    return Promise.race([
      providerForm.waitFor({ timeout: 45000 }).then(() => true),
      callbackHeading.waitFor({ timeout: 45000 }).then(() => true),
      page.waitForURL((url) => !url.toString().startsWith(appBaseUrl), { timeout: 45000 }).then(() => true)
    ]).catch(() => false);
  }

  private async waitForCallbackSettlement(
    page: import("playwright").Page,
    log: (message: string) => void
  ): Promise<boolean> {
    const loadingPanel = page.locator(".loading-progress-panel").first();
    const loadingVisible = await loadingPanel.isVisible().catch(() => false);
    if (!loadingVisible) {
      return true;
    }

    log("Callback page is still reconciling; waiting for final status.");

    const settled = await loadingPanel.waitFor({ state: "hidden", timeout: 60000 })
      .then(() => true)
      .catch(() => false);

    if (!settled) {
      log("Callback page did not finish reconciliation before the settlement timeout.");
    }

    return settled;
  }
}
