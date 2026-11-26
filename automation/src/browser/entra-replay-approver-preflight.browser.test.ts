import assert from "node:assert/strict";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { chromium, request as playwrightRequest, type Page } from "playwright";
import { isAppSignedOutUrl, isCustomerListUrl, resolveBrowserApiOrigin } from "./entra-isolation-observation.js";
import { assertReplayApproverToken, type ReplayApproverTokenExpectation } from "../support/replay-approver-token.js";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
type Manifest = { schemaVersion: number; environment: string; identityType: string; approverObjectId: string; directoryId: string; apiClientId: string; tenantCode: string };

async function waitForApproverCustomerResponse(page: Page, apiOrigin: string): Promise<{ status: number; token: string }> {
  const response = await page.waitForResponse(async candidate => {
    const request = candidate.request();
    return request.method() === "GET" && isCustomerListUrl(candidate.url(), apiOrigin)
      && await request.headerValue("x-tenant-code") === "TenantA"
      && /^Bearer\s+\S+$/i.test(await request.headerValue("authorization") ?? "");
  }, { timeout: 300000 });
  const authorization = await response.request().headerValue("authorization");
  assert.ok(authorization, "Authenticated API request is required.");
  return { status: response.status(), token: authorization!.replace(/^Bearer\s+/i, "") };
}

test("Azure dev replay approver token is pinned and has phase10-operator (no mutation)", { timeout: 420000 }, async t => {
  const reportRoot = path.join(repoRoot, "TestResults", "Phase10", "azure-replay-approver-preflight", `${new Date().toISOString().replace(/[:.]/g, "-")}-${process.pid}`);
  const checks = { authenticatedApiRequestHttp200: false, pinnedApproverAndRoleClaims: false, applicationSignOut: false };
  let reportStatus = "FAIL";
  t.after(async () => {
    await mkdir(reportRoot, { recursive: true });
    await writeFile(path.join(reportRoot, "summary.json"), JSON.stringify({
      schemaVersion: 1, status: reportStatus, environment: "dev", tenantCode: "TenantA",
      checks, checkedUtc: new Date().toISOString(), mutationPerformed: false
    }, null, 2), "utf8");
    console.log(`Sanitized approver token evidence: ${path.relative(repoRoot, path.join(reportRoot, "summary.json"))}`);
  });
  const manifestPath = process.env.PHASE10_REPLAY_APPROVER_MANIFEST;
  const uiOrigin = process.env.PHASE10_AZURE_UI_ORIGIN;
  const gatewayOrigin = process.env.PHASE10_AZURE_API_ORIGIN;
  assert.ok(manifestPath && uiOrigin && gatewayOrigin, "Use the supervised replay-approver preflight runhook.");
  const resolvedManifest = path.resolve(manifestPath!);
  assert.ok(!resolvedManifest.toLowerCase().startsWith(`${repoRoot.toLowerCase()}${path.sep}`), "Approver manifest must remain outside the repository.");
  const manifest = JSON.parse(await readFile(resolvedManifest, "utf8")) as Manifest;
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.environment, "dev");
  assert.equal(manifest.identityType, "replay-approver");
  assert.equal(manifest.tenantCode, "TenantA");
  for (const value of [manifest.approverObjectId, manifest.directoryId, manifest.apiClientId]) assert.match(value, /^[a-f0-9-]{36}$/i);

  const configApi = await playwrightRequest.newContext();
  let browserApiOrigin: string;
  try {
    const config = await configApi.get(`${uiOrigin}/runtime-config.json`, { timeout: 15000, maxRedirects: 0 });
    assert.equal(config.status(), 200, "Deployed UI runtime configuration must be readable.");
    browserApiOrigin = resolveBrowserApiOrigin(uiOrigin!, gatewayOrigin!, (await config.json()).apiBaseUrl);
  } finally { await configApi.dispose(); }

  const browser = await chromium.launch({ headless: false, args: ["--start-maximized"] });
  try {
    const context = await browser.newContext({ viewport: null });
    const page = await context.newPage();
    await page.bringToFront();
    console.log(`[${new Date().toISOString()}] Complete normal Entra sign-in/MFA as the dedicated replay approver. This performs read-only checks only.`);
    const [authenticated] = await Promise.all([
      waitForApproverCustomerResponse(page, browserApiOrigin),
      page.goto(`${uiOrigin}/customers?tenantCode=TenantA`, { waitUntil: "domcontentloaded", timeout: 30000 })
    ]).catch(() => { throw new Error("Could not observe the authenticated TenantA customer-list response within the sign-in window."); });
    assert.equal(authenticated.status, 200, "Approver's own-tenant API request must be authorized.");
    checks.authenticatedApiRequestHttp200 = true;
    assertReplayApproverToken(authenticated.token, {
      objectId: manifest.approverObjectId,
      directoryId: manifest.directoryId,
      apiClientId: manifest.apiClientId,
      tenantCode: manifest.tenantCode
    } satisfies ReplayApproverTokenExpectation);
    checks.pinnedApproverAndRoleClaims = true;
    console.log("Pinned identity, API audience, delegated scope, TenantA claim, and phase10-operator role verified; no approval/replay/payment was submitted.");
    await Promise.all([
      page.waitForURL(url => isAppSignedOutUrl(url, uiOrigin!), { timeout: 30000, waitUntil: "domcontentloaded" }),
      page.getByRole("button", { name: "Sign out", exact: true }).click({ timeout: 15000 })
    ]).catch(() => { throw new Error("Sign-out did not return to the approved application signed-out page."); });
    await page.getByRole("button", { name: "Sign in", exact: true }).waitFor({ state: "visible", timeout: 15000 });
    checks.applicationSignOut = true;
  } finally { await browser.close(); }
  reportStatus = "PASS";
});
