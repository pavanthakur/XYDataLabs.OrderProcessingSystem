import assert from "node:assert/strict";
import test from "node:test";
import { chromium } from "playwright";
import { waitForCallbackOutcome } from "./callback-outcome.js";

test("browser callback guard rejects visible errors and waits for real success", async (t) => {
  const browser = await chromium.launch({ headless: true });
  t.after(() => browser.close());
  const page = await browser.newPage();

  await t.test("resource-not-found is a failure even with no loading panel", async () => {
    await page.setContent('<p class="error-banner">The requested resource was not found.</p>');
    assert.equal((await waitForCallbackOutcome(page, 1000)).state, "failed");
  });

  await t.test("missing initial loading panel does not race ahead of reconciliation", async () => {
    await page.setContent(`<main></main><script>
      setTimeout(() => { document.querySelector('main').innerHTML = '<div class="loading-progress-panel">Confirming</div>'; }, 30);
      setTimeout(() => { document.querySelector('main').innerHTML = '<p class="success-banner">Payment completed successfully.</p>'; }, 120);
    </script>`);
    const outcome = await waitForCallbackOutcome(page, 2000);
    assert.equal(outcome.state, "completed");
    assert.equal(outcome.message, "Payment completed successfully.");
  });

  await t.test("unresolved callback times out as pending, not completed", async () => {
    await page.setContent('<p class="info-banner">Waiting for provider confirmation.</p>');
    assert.equal((await waitForCallbackOutcome(page, 100)).state, "pending");
  });

  await t.test("page errors cannot be hidden by a stale success banner", async () => {
    await page.setContent('<p class="success-banner">Completed</p><p class="error-banner">Reconciliation failed.</p>');
    assert.equal((await waitForCallbackOutcome(page, 1000)).state, "failed");
  });
});
