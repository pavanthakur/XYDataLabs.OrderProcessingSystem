import assert from "node:assert/strict";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { chromium, type Page } from "playwright";
import { JsonRuntimeTargetCatalog } from "../catalog/json-runtime-target-catalog.js";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");

test("Local identity: one admin session switches tenants; logout replaces it with isolated tenant accounts", { timeout: 240000 }, async (t) => {
  const target = await new JsonRuntimeTargetCatalog().resolve("docker-dev-http");
  const base = new URL(process.env.PHASE10_CUSTOMER_BASE_URL ?? target.baseUrl);
  assert.ok(["localhost", "127.0.0.1"].includes(base.hostname), "This test is local-only.");
  const envFile = await readFile(path.join(repoRoot, "Resources/Docker/.env.local"), "utf8");
  const line = envFile.split(/\r?\n/).find(value => value.startsWith("KEYCLOAK_TENANT_ADMIN_PASSWORD="));
  const password = process.env.KEYCLOAK_TENANT_ADMIN_PASSWORD ?? line?.slice(line.indexOf("=") + 1).trim().replace(/^["']|["']$/g, "");
  assert.ok(password && !password.startsWith("<"), "Configure the private local test password.");
  const root = process.env.PHASE10_RUN_ROOT ? path.join(process.env.PHASE10_RUN_ROOT, "customer-directory")
    : path.join(repoRoot, "TestResults/DockerStorage", `customer-directory-browser-${Date.now()}`);
  await mkdir(root, { recursive: true });
  const results: Record<string, unknown>[] = [];
  const headed = process.env.PHASE10_BROWSER_HEADED === "1";
  const browser = await chromium.launch({ headless: !headed, slowMo: headed ? 300 : 0 });
  const context = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await context.newPage();
  t.after(async () => {
    await writeFile(path.join(root, "summary.json"), JSON.stringify({ baseUrl: base.origin, results }, null, 2));
    await browser.close();
  });
  async function login(username: string) {
    await page.locator("#username").waitFor({ state: "visible" });
    await page.locator("#username").fill(username);
    await page.locator("#password").fill(password!);
    await page.getByRole("button", { name: /sign in/i }).click();
    await page.getByText(username, { exact: true }).waitFor();
  }
  async function ready(tenant: string) {
    await page.waitForFunction(() => [...document.querySelectorAll("dd")].some(node => node.textContent === "ready"));
    assert.equal(await page.locator(".tenant-picker select").inputValue(), tenant);
    assert.equal(await page.locator(".error-banner").count(), 0);
  }
  async function signOut(currentPage: Page) {
    await currentPage.getByRole("button", { name: "Sign out", exact: true }).click();
    await currentPage.waitForURL(`${base.origin}/signed-out`);
    await currentPage.getByRole("button", { name: "Sign in", exact: true }).waitFor();
    assert.equal(await currentPage.locator(".customer-link").count(), 0);
    assert.equal(await currentPage.locator(".error-banner").count(), 0);
  }
  try {
    const anonymous = await context.request.get(`${base.origin}/api/v1/Customer/GetAllCustomers`, {headers:{"X-Tenant-Code":"TenantA"}});
    assert.equal(anonymous.status(), 401, "Tenant data must require sign-in on every runtime.");
    const anonymousRuntime=await context.request.get(`${base.origin}/api/v1/Payments/runtime`,{headers:{"X-Tenant-Code":"TenantA"}});
    assert.equal(anonymousRuntime.status(),401,"Effective payment adapter diagnostics require sign-in.");
    await page.goto(`${base.origin}/payments/new?tenantCode=TenantA`);
    await login("tenant-admin");
    await page.getByRole("heading", {name:/Take a card payment|Collect payment/i}).waitFor();
    await page.waitForFunction(() => {
      return Boolean(document.querySelector('[role="alert"]')) || Boolean(document.querySelector('label.search-field select:not([disabled])'));
    });
    assert.equal(await page.locator(".error-banner").count(), 0, await page.locator(".error-banner").allTextContents().then(values=>values.join(" ")));
    assert.equal(await page.getByLabel("Customer for payment").isEnabled(), true);
    await page.getByRole("link", {name:"Customers",exact:true}).click();
    await ready("TenantA");
    let adminAuthorization: string | undefined;
    for (const tenant of ["TenantB", "TenantC", "TenantA"]) {
      const response = page.waitForResponse(r => new URL(r.url()).pathname.toLowerCase() === "/api/v1/customer/getallcustomers" && r.request().headers()["x-tenant-code"] === tenant);
      await page.locator(".tenant-picker select").selectOption(tenant);
      const customerResponse = await response;
      assert.equal(customerResponse.status(), 200);
      adminAuthorization = customerResponse.request().headers()["authorization"];
      await ready(tenant);
      results.push({ account: "tenant-admin", tenant, status: "passed", httpStatus: 200, customerCount: await page.locator(".customer-link").count() });
      await page.screenshot({ path: path.join(root, `admin-${tenant}.png`), fullPage: true });
    }
    await page.reload();
    await ready("TenantA");
    const otherTab = await context.newPage();
    await otherTab.goto(`${base.origin}/customers`);
    await otherTab.locator(".customer-link").first().waitFor();
    await signOut(page);
    assert.ok(adminAuthorization);
    const revoked = await context.request.get(`${base.origin}/api/v1/Customer/GetAllCustomers`, {headers:{Authorization:adminAuthorization,"X-Tenant-Code":"TenantA"}});
    assert.ok([401,403].includes(revoked.status()), "Provider logout must invalidate the old administrator token.");
    await otherTab.getByRole("button", { name: "Sign in", exact: true }).waitFor();
    await otherTab.close();
    for (const [username, tenant] of [["tenant-a-user", "TenantA"], ["tenant-b-user", "TenantB"], ["tenant-c-user", "TenantC"]]) {
      await page.getByRole("button", { name: "Sign in", exact: true }).click();
      await login(username!);
      await ready(tenant!);
      assert.equal(await page.locator(".tenant-picker option").count(), 1);
      assert.equal(await page.locator(".tenant-picker select").isDisabled(), true);
      const ownResponse = page.waitForResponse(r => new URL(r.url()).pathname.toLowerCase() === "/api/v1/customer/getallcustomers");
      await page.reload();
      const response = await ownResponse;
      assert.equal(response.status(), 200);
      await ready(tenant!);
      const deniedTenant = tenant === "TenantA" ? "TenantB" : "TenantA";
      const authorization = response.request().headers()["authorization"];
      assert.ok(authorization, "A real authenticated request is required.");
      const denied = await context.request.get(`${base.origin}/api/v1/Customer/GetAllCustomers`, { headers: { Authorization: authorization, "X-Tenant-Code": deniedTenant } });
      assert.equal(denied.status(), 403);
      results.push({ account: username, tenant, status: "passed", httpStatus: 200, deniedTenant, deniedStatus: 403, customerCount: await page.locator(".customer-link").count() });
      await page.screenshot({ path: path.join(root, `${tenant}.png`), fullPage: true });
      await signOut(page);
    }
    results.push({ scenario: "same-browser login/logout and cross-tab logout", status: "passed" });
  } catch (error) {
    const failureUrl = new URL(page.url());
    results.push({ scenario: "identity-browser", status: "failed", origin: failureUrl.origin, path: failureUrl.pathname,
      identityMessage: await page.locator("#input-error, .alert-error, .alert-warning, #kc-page-title").allTextContents() });
    if (page.url().startsWith(base.origin)) await page.screenshot({ path: path.join(root, "failure.png"), fullPage: true });
    throw new Error((error instanceof Error ? error.message : String(error)).replaceAll(password, "[REDACTED]"));
  } finally { console.log(`Identity browser evidence: ${root}`); }
});
