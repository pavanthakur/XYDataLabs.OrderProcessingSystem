import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import type { Frame, Locator, Page } from "playwright";
import type { ChallengeOutcome, ProviderChallengeContext } from "../contracts/provider-challenge-handler.js";

const otpSelectors = [
  'form[name="form3DSecure"] input[name="codevalidation"]',
  'input[name="codevalidation"]',
  'form[name="form3DSecure"] input[type="password"]',
  'input[type="password"]',
  'input[name*="otp" i]',
  'input[id*="otp" i]',
  'input[inputmode="numeric"]',
  'input[type="tel"]',
  'input[maxlength="3"]',
  'input[maxlength="4"]'
];

const submitButtonPatterns = [
  /continue/i,
  /submit/i,
  /confirm/i,
  /verify/i,
  /send/i,
  /enviar/i,
  /accept/i,
  /continuar/i,
  /aceptar/i,
  /pagar/i
];

const exactSubmitSelectors = [
  'form[name="form3DSecure"] #SendButton',
  'form[name="form3DSecure"] button[type="submit"]',
  'form[name="form3DSecure"] button',
  'button[type="submit"]',
  '#SendButton'
];

export class OpenPaySandboxChallengeHandler {
  public async execute(page: Page, context: ProviderChallengeContext): Promise<ChallengeOutcome> {
    const sandboxOtpCode = context.sandboxOtpCode?.trim() || "999";
    const diagnosticsDirectory = context.diagnosticsDirectory?.trim();

    try {
      await page.waitForLoadState("domcontentloaded", { timeout: 60000 });
      await this.captureDiagnostics(page, diagnosticsDirectory, "provider-loaded");

      const otpInput = await this.findOtpInput(page);
      if (!otpInput) {
        await this.captureDiagnostics(page, diagnosticsDirectory, "otp-input-missing");
        return "partial";
      }

      await otpInput.fill("");
      await otpInput.fill(sandboxOtpCode);
      await this.captureDiagnostics(page, diagnosticsDirectory, "otp-filled");

      const submitButton = await this.findSubmitButton(page);
      const preSubmitUrl = page.url();
      if (submitButton) {
        await submitButton.click();
      }
      else {
        await otpInput.press("Enter");
      }

      const submissionCompleted = await this.waitForSubmissionState(page, otpInput, preSubmitUrl);

      await this.captureDiagnostics(page, diagnosticsDirectory, "otp-submitted");

      return submissionCompleted ? "passed" : "partial";
    }
    catch {
      await this.captureDiagnostics(page, diagnosticsDirectory, "challenge-error");
      return "partial";
    }
  }

  private async findOtpInput(page: Page): Promise<Locator | null> {
    for (const frame of page.frames()) {
      for (const selector of otpSelectors) {
        const locator = frame.locator(selector).first();
        if (await locator.count() === 0) {
          continue;
        }

        if (await locator.isVisible().catch(() => false)) {
          return locator;
        }
      }
    }

    return null;
  }

  private async findSubmitButton(page: Page): Promise<Locator | null> {
    for (const frame of page.frames()) {
      for (const selector of exactSubmitSelectors) {
        const locator = frame.locator(selector).first();
        if (await locator.count() === 0) {
          continue;
        }

        if (await locator.isVisible().catch(() => false)) {
          return locator;
        }
      }

      for (const pattern of submitButtonPatterns) {
        const buttonLocator = frame.getByRole("button", { name: pattern }).first();
        if (await buttonLocator.count() > 0 && await buttonLocator.isVisible().catch(() => false)) {
          return buttonLocator;
        }

        const inputLocator = frame.locator('input[type="submit"], input[type="button"]').filter({ hasText: pattern }).first();
        if (await inputLocator.count() > 0 && await inputLocator.isVisible().catch(() => false)) {
          return inputLocator;
        }
      }
    }

    return null;
  }

  private async waitForSubmissionState(page: Page, otpInput: Locator, preSubmitUrl: string): Promise<boolean> {
    const navigationDetected = await page.waitForURL(
      (url) => url.toString() !== preSubmitUrl,
      { timeout: 30000 }
    ).then(() => true).catch(() => false);

    if (navigationDetected) {
      return true;
    }

    const inputHidden = await otpInput.waitFor({ state: "hidden", timeout: 5000 })
      .then(() => true)
      .catch(() => false);

    return inputHidden;
  }

  private async captureDiagnostics(page: Page, diagnosticsDirectory: string | undefined, stage: string): Promise<void> {
    if (!diagnosticsDirectory) {
      return;
    }

    await mkdir(diagnosticsDirectory, { recursive: true });

    const safeStage = stage.replace(/[^a-z0-9-]/gi, "-").toLowerCase();
    const pageTitle = await page.title().catch(() => "");
    const frameSnapshot = await Promise.all(page.frames().map((frame) => this.describeFrame(frame)));
    const html = await page.content().catch(() => "");

    await page.screenshot({
      path: path.join(diagnosticsDirectory, `${safeStage}.png`),
      fullPage: true
    }).catch(() => undefined);

    await writeFile(
      path.join(diagnosticsDirectory, `${safeStage}.json`),
      JSON.stringify({
        stage,
        url: page.url(),
        title: pageTitle,
        frames: frameSnapshot
      }, null, 2),
      "utf8"
    );

    await writeFile(path.join(diagnosticsDirectory, `${safeStage}.html`), html, "utf8");
  }

  private async describeFrame(frame: Frame): Promise<{ url: string; name: string; title: string; inputs: string[] }> {
    const inputs = await frame.locator("input").evaluateAll((elements) =>
      elements.map((element) => {
        const htmlElement = element as HTMLInputElement;
        return `${htmlElement.type || "text"}:${htmlElement.name || htmlElement.id || htmlElement.placeholder || "unnamed"}`;
      })
    ).catch(() => [] as string[]);

    const title = await frame.title().catch(() => "");

    return {
      url: frame.url(),
      name: frame.name(),
      title,
      inputs
    };
  }
}
