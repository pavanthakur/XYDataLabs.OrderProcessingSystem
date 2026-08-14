import path from "node:path";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { chromium, request as playwrightRequest } from "playwright";
import type { ChallengeOutcome } from "../contracts/provider-challenge-handler.js";
import type { ThreeDsSetting } from "../contracts/report-composer.js";
import type { RuntimeTargetDefinition } from "../contracts/runtime-target-catalog.js";
import { OpenPaySandboxChallengeHandler } from "./openpay-sandbox-challenge-handler.js";

type AutomationScope = import("playwright").Page | import("playwright").Frame;
type ScopeLocatorFactory = (scope: AutomationScope) => import("playwright").Locator;

const automationPayerName = "Automation Runner";
const automationPayerEmail = "abc@xyz.com";
const razorpayAutomationPhone = "9111191111";
const razorpayAutomationCardNumber = "4100280000001007";
const razorpayAutomationCardExpiry = "1244";
const razorpayAutomationCardCvv = "111";
const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const automationRoot = path.resolve(currentDirectory, "../..");
const workspaceRoot = path.resolve(automationRoot, "..");

async function readEnvelopeArray<T>(
  response: import("playwright").APIResponse
): Promise<T[]> {
  const payload = await response.json() as { data?: T[] };
  return Array.isArray(payload.data) ? payload.data : [];
}

interface PaymentConfigurationResponse {
  activeProviderType: string;
  activeProviderName: string;
  collectionMode: string;
  browserKey?: string | null;
  browserMerchantId?: string | null;
  isProduction: boolean;
}

export interface PaymentJourneyRequest {
  tenantCode: string;
  target: RuntimeTargetDefinition;
  customerOrderId: string;
  sandboxOtpCode: string;
  headless: boolean;
  requestedProvider?: string;
  diagnosticsDirectory?: string;
  logger?: (message: string) => void;
}

export interface PaymentJourneyResult {
  journeyOutcome: string;
  challengeOutcome: ChallengeOutcome;
  threeDsSetting: ThreeDsSetting;
  paymentProvider: string;
  customerOrderId: string;
  orderId: number;
  orderReferenceId: string;
  orderAmount: number;
  orderCurrencyCode: string;
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
      page.on("console", (message) => {
        const text = message.text();
        const messageType = message.type();

        if (this.usesLocalParityBrowserNoiseFilter(request.target) && this.isExpectedLocalParityConsoleNoise(text)) {
          log("[browser:expected] Suppressed expected local provider/browser diagnostic.");
          return;
        }

        if (this.usesAzureBrowserNoiseFilter(request.target) && this.isExpectedAzureConsoleNoise(text, messageType)) {
          log(`[browser:azure-suppressed] Suppressed expected Azure provider browser diagnostic (${messageType}).`);
          return;
        }

        log(`[browser:${messageType}] ${text}`);
      });
      page.on("pageerror", (error) => {
        log(`[browser:error] ${error.message}`);
      });
      page.on("requestfailed", (failedRequest) => {
        const url = failedRequest.url();
        const errorText = failedRequest.failure()?.errorText ?? "unknown";

        if (this.usesLocalParityBrowserNoiseFilter(request.target) && this.isExpectedLocalParityRequestNoise(url, errorText)) {
          log(`[browser:expected] Suppressed expected local provider/browser request diagnostic for ${this.describeExpectedBrowserNoiseTarget(url)}.`);
          return;
        }

        if (this.usesAzureBrowserNoiseFilter(request.target) && this.isExpectedAzureRequestNoise(url, errorText)) {
          return;
        }

        log(`[browser:requestfailed] ${failedRequest.method()} ${url} -> ${errorText}`);
      });
      page.on("response", (response) => {
        const url = response.url();
        if (this.usesLocalParityBrowserNoiseFilter(request.target) && url.includes("/payment/client-event") && response.status() === 404) {
          log("[browser:expected] Suppressed expected local telemetry callback settlement diagnostic.");
        }
      });
      const targetUrl = `${request.target.baseUrl}${request.target.paymentPagePath}?tenantCode=${encodeURIComponent(request.tenantCode)}`;

      log(`Navigating to ${targetUrl}.`);
      await page.goto(targetUrl, { waitUntil: "domcontentloaded" });
      await this.completeLocalKeycloakLogin(page, request, log);
      const accessToken = await this.waitForLocalAccessToken(page, request, log);
      await page.getByRole("heading", { name: /Take a card payment|Collect payment/i }).waitFor({ timeout: 30000 });
      log("Payment page is ready.");
      const paymentConfiguration = await this.resolvePaymentConfiguration(
        request,
        log,
        accessToken);
      const authoritativeOrder = await this.createAuthoritativeOrder(
        request,
        accessToken,
        paymentConfiguration.activeProviderType,
        log);
      const customerOrderId = `ORDER-${authoritativeOrder.orderId}`;
      const orderPaymentUrl =
        `${request.target.baseUrl}/customers/${authoritativeOrder.customerId}` +
        `/orders/${authoritativeOrder.orderId}/payment` +
        `?tenantCode=${encodeURIComponent(request.tenantCode)}`;
      log(
        `Opening persisted order ${authoritativeOrder.orderId} (${authoritativeOrder.orderReferenceId}) with authoritative amount ` +
        `${authoritativeOrder.totalPrice} ${authoritativeOrder.currencyCode}.`);
      await page.goto(orderPaymentUrl, { waitUntil: "domcontentloaded" });
      const orderHeading = page.getByRole("heading", { name: /Collect payment|Take a card payment/i });
      const orderErrorBanner = page.locator("p.error-banner").first();
      await Promise.any([
        orderHeading.waitFor({ timeout: 30000 }),
        orderErrorBanner.waitFor({ timeout: 30000 })
      ]).catch(async () => {
        log(`Order payment page did not settle after reopening persisted order. Current URL: ${page.url()}`);
        throw new Error("Order payment page did not become ready within the expected timeout.");
      });
      if (await orderErrorBanner.isVisible().catch(() => false)) {
        const statusMessage = (await orderErrorBanner.textContent().catch(() => null))?.trim() || "Order payment page reported an error.";
        throw new Error(statusMessage);
      }

      const tenantPicker = page.getByLabel("Tenant");
      if (await tenantPicker.count() > 0) {
        await tenantPicker.selectOption(request.tenantCode).catch(() => undefined);
      }

      log(`Filling payment form for ${customerOrderId}.`);
      await page.getByLabel("Cardholder name").fill(automationPayerName);
      await page.getByLabel("Email").fill(automationPayerEmail);
      await page.getByLabel("Customer order id").fill(customerOrderId);

      if (paymentConfiguration.collectionMode !== "provider_checkout") {
        await page.getByLabel("Card number").fill("4111111111111111");
        await page.getByLabel("Expiry month").fill("12");
        await page.getByLabel("Expiry year").fill("26");
        await page.getByLabel("CVV").fill("110");
      }

      log("Submitting payment form.");
      const submitButton = page.getByRole("button", {
        name: paymentConfiguration.collectionMode === "provider_checkout"
          ? new RegExp(`Continue to ${paymentConfiguration.activeProviderName}`, "i")
          : /Process payment/i
      });
      await submitButton.waitFor({ state: "visible", timeout: 30000 });
      await page.waitForFunction((button) => !(button as HTMLButtonElement).disabled, await submitButton.elementHandle(), {
        timeout: 30000
      }).catch(() => undefined);
      await submitButton.click();

      let razorpayMockBankChallengeRan = false;
      if (
        paymentConfiguration.collectionMode === "provider_checkout"
        && this.providersMatch(paymentConfiguration.activeProviderType, "Razorpay")
      ) {
        if (this.usesLocalRazorpayMock(request.target.baseUrl)) {
          log("Using local Razorpay mock callback path.");
          log("Expected local telemetry noise: /payment/client-event may abort while the callback settles.");
          const mockPaymentId = `local-razorpay-${customerOrderId}`;
          const callbackUrl = new URL("/payments/callback", request.target.baseUrl);
          callbackUrl.searchParams.set("tenantCode", request.tenantCode);
          callbackUrl.searchParams.set("source", "razorpay-local-mock");
          callbackUrl.searchParams.set("razorpay_payment_id", mockPaymentId);
          callbackUrl.searchParams.set("razorpay_order_id", mockPaymentId);
          await page.goto(callbackUrl.toString(), { waitUntil: "domcontentloaded" });
        }
        else {
          razorpayMockBankChallengeRan = await this.completeRazorpayHostedCheckout(page, automationPayerEmail, log);
        }
      }

      const callbackHeading = page.getByRole("heading", { name: /Review the final payment outcome/i });
      const paymentErrorBanner = page.locator("p.error-banner").first();
      const nextState = await this.waitForPostSubmitState(page, paymentConfiguration.collectionMode, callbackHeading, paymentErrorBanner, log);

      if (nextState === "error") {
        const statusMessage = (await paymentErrorBanner.textContent().catch(() => null))?.trim() || "Payment processing failed on the payment page.";
        log(`Payment flow failed on the payment page: ${statusMessage}`);
        throw new Error(statusMessage);
      }

      let challengeOutcome: ChallengeOutcome = "not-applicable";
      let threeDsSetting: ThreeDsSetting = "unknown";
      if (nextState === "redirect") {
        // OpenPay 3DS: redirect to provider challenge page
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
      else if (razorpayMockBankChallengeRan) {
        // Razorpay 3DS: bank challenge was handled inside the hosted checkout iframe
        threeDsSetting = "enabled";
        challengeOutcome = "passed";
        log("Razorpay mock bank 3DS challenge completed inside hosted checkout.");
      }
      else {
        threeDsSetting = "disabled";
        log("Payment flow returned directly to callback page without provider challenge.");
      }

      const callbackSettled = await this.waitForCallbackSettlement(page, log);
      const statusBanner = page.locator("p.success-banner, p.error-banner, p.info-banner").first();
      const statusMessage = (await statusBanner.textContent().catch(() => null))?.trim() || "Payment flow reached callback page.";
      if (request.target.runtime === "local" && statusMessage === "The requested resource was not found.") {
        log("Final callback status: expected local mock callback response was not found yet; callback settled through the local mock path.");
      }
      else {
        log(`Final callback status: ${statusMessage}`);
      }

      return {
        journeyOutcome: callbackSettled ? "completed" : "callback-pending",
        challengeOutcome,
        threeDsSetting,
        paymentProvider: paymentConfiguration.activeProviderType,
        customerOrderId,
        orderId: authoritativeOrder.orderId,
        orderReferenceId: authoritativeOrder.orderReferenceId,
        orderAmount: authoritativeOrder.totalPrice,
        orderCurrencyCode: authoritativeOrder.currencyCode,
        finalUrl: page.url(),
        statusMessage
      };
    }
    finally {
      await browser.close();
    }
  }

  private async resolvePaymentConfiguration(
    request: PaymentJourneyRequest,
    log: (message: string) => void,
    accessToken: string | null
  ): Promise<PaymentConfigurationResponse> {
    log(`Resolving payment configuration for ${request.tenantCode}.`);
    const apiBaseUrl = request.target.apiBaseUrl ?? request.target.baseUrl;
    const apiContext = await playwrightRequest.newContext({
      baseURL: apiBaseUrl,
      ignoreHTTPSErrors: request.target.ignoreHttpsErrors,
      extraHTTPHeaders: {
        "X-Tenant-Code": request.tenantCode,
        ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {})
      }
    });

    try {
      const response = await apiContext.get("/api/v1/Info/payment-configuration");
      if (!response.ok()) {
        const responseBody = await response.text().catch(() => "");
        const normalizedBody = responseBody.trim().replace(/\s+/g, " ");
        const responseDetail = normalizedBody.length > 0
          ? ` Response: ${normalizedBody.slice(0, 500)}`
          : "";
        throw new Error(`Payment configuration request failed with status ${response.status()}.${responseDetail}`);
      }

      const paymentConfiguration = await response.json() as PaymentConfigurationResponse;
      if (!paymentConfiguration.activeProviderType?.trim()) {
        throw new Error("Payment configuration response did not include an active provider type.");
      }

      if (
        request.requestedProvider
        && !this.providersMatch(request.requestedProvider, paymentConfiguration.activeProviderType)
      ) {
        throw new Error(
          `Requested provider ${request.requestedProvider} but API resolved ${paymentConfiguration.activeProviderType} for tenant ${request.tenantCode}.`
        );
      }

      log(
        `Resolved provider ${paymentConfiguration.activeProviderType} with collection mode ${paymentConfiguration.collectionMode}.`
      );

      return paymentConfiguration;
    }
    finally {
      await apiContext.dispose();
    }
  }

  private async waitForLocalAccessToken(
    page: import("playwright").Page,
    request: PaymentJourneyRequest,
    log: (message: string) => void
  ): Promise<string | null> {
    if (request.target.runtime === "azure") {
      return null;
    }

    const accessToken = await page.waitForFunction(() => {
      const token = window.localStorage.getItem("orderprocessing.accessToken");
      return typeof token === "string" && token.trim().length > 0 ? token : null;
    }, undefined, { timeout: 30000 })
      .then((result) => result.jsonValue() as Promise<string | null>)
      .catch(() => null);

    if (!accessToken) {
      log(`Local access token was not available after login for ${request.tenantCode}; proceeding without bearer auth.`);
      return null;
    }

    log(`Local access token is ready for ${request.tenantCode}.`);
    return accessToken;
  }

  private async completeLocalKeycloakLogin(
    page: import("playwright").Page,
    request: PaymentJourneyRequest,
    log: (message: string) => void
  ): Promise<void> {
    if (request.target.runtime === "azure") {
      return;
    }

    let password = process.env.KEYCLOAK_TENANT_ADMIN_PASSWORD
      ?? process.env.LOCAL_KEYCLOAK_TEST_PASSWORD
      ?? process.env.LOCAL_KEYCLOAK_ADMIN_PASSWORD;
    if (!password) {
      const envLocalPath = path.join(workspaceRoot, "Resources", "Docker", ".env.local");
      const envLocalText = await readFile(envLocalPath, "utf8").catch(() => "");
      const passwordLine = envLocalText
        .split(/\r?\n/)
        .find((line) => {
          const trimmed = line.trim();
          return trimmed.startsWith("KEYCLOAK_TENANT_ADMIN_PASSWORD=")
            || trimmed.startsWith("LOCAL_KEYCLOAK_ADMIN_PASSWORD=");
        });

      if (!passwordLine) {
        throw new Error(
          "KEYCLOAK_TENANT_ADMIN_PASSWORD, LOCAL_KEYCLOAK_TEST_PASSWORD, or LOCAL_KEYCLOAK_ADMIN_PASSWORD is required for the local PKCE browser matrix.");
      }

      password = passwordLine.split("=", 2)[1].trim().replace(/^["']|["']$/g, "");
    }

    const normalizedTenant = request.tenantCode.trim().toLowerCase();
    const username = normalizedTenant === "tenantb"
      ? "tenant-b-user"
      : normalizedTenant === "tenantc"
        ? "tenant-c-user"
        : "tenant-admin";

    const entryState = await Promise.race([
      page.waitForURL((url) => url.toString().includes("/realms/xy-phase9/"), { timeout: 15000 }).then(() => "auth" as const),
      page.getByRole("heading", { name: /Take a card payment|Collect payment/i }).waitFor({ timeout: 15000 }).then(() => "app" as const)
    ]).catch(() => "unknown" as const);

    if (entryState === "app") {
      log(`Local payment page is already ready for ${request.tenantCode}; Keycloak login is not required.`);
      return;
    }

    if (entryState === "unknown" && !page.url().includes("/realms/xy-phase9/")) {
      await page.waitForURL((url) => url.toString().includes("/realms/xy-phase9/"), { timeout: 10000 }).catch(() => undefined);
    }

    if (!page.url().includes("/realms/xy-phase9/")) {
      return;
    }

    log(`Authenticating ${request.tenantCode} through Keycloak Authorization Code + PKCE as ${username}.`);
    const usernameField = page.locator("#username");
    const passwordField = page.locator("#password");
    await usernameField.waitFor({ timeout: 15000 });
    await passwordField.waitFor({ timeout: 15000 });
    await usernameField.fill(username);
    await passwordField.fill(password);
    await page.getByRole("button", { name: /sign in/i }).click();
    await page.waitForURL(
      (url) => url.toString().startsWith(request.target.baseUrl),
      { timeout: 60000 });
    log(`Keycloak PKCE authentication completed for ${request.tenantCode}.`);
  }

  private async createAuthoritativeOrder(
    request: PaymentJourneyRequest,
    accessToken: string | null,
    providerType: string,
    log: (message: string) => void
  ): Promise<{ customerId: number; orderId: number; orderReferenceId: string; totalPrice: number; currencyCode: string }> {
    const apiBaseUrl = request.target.apiBaseUrl ?? request.target.baseUrl;
    const api = await playwrightRequest.newContext({
      baseURL: apiBaseUrl,
      ignoreHTTPSErrors: request.target.ignoreHttpsErrors,
      extraHTTPHeaders: {
        "X-Tenant-Code": request.tenantCode,
        ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {})
      }
    });

    try {
      const productsResponse = await api.get("/api/v1/Product/GetAllProducts");
      if (!productsResponse.ok()) {
        throw new Error(
          `Unable to resolve seeded order products. status=${productsResponse.status()}.`);
      }

      const products = await readEnvelopeArray<{ productId: number }>(
        productsResponse);
      const product = products[0];
      if (!product) {
        throw new Error(
          `Tenant ${request.tenantCode} has no seeded product for the payment proof.`);
      }

      const uniqueSuffix = `${Date.now()}-${crypto.randomUUID().slice(0, 8)}`;
      const customerResponse = await api.post("/api/v1/Customer", {
        headers: { "Content-Type": "application/json" },
        data: {
          name: `${automationPayerName} ${request.tenantCode}`,
          email: `phase10-${request.tenantCode}-${uniqueSuffix}@example.local`
        }
      });
      if (!customerResponse.ok()) {
        throw new Error(
          `Authoritative customer creation failed with status ${customerResponse.status()}.`);
      }
      const customerPayload = await customerResponse.json() as { data?: number };
      if (!customerPayload.data) {
        throw new Error("Authoritative customer response did not include a customer id.");
      }

      const createResponse = await api.post("/api/v1/Order", {
        headers: { "Content-Type": "application/json" },
        data: {
          customerId: customerPayload.data,
          productIds: [product.productId],
          currencyCode: this.providersMatch(providerType, "Razorpay")
            ? "INR"
            : "MXN"
        }
      });
      if (!createResponse.ok()) {
        throw new Error(
          `Authoritative order creation failed with status ${createResponse.status()}.`);
      }

      const payload = await createResponse.json() as {
        data?: { orderId?: number; orderReferenceId?: string; totalPrice?: number; currencyCode?: string };
      };
      if (!payload.data?.orderId || !payload.data.totalPrice) {
        throw new Error("Authoritative order response did not include order id and amount.");
      }

      const orderReferenceId = payload.data.orderReferenceId?.trim() || `ORDER-${payload.data.orderId}`;
      const currencyCode = payload.data.currencyCode?.trim().toUpperCase() || (this.providersMatch(providerType, "Razorpay") ? "INR" : "MXN");

      log(
        `Persisted order ${payload.data.orderId} for customer ${customerPayload.data} ` +
        `with amount ${payload.data.totalPrice} ${currencyCode} and reference ${orderReferenceId}.`);
      return {
        customerId: customerPayload.data,
        orderId: payload.data.orderId,
        orderReferenceId,
        totalPrice: payload.data.totalPrice,
        currencyCode
      };
    }
    finally {
      await api.dispose();
    }
  }

  private providersMatch(left: string, right: string): boolean {
    return left.trim().localeCompare(right.trim(), undefined, { sensitivity: "accent" }) === 0;
  }

  private usesLocalRazorpayMock(baseUrl?: string | null): boolean {
    if (!baseUrl) {
      return false;
    }

    try {
      const parsed = new URL(baseUrl);
      return parsed.hostname === "localhost" || parsed.hostname === "127.0.0.1";
    }
    catch {
      return false;
    }
  }

  private async waitForPostSubmitState(
    page: import("playwright").Page,
    collectionMode: string,
    callbackHeading: import("playwright").Locator,
    paymentErrorBanner: import("playwright").Locator,
    log: (message: string) => void
  ): Promise<"redirect" | "callback" | "error"> {
    if (collectionMode === "provider_checkout") {
      return Promise.any([
        page.waitForURL(/\/payments\/callback/i, { timeout: 60000 }).then(async () => {
          await callbackHeading.waitFor({ timeout: 60000 });
          return "callback" as const;
        }),
        paymentErrorBanner.waitFor({ timeout: 60000 }).then(() => "error" as const)
      ]).catch(async () => {
        log(`Provider checkout did not reach the callback page. Current URL: ${page.url()}`);
        throw new Error("Provider checkout did not reach the callback page within the expected timeout.");
      });
    }

    const redirectHeading = page.getByRole("heading", { name: /Opening the provider OTP challenge/i });
    return Promise.any([
      redirectHeading.waitFor({ timeout: 45000 }).then(() => "redirect" as const),
      callbackHeading.waitFor({ timeout: 45000 }).then(() => "callback" as const),
      paymentErrorBanner.waitFor({ timeout: 45000 }).then(() => "error" as const)
    ]).catch(async () => {
      log(`Payment flow did not reach redirect, callback, or error state. Current URL: ${page.url()}`);
      throw new Error("Payment flow did not reach a recognizable post-submit state within the expected timeout.");
    });
  }

  /**
   * Drives the Razorpay hosted checkout flow and returns whether the mock bank 3DS challenge
   * was presented and completed (true) or whether the checkout was already settled (false, meaning
   * Razorpay skipped the 3DS step for this card/configuration).
   */
  private async completeRazorpayHostedCheckout(
    page: import("playwright").Page,
    payerEmail: string,
    log: (message: string) => void
  ): Promise<boolean> {
    const callbackHeading = page.getByRole("heading", { name: /Review the final payment outcome/i });
    if (await callbackHeading.isVisible().catch(() => false)) {
      log("Razorpay callback page is already visible; hosted checkout steps are not required.");
      return false;
    }

    log("Waiting for Razorpay hosted checkout UI.");
    await this.fillRazorpayContactDetails(page, payerEmail, log);
    await this.fillRazorpayCardDetails(page, log);
    await this.dismissRazorpaySaveCardPrompt(page, log);
    await this.completeRazorpayMockBankChallenge(page, log);
    return true;
  }

  private async fillRazorpayContactDetails(
    page: import("playwright").Page,
    payerEmail: string,
    log: (message: string) => void
  ): Promise<void> {
    const contactScope = await this.tryFindScope(page, [
      (scope) => scope.getByText(/Contact details/i),
      (scope) => scope.getByText(/Enter mobile .* email to continue/i)
    ], 15000, "Razorpay contact details");

    if (!contactScope) {
      log("Razorpay contact-details step was not shown.");
      return;
    }

    log("Completing Razorpay contact-details step.");
    await this.fillVisibleInput(page, [
      (scope) => scope.locator('input[type="tel"]').first(),
      (scope) => scope.locator('input[inputmode="tel"]').first(),
      (scope) => scope.locator('input[name*="phone"]').first(),
      (scope) => scope.locator('input[name*="contact"]').first()
    ], razorpayAutomationPhone, 10000, "Razorpay phone");

    await this.fillVisibleInput(page, [
      (scope) => scope.locator('input[type="email"]').first(),
      (scope) => scope.locator('input[name*="email"]').first(),
      (scope) => scope.getByPlaceholder(/email/i).first()
    ], payerEmail, 10000, "Razorpay email");

    await this.clickWithinScope(contactScope.scope, [
      (scope) => scope.getByRole("button", { name: /^Continue$/i }),
      (scope) => scope.getByText(/^Continue$/i)
    ], "Razorpay contact-details continue");
  }

  private async fillRazorpayCardDetails(
    page: import("playwright").Page,
    log: (message: string) => void
  ): Promise<void> {
    await this.tryClickVisible(page, [
      (scope) => scope.getByText(/^Cards$/i),
      (scope) => scope.getByRole("tab", { name: /^Cards$/i })
    ], 10000);

    let cardScope: { scope: AutomationScope; label: string };
    try {
      cardScope = await this.findScope(page, [
        (scope) => scope.getByText(/Add a new card/i),
        (scope) => scope.getByText(/Payment Options/i),
        (scope) => scope.getByText(/Debit \/ Credit Card/i),
        (scope) => scope.getByText(/Cards/i)
      ], 20000, "Razorpay card entry");
    }
    catch {
      log("Razorpay card section labels were not found; falling back to generic card input discovery.");
      try {
        cardScope = await this.findScope(page, [
          (scope) => scope.locator('input[autocomplete="cc-number"]').first(),
          (scope) => scope.locator('input[name="card[number]"]').first(),
          (scope) => scope.locator('input[name*="card"]').first(),
          (scope) => scope.locator('input[placeholder*="card" i]').first(),
          (scope) => scope.locator('input[type="tel"]').first()
        ], 20000, "Razorpay generic card input");
      }
      catch {
        const callbackHeading = page.getByRole("heading", { name: /Review the final payment outcome/i });
        if (await callbackHeading.isVisible().catch(() => false)) {
          log("Razorpay checkout already transitioned to the callback page; card entry was not required.");
          return;
        }

        log(`Razorpay checkout surfaces at failure: ${JSON.stringify(await this.describeAutomationSurfaces(page))}`);
        throw new Error("Unable to locate Razorpay hosted checkout card entry or callback page.");
      }
    }

    log(`Completing Razorpay card entry in ${cardScope.label}.`);

    const cardNumberFilled = await this.tryFillWithinScope(cardScope.scope, [
      (scope) => scope.locator('input[autocomplete="cc-number"]').first(),
      (scope) => scope.locator('input[name="card[number]"]').first(),
      (scope) => scope.getByPlaceholder(/card/i).first()
    ], razorpayAutomationCardNumber, true);

    const expiryFilled = await this.tryFillWithinScope(cardScope.scope, [
      (scope) => scope.locator('input[autocomplete="cc-exp"]').first(),
      (scope) => scope.locator('input[name="card[expiry]"]').first(),
      (scope) => scope.getByPlaceholder(/MM/i).first()
    ], razorpayAutomationCardExpiry, true);

    const cvvFilled = await this.tryFillWithinScope(cardScope.scope, [
      (scope) => scope.locator('input[autocomplete="cc-csc"]').first(),
      (scope) => scope.locator('input[name="card[cvv]"]').first(),
      (scope) => scope.getByPlaceholder(/CVV/i).first()
    ], razorpayAutomationCardCvv, true);

    if (!cardNumberFilled || !expiryFilled || !cvvFilled) {
      await this.fillCardInputsByOrder(cardScope.scope);
    }

    for (let attempt = 1; attempt <= 3; attempt += 1) {
      await this.clickWithinScope(cardScope.scope, [
        (scope) => scope.getByRole("button", { name: /^Continue$/i }),
        (scope) => scope.getByText(/^Continue$/i)
      ], "Razorpay card continue");

      if (await this.waitForRazorpayPostCardAdvance(page, 6000)) {
        return;
      }

      log(`Razorpay card submit attempt ${attempt} did not advance the checkout yet.`);
    }

    throw new Error("Razorpay checkout did not advance after card submission.");
  }

  private async dismissRazorpaySaveCardPrompt(
    page: import("playwright").Page,
    log: (message: string) => void
  ): Promise<void> {
    const dismissed = await this.tryClickVisible(page, [
      (scope) => scope.getByRole("button", { name: /Maybe later/i }),
      (scope) => scope.getByText(/Maybe later/i)
    ], 10000);

    if (dismissed) {
      log("Dismissed the optional Razorpay save-card prompt.");
    }
  }

  private async completeRazorpayMockBankChallenge(
    page: import("playwright").Page,
    log: (message: string) => void
  ): Promise<void> {
    let mockBankSurface: { scope: AutomationScope; label: string };

    try {
      mockBankSurface = await this.findScope(page, [
        (scope) => scope.getByText(/Welcome to Razorpay Software Private Ltd Bank/i),
        (scope) => scope.getByText(/This is just a demo bank page/i),
        (scope) => scope.getByRole("button", { name: /^Success$/i })
      ], 45000, "Razorpay mock bank page");
    }
    catch (error) {
      const surfaceSummary = await this.describeAutomationSurfaces(page);
      log(`Razorpay mock bank page was not found. Visible surfaces: ${JSON.stringify(surfaceSummary)}`);
      throw error;
    }

    log(`Completing Razorpay mock bank success step in ${mockBankSurface.label}.`);
    await this.clickWithinScope(mockBankSurface.scope, [
      (scope) => scope.getByRole("button", { name: /^Success$/i }),
      (scope) => scope.getByText(/^Success$/i)
    ], "Razorpay mock bank success");
  }

  private async fillCardInputsByOrder(scope: AutomationScope): Promise<void> {
    const inputs = scope.locator('input:not([type="radio"]):not([type="checkbox"]):not([type="hidden"]):not([type="button"]):not([type="submit"])');
    const visibleInputs: import("playwright").Locator[] = [];

    for (let index = 0; index < await inputs.count(); index += 1) {
      const candidate = inputs.nth(index);
      const isVisible = await candidate.isVisible().catch(() => false);
      const inputType = (await candidate.getAttribute("type").catch(() => null))?.toLowerCase() ?? "text";
      if (isVisible && !["radio", "checkbox", "hidden", "button", "submit"].includes(inputType)) {
        visibleInputs.push(candidate);
      }
    }

    if (visibleInputs.length < 3) {
      throw new Error("Unable to identify Razorpay card entry inputs.");
    }

    await this.typeIntoInput(visibleInputs[0], razorpayAutomationCardNumber);
    await this.typeIntoInput(visibleInputs[1], razorpayAutomationCardExpiry);
    await this.typeIntoInput(visibleInputs[2], razorpayAutomationCardCvv);
  }

  private async fillVisibleInput(
    page: import("playwright").Page,
    factories: ScopeLocatorFactory[],
    value: string,
    timeoutMs: number,
    description: string
  ): Promise<void> {
    const located = await this.findVisibleLocator(page, factories, timeoutMs, description);
    await located.locator.fill(value);
  }

  private async clickVisible(
    page: import("playwright").Page,
    factories: ScopeLocatorFactory[],
    timeoutMs: number,
    description: string
  ): Promise<void> {
    const located = await this.findVisibleLocator(page, factories, timeoutMs, description);
    await located.locator.click();
  }

  private async tryClickVisible(
    page: import("playwright").Page,
    factories: ScopeLocatorFactory[],
    timeoutMs: number
  ): Promise<boolean> {
    try {
      const located = await this.findVisibleLocator(page, factories, timeoutMs);
      await located.locator.click();
      return true;
    }
    catch {
      return false;
    }
  }

  private async tryFindScope(
    page: import("playwright").Page,
    factories: ScopeLocatorFactory[],
    timeoutMs: number,
    description: string
  ): Promise<{ scope: AutomationScope; label: string } | null> {
    try {
      return await this.findScope(page, factories, timeoutMs, description);
    }
    catch {
      return null;
    }
  }

  private async clickWithinScope(
    scope: AutomationScope,
    factories: ScopeLocatorFactory[],
    description: string
  ): Promise<void> {
    for (const factory of factories) {
      const locator = factory(scope).first();
      if (await locator.isVisible().catch(() => false)) {
        await locator.click();
        return;
      }
    }

    throw new Error(`Unable to click ${description}.`);
  }

  private async tryFillWithinScope(
    scope: AutomationScope,
    factories: ScopeLocatorFactory[],
    value: string,
    useSequentialTyping = false
  ): Promise<boolean> {
    for (const factory of factories) {
      const locator = factory(scope).first();
      if (await locator.isVisible().catch(() => false)) {
        if (useSequentialTyping) {
          await this.typeIntoInput(locator, value);
        }
        else {
          await locator.fill(value);
        }
        return true;
      }
    }

    return false;
  }

  private async typeIntoInput(locator: import("playwright").Locator, value: string): Promise<void> {
    await locator.click();
    await locator.fill("");
    await locator.pressSequentially(value, { delay: 40 });
    await locator.press("Tab").catch(() => undefined);
  }

  private async waitForRazorpayPostCardAdvance(
    page: import("playwright").Page,
    timeoutMs: number
  ): Promise<boolean> {
    const deadline = Date.now() + timeoutMs;

    while (Date.now() < deadline) {
      for (const surface of this.listAutomationSurfaces(page)) {
        const maybeLaterVisible = await surface.scope.getByText(/Maybe later/i).first().isVisible().catch(() => false);
        const successVisible = await surface.scope.getByRole("button", { name: /^Success$/i }).first().isVisible().catch(() => false);
        const callbackVisible = await surface.scope.getByRole("heading", { name: /Review the final payment outcome/i }).first().isVisible().catch(() => false);

        if (maybeLaterVisible || successVisible || callbackVisible) {
          return true;
        }
      }

      await page.waitForTimeout(250);
    }

    return false;
  }

  private async findScope(
    page: import("playwright").Page,
    factories: ScopeLocatorFactory[],
    timeoutMs: number,
    description: string
  ): Promise<{ scope: AutomationScope; label: string }> {
    const located = await this.findVisibleLocator(page, factories, timeoutMs, description);
    return { scope: located.scope, label: located.label };
  }

  private async findVisibleLocator(
    page: import("playwright").Page,
    factories: ScopeLocatorFactory[],
    timeoutMs: number,
    description?: string
  ): Promise<{ scope: AutomationScope; locator: import("playwright").Locator; label: string }> {
    const deadline = Date.now() + timeoutMs;

    while (Date.now() < deadline) {
      for (const surface of this.listAutomationSurfaces(page)) {
        for (const factory of factories) {
          const locator = factory(surface.scope).first();
          if (await locator.isVisible().catch(() => false)) {
            return { scope: surface.scope, locator, label: surface.label };
          }
        }
      }

      await page.waitForTimeout(250);
    }

    throw new Error(description
      ? `Unable to find ${description} within ${timeoutMs}ms.`
      : `Unable to find a visible automation target within ${timeoutMs}ms.`);
  }

  private listAutomationSurfaces(page: import("playwright").Page): Array<{ scope: AutomationScope; label: string }> {
    const surfaces: Array<{ scope: AutomationScope; label: string }> = [];

    for (const candidatePage of page.context().pages()) {
      surfaces.push({ scope: candidatePage, label: `page:${candidatePage.url() || "about:blank"}` });

      for (const frame of candidatePage.frames()) {
        surfaces.push({ scope: frame, label: `frame:${frame.url() || "about:blank"}` });
      }
    }

    return surfaces;
  }

  private async describeAutomationSurfaces(page: import("playwright").Page): Promise<Array<Record<string, unknown>>> {
    const descriptions: Array<Record<string, unknown>> = [];

    for (const surface of this.listAutomationSurfaces(page)) {
      descriptions.push({
        label: surface.label,
        contact: await surface.scope.getByText(/Contact details/i).first().isVisible().catch(() => false),
        paymentOptions: await surface.scope.getByText(/Payment Options/i).first().isVisible().catch(() => false),
        addCard: await surface.scope.getByText(/Add a new card/i).first().isVisible().catch(() => false),
        maybeLater: await surface.scope.getByText(/Maybe later/i).first().isVisible().catch(() => false),
        secureMyCard: await surface.scope.getByText(/secure my card/i).first().isVisible().catch(() => false),
        orderSummary: await surface.scope.getByText(/order summary/i).first().isVisible().catch(() => false),
        payNow: await surface.scope.getByText(/^Pay( now)?$/i).first().isVisible().catch(() => false),
        success: await surface.scope.getByRole("button", { name: /^Success$/i }).first().isVisible().catch(() => false),
        failure: await surface.scope.getByRole("button", { name: /^Failure$/i }).first().isVisible().catch(() => false),
        continueButton: await surface.scope.getByRole("button", { name: /^Continue$/i }).first().isVisible().catch(() => false)
      });
    }

    return descriptions;
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

  private usesLocalParityBrowserNoiseFilter(target: RuntimeTargetDefinition): boolean {
    return target.runtime === "local" || target.runtime === "docker";
  }

  private usesAzureBrowserNoiseFilter(target: RuntimeTargetDefinition): boolean {
    return target.runtime === "azure";
  }

  private isExpectedAzureConsoleNoise(text: string, messageType: string): boolean {
    // Browser console group events (startGroup/endGroup) from provider SDKs such as
    // Razorpay's PerimeterX anti-bot script are not actionable and should not surface.
    if (messageType === "startGroup" || messageType === "endGroup") {
      return true;
    }

    // Razorpay's checkout iframe generates Mixed Content warnings when the payment page
    // is served over HTTPS but Razorpay's frame loads sub-resources from HTTP or from
    // domains that refuse cross-origin connections in the sandbox environment.
    if (messageType === "warning" && text.includes("Mixed Content")) {
      return true;
    }

    // WebGL GPU stall warnings from the headless Chromium renderer are runner-environment
    // noise and carry no signal about payment flow correctness.
    if (messageType === "warning" && text.includes("GL Driver Message") && text.includes("GPU stall")) {
      return true;
    }

    // ERR_CONNECTION_REFUSED errors logged as browser console errors originate from
    // Razorpay's checkout frame trying to reach local/sandbox broker endpoints that
    // are not available in the Azure runner environment.
    if (messageType === "error" && text.includes("Failed to load resource: net::ERR_CONNECTION_REFUSED")) {
      return true;
    }

    // Razorpay's checkout iframe attempts to read cross-origin response headers that
    // browsers block by policy. These CORS-policy violations are expected sandbox noise.
    if (messageType === "error" && text.includes("Refused to get unsafe header")) {
      return true;
    }

    // OpenPay sandbox resources emit 401/404 errors with an empty reason phrase
    // (e.g. "status of 401 ()") due to CORS and auth restrictions in the Azure
    // runner environment. These differ from application-level auth errors which
    // include a non-empty reason phrase such as "(Unauthorized)" or "(Not Found)".
    if (
      messageType === "error" && (
        text.includes("Failed to load resource: the server responded with a status of 401 ()") ||
        text.includes("Failed to load resource: the server responded with a status of 404 ()")
      )
    ) {
      return true;
    }

    // Sift Science fraud-detection SDK diagnostic emitted by OpenPay's direct-card form.
    if (messageType === "log" && text.includes("executing sift mode")) {
      return true;
    }

    // Razorpay's checkout iframe declares permissions-policy features (accelerometer,
    // devicemotion, deviceorientation, web-share) that the headless Chromium runner does
    // not grant. These policy violations and unrecognised-feature warnings carry no signal
    // about payment flow correctness.
    if (
      (messageType === "error" && text.includes("Permissions policy violation:")) ||
      (messageType === "warning" && text.includes("Unrecognized feature:")) ||
      (messageType === "warning" && text.includes("devicemotion events are blocked by permissions policy")) ||
      (messageType === "warning" && text.includes("deviceorientation events are blocked by permissions policy"))
    ) {
      return true;
    }

    return false;
  }

  private isExpectedAzureRequestNoise(url: string, errorText: string): boolean {
    // UI telemetry events abort during provider redirect — expected and harmless.
    if (url.includes("/payment/client-event") && errorText === "net::ERR_ABORTED") {
      return true;
    }

    // Razorpay's PerimeterX anti-bot SDK probes random localhost ports with numeric PNG
    // paths (e.g. http://localhost:37857/1901812.png) to fingerprint the runner environment.
    // These connection-refused failures are structural noise that will never succeed on a
    // CI runner and carry no signal about the payment flow.
    if (errorText === "net::ERR_CONNECTION_REFUSED") {
      try {
        const parsedUrl = new URL(url);
        if (parsedUrl.hostname === "localhost" || parsedUrl.hostname === "127.0.0.1") {
          return true;
        }
      }
      catch {
        // malformed URL — fall through
      }
    }

    // hCaptcha and other 3rd-party SDK resources abort or are blocked by ORB when the
    // checkout frame navigates away during the payment flow. ERR_BLOCKED_BY_ORB is
    // generated when Chromium's Opaque Response Blocking policy blocks a cross-origin
    // resource (e.g. a Razorpay CDN JS bundle fetched from a next-generation CDN host).
    if (
      errorText === "net::ERR_ABORTED" ||
      errorText === "net::ERR_CONNECTION_REFUSED" ||
      errorText === "net::ERR_BLOCKED_BY_ORB"
    ) {
      let hostname = "";
      try {
        hostname = new URL(url).hostname;
      }
      catch {
        return false;
      }

      if (
        hostname === "hcaptcha.com" || hostname.endsWith(".hcaptcha.com") ||
        hostname === "razorpay.com" || hostname.endsWith(".razorpay.com") ||
        hostname === "checkout-static.razorpay.com" || hostname.endsWith(".checkout-static.razorpay.com")
      ) {
        return true;
      }
    }

    return false;
  }

  private isExpectedLocalParityRequestNoise(url: string, errorText: string): boolean {
    return (
      url.startsWith("https://js.openpay.mx/") ||
      (url.includes("/payment/client-event") && errorText === "net::ERR_ABORTED")
    );
  }

  private isExpectedLocalParityConsoleNoise(text: string): boolean {
    return (
      text.includes("Failed to load resource: net::ERR_NAME_NOT_RESOLVED") ||
      text.includes("Failed to load resource: net::ERR_NETWORK_ACCESS_DENIED") ||
      text.includes("Failed to load resource: the server responded with a status of 401 (Unauthorized)") ||
      text.includes("Failed to load resource: the server responded with a status of 404 (Not Found)")
    );
  }

  private describeExpectedBrowserNoiseTarget(url: string): string {
    if (url.startsWith("https://js.openpay.mx/")) {
      return "OpenPay browser SDK";
    }

    if (url.includes("/payment/client-event")) {
      return "local telemetry callback";
    }

    return "local browser dependency";
  }
}
