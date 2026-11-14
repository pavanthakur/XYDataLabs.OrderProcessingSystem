import assert from "node:assert/strict";
import { test } from "node:test";
import { chromium } from "playwright";
import { completeRazorpayContactDetails } from "./razorpay-contact-details.js";

const phoneFixture = "9111191111";
const emailFixture = "sandbox@example.test";

test("Razorpay contact step validates sandbox phone and advances once before card entry", { timeout: 30000 }, async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await openContactFixture(page, true);
    const logs: string[] = [];

    await completeRazorpayContactDetails(page, phoneFixture, emailFixture, (message) => logs.push(message));

    const provider = page.frameLocator("#provider");
    assert.equal(await provider.getByText("Payment options").isVisible(), true);
    assert.deepEqual(logs, [
      "Completing Razorpay contact-details step.",
      "Razorpay contact details were accepted; continuing to the provider's payment options."
    ]);
  } finally {
    await browser.close();
  }
});

test("Razorpay contact step fails closed if provider rejects the phone fixture", { timeout: 30000 }, async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await openContactFixture(page, false);
    const provider = page.frameLocator("#provider");
    let continueClicks = 0;
    await provider.getByRole("button", { name: "Continue" }).evaluate((button) => {
      button.addEventListener("click", () => { document.body.dataset.continued = "true"; });
    });

    await assert.rejects(
      completeRazorpayContactDetails(page, phoneFixture, emailFixture, () => undefined),
      /did not retain the sandbox mobile number/
    );
    continueClicks = await provider.locator("body").evaluate((body) => body.dataset.continued === "true" ? 1 : 0);
    assert.equal(continueClicks, 0, "rejected contact input must not advance Razorpay checkout");
    assert.equal(await provider.getByText("Contact details").isVisible(), true);
  } finally {
    await browser.close();
  }
});

test("Razorpay contact-shaped form without a recognized heading is not mistaken for card entry", { timeout: 30000 }, async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await openContactFixture(page, true, "Continue securely");
    await assert.rejects(
      completeRazorpayContactDetails(page, phoneFixture, emailFixture, () => undefined),
      /unrecognized contact form/
    );
  } finally {
    await browser.close();
  }
});

async function openContactFixture(page: import("playwright").Page, acceptPhone: boolean, heading = "Contact details"): Promise<void> {
  const html = `<!doctype html><html><body>
    <section id="contact">
      <h1>${heading}</h1>
      <input type="tel" placeholder="Mobile number" aria-label="Mobile number">
      <p id="phone-error">Please enter your mobile number</p>
      <input type="email" placeholder="Email" aria-label="Email">
      <button type="button" disabled>Continue</button>
    </section>
    <script>
      const phone = document.querySelector('input[type="tel"]');
      const error = document.querySelector('#phone-error');
      const button = document.querySelector('button');
      phone.addEventListener('input', () => {
        ${acceptPhone ? "const valid = phone.value.replace(/\\D/g, '').length === 10;" : "phone.value = ''; const valid = false;"}
        error.hidden = valid;
        button.disabled = !valid;
      });
      button.addEventListener('click', () => {
        document.querySelector('#contact').hidden = true;
        const next = document.createElement('h2'); next.textContent = 'Payment options'; document.body.append(next);
      });
    </script>
  </body></html>`;
  await page.setContent('<iframe id="provider"></iframe>');
  await page.locator("#provider").evaluate((iframe, content) => {
    (iframe as HTMLIFrameElement).srcdoc = content;
  }, html);
  await page.frameLocator("#provider").getByText(heading).waitFor({ state: "visible" });
}
