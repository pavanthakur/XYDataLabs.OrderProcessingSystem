import type { Frame, Locator, Page } from "playwright";

type CheckoutScope = Page | Frame;

/**
 * Completes Razorpay's pre-card contact form once, validating the masked phone
 * input before continuing. This is contact capture, not an OTP/3DS challenge.
 */
export async function completeRazorpayContactDetails(
  page: Page,
  phone: string,
  email: string,
  log: (message: string) => void
): Promise<void> {
  const deadline = Date.now() + 15000;
  let scope: CheckoutScope | undefined;
  let heading: Locator | undefined;
  let unrecognizedContactForm = false;

  while (Date.now() < deadline && !scope) {
    for (const candidate of checkoutScopes(page)) {
      const marker = candidate.getByText(/^(Contact details|Enter mobile .* email to continue)$/i).first();
      const hasContactForm = await hasVisibleContactFields(candidate);
      if (hasContactForm && await marker.isVisible().catch(() => false)) {
        scope = candidate;
        heading = marker;
        break;
      }
      unrecognizedContactForm ||= hasContactForm;
    }
    if (!scope && unrecognizedContactForm) {
      throw new Error("Razorpay shows an unrecognized contact form; refusing to treat it as card entry or continue checkout.");
    }
    if (!scope) await page.waitForTimeout(200);
  }

  if (!scope || !heading) {
    log("Razorpay contact-details step was not shown.");
    return;
  }

  log("Completing Razorpay contact-details step.");
  const phoneInput = await findVisible(scope, [
    (candidate) => candidate.getByPlaceholder(/mobile number/i),
    (candidate) => candidate.locator('input[aria-label*="mobile" i]'),
    (candidate) => candidate.locator('input[type="tel"]'),
    (candidate) => candidate.locator('input[inputmode="tel"]'),
    (candidate) => candidate.locator('input[name*="phone" i]')
  ], "Razorpay mobile number");

  await phoneInput.fill(phone);
  await phoneInput.press("Tab").catch(() => undefined);

  const expectedDigits = phone.replace(/\D/g, "");
  const actualDigits = (await phoneInput.inputValue()).replace(/\D/g, "");
  if (!expectedDigits || !actualDigits.endsWith(expectedDigits)) {
    throw new Error("Razorpay did not retain the sandbox mobile number; checkout was not continued.");
  }

  const emailInput = await findVisible(scope, [
    (candidate) => candidate.locator('input[type="email"]'),
    (candidate) => candidate.locator('input[name*="email" i]'),
    (candidate) => candidate.getByPlaceholder(/email/i)
  ], "Razorpay contact email");
  await emailInput.fill(email);
  if ((await emailInput.inputValue()).trim().toLowerCase() !== email.trim().toLowerCase()) {
    throw new Error("Razorpay did not retain the checkout email; checkout was not continued.");
  }

  const mobileValidation = scope.getByText(/please enter your mobile number/i).first();
  const continueButton = scope.getByRole("button", { name: /^Continue$/i }).first();
  const validationDeadline = Date.now() + 5000;
  while (Date.now() < validationDeadline) {
    const validationVisible = await mobileValidation.isVisible().catch(() => false);
    const buttonReady = await continueButton.isVisible().catch(() => false)
      && await continueButton.isEnabled().catch(() => false);
    if (!validationVisible && buttonReady) break;
    await page.waitForTimeout(200);
  }

  if (await mobileValidation.isVisible().catch(() => false)) {
    throw new Error("Razorpay rejected the sandbox mobile number; checkout was not continued.");
  }
  if (!(await continueButton.isVisible().catch(() => false)) || !(await continueButton.isEnabled().catch(() => false))) {
    throw new Error("Razorpay contact form is not ready to continue; checkout was not submitted.");
  }

  // Submit this contact form once. Never retry a provider checkout transition.
  await continueButton.click();
  await heading.waitFor({ state: "hidden", timeout: 20000 }).catch(() => {
    throw new Error("Razorpay contact step did not advance after one Continue click; no card was submitted.");
  });
  log("Razorpay contact details were accepted; continuing to the provider's payment options.");
}

function checkoutScopes(page: Page): CheckoutScope[] {
  return page.context().pages().flatMap((candidatePage) => [candidatePage, ...candidatePage.frames()]);
}

async function hasVisibleContactFields(scope: CheckoutScope): Promise<boolean> {
  const phoneCandidate = scope.locator('input[type="tel"], input[inputmode="tel"], input[name*="phone" i]').first();
  const emailCandidate = scope.locator('input[type="email"], input[name*="email" i]').first();
  const continueCandidate = scope.getByRole("button", { name: /^Continue$/i }).first();
  return await phoneCandidate.isVisible().catch(() => false)
    && await emailCandidate.isVisible().catch(() => false)
    && await continueCandidate.isVisible().catch(() => false);
}

async function findVisible(scope: CheckoutScope, factories: Array<(scope: CheckoutScope) => Locator>, description: string): Promise<Locator> {
  for (const factory of factories) {
    const locator = factory(scope).first();
    if (await locator.isVisible().catch(() => false) && await locator.isEnabled().catch(() => false)) return locator;
  }
  throw new Error(`Unable to find an enabled ${description} in the Razorpay contact form.`);
}
