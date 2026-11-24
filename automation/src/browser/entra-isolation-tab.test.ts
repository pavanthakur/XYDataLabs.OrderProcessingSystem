import assert from "node:assert/strict";
import test from "node:test";
import { chromium } from "playwright";
import { openSameSessionTab } from "./entra-isolation-tab.js";

test("authenticated navigation and opener tabs retain tab session without copying credentials in the runner", async () => {
  const browser = await chromium.launch();
  try {
    const context = await browser.newContext();
    const origin = "https://isolation-fixture.example.test";
    await context.route(`${origin}/**`, route => route.fulfill({ contentType: "text/html", body: "<title>Fixture</title>" }));
    const page = await context.newPage();
    await page.goto(`${origin}/customers?tenantCode=TenantA`);
    await page.evaluate(() => sessionStorage.setItem("fixture-session", "present"));
    await page.goto(`${origin}/customers?tenantCode=TenantB`);
    assert.equal(await page.evaluate(() => sessionStorage.getItem("fixture-session")), "present");
    const unrelatedTab = await context.newPage();
    await unrelatedTab.goto(`${origin}/customers`);
    assert.equal(await unrelatedTab.evaluate(() => sessionStorage.getItem("fixture-session")), null);
    await assert.rejects(openSameSessionTab(page, "https://other.example.test/customers"), /application origin/);
    const sameSessionTab = await openSameSessionTab(page, `${origin}/customers?tenantCode=TenantA`);
    assert.equal(await sameSessionTab.evaluate(() => sessionStorage.getItem("fixture-session")), "present");
  } finally { await browser.close(); }
});
