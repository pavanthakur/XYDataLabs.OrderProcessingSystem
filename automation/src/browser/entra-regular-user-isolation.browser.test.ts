import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { chromium, request as playwrightRequest, type BrowserContext, type Page } from "playwright";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
type UserMapping = { tenantCode: string; email: string; objectId: string };
type PrivateManifest = { schemaVersion: number; environment: string; directoryId: string; apiClientId: string; users: UserMapping[] };

function decodePayload(token: string): Record<string, unknown> {
  const parts = token.split(".");
  assert.equal(parts.length, 3, "Expected a JWT access token from an authenticated API request.");
  return JSON.parse(Buffer.from(parts[1]!, "base64url").toString("utf8")) as Record<string, unknown>;
}

function responseEnvelope<T>(value: unknown): T {
  if (value && typeof value === "object" && "data" in value) return (value as { data: T }).data;
  return value as T;
}

async function discoverTenants(apiOrigin: string): Promise<string[]> {
  const api = await playwrightRequest.newContext({ baseURL: apiOrigin });
  const response = await api.get("/api/v1/Info/runtime-configuration");
  assert.equal(response.status(), 200, "Azure runtime topology discovery must succeed before user sign-in.");
  const body = responseEnvelope<{ availableTenants?: Array<{ tenantCode?: string }> }>(await response.json());
  await api.dispose();
  const codes = (body.availableTenants ?? []).map(item => item.tenantCode?.trim()).filter((code): code is string => Boolean(code));
  assert.ok(codes.length > 0, "Azure runtime returned no active tenant codes.");
  assert.equal(new Set(codes.map(code => code.toLowerCase())).size, codes.length, "Runtime tenant codes must be unique.");
  return codes.sort((left, right) => left.localeCompare(right));
}

async function waitForOwnCustomerResponse(page: Page, apiOrigin: string, tenantCode: string): Promise<string> {
  const response = await page.waitForResponse(candidate => {
    const url = new URL(candidate.url());
    return url.origin === apiOrigin && url.pathname.toLowerCase() === "/api/v1/customer/getallcustomers"
      && candidate.request().headers()["x-tenant-code"] === tenantCode && candidate.status() === 200;
  }, { timeout: 300000 });
  const authorization = response.request().headers().authorization;
  assert.match(authorization ?? "", /^Bearer\s+[^\s]+$/i, "An authenticated own-tenant API request is required.");
  return authorization!.replace(/^Bearer\s+/i, "");
}

async function signedOut(page: Page, uiOrigin: string): Promise<void> {
  await page.getByRole("button", { name: "Sign out", exact: true }).click();
  await page.waitForURL(`${uiOrigin}/signed-out`, { timeout: 30000 });
  await page.getByRole("button", { name: "Sign in", exact: true }).waitFor({ state: "visible", timeout: 15000 });
}

test("Azure dev regular Entra users are isolated to exactly one assigned tenant (no payments)", { timeout: 1200000 }, async t => {
  const manifestPath = process.env.PHASE10_ENTRA_TEST_USERS_MANIFEST;
  const uiOrigin = process.env.PHASE10_AZURE_UI_ORIGIN;
  const apiOrigin = process.env.PHASE10_AZURE_API_ORIGIN;
  const deploymentIdentitySha256 = process.env.PHASE10_AZURE_DEPLOYMENT_IDENTITY_SHA256;
  const sourceRevision = process.env.PHASE10_RUNNER_SOURCE_REVISION;
  const sourceDirty = process.env.PHASE10_RUNNER_SOURCE_DIRTY === "true";
  const runnerSourceSha256 = process.env.PHASE10_RUNNER_SOURCE_SHA256;
  assert.ok(manifestPath, "Set PHASE10_ENTRA_TEST_USERS_MANIFEST to the private local manifest.");
  assert.ok(uiOrigin && apiOrigin, "The operator wrapper must resolve live Azure-dev UI/API origins.");
  assert.match(deploymentIdentitySha256 ?? "", /^[0-9a-f]{64}$/i, "Live Azure deployment identity is required.");
  assert.match(sourceRevision ?? "", /^[0-9a-f]{40}$/i, "Runner source revision is required.");
  assert.match(runnerSourceSha256 ?? "", /^[0-9a-f]{64}$/i, "Runner source-content hash is required.");
  const manifest = JSON.parse(await readFile(manifestPath, "utf8")) as PrivateManifest;
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.environment, "dev");
  assert.ok(!path.resolve(manifestPath).toLowerCase().startsWith(`${repoRoot.toLowerCase()}${path.sep}`), "PII manifest must be outside the repository.");
  const activeTenantCodes = await discoverTenants(apiOrigin);
  const mappings = [...manifest.users].sort((left, right) => left.tenantCode.localeCompare(right.tenantCode));
  assert.deepEqual(mappings.map(item => item.tenantCode), activeTenantCodes, "A distinct regular test user is required for every active Azure-dev tenant.");
  for (const item of mappings) {
    assert.match(item.email, /^[^\s@]+@[^\s@]+\.[^\s@]+$/);
    assert.match(item.objectId, /^[0-9a-f-]{36}$/i, `Run provisioning Verify first for ${item.tenantCode}.`);
  }

  const reportDir = path.join(repoRoot, "TestResults", "Phase10", "azure-regular-user-isolation", `${new Date().toISOString().replace(/[:.]/g, "-")}-${process.pid}`);
  await mkdir(reportDir, { recursive: true });
  const results: Record<string, unknown>[] = [];
  const matrix: Record<string, unknown>[] = [];
  const browser = await chromium.launch({ headless: false });
  t.after(async () => {
    await writeFile(path.join(reportDir, "regular-user-isolation.json"), JSON.stringify({
      schema: "phase10-azure-regular-user-isolation-evidence-v1",
      status: results.length === mappings.length && results.every(row => row.status === "passed") ? "passed" : "failed",
      environment: "dev", activeTenantCodes, startedUtc: startedUtc,
      completedUtc: new Date().toISOString(), regularUserIsolation: matrix,
      deploymentIdentitySha256, sourceRevision, sourceDirty, runnerSourceSha256,
      forgedTenantHeaderDenied: results.length === mappings.length && results.every(row => row.forgedHeaderDenied === true) ? "passed" : "failed",
      unauthorizedDeepLinkDenied: results.length === mappings.length && results.every(row => row.deepLinkDenied === true) ? "passed" : "failed",
      signOut: results.length === mappings.length && results.every(row => row.signOut === true) ? "passed" : "failed",
      identities: results.map(row => ({ tenantCode: row.tenantCode, identitySha256: row.identitySha256, status: row.status })),
      paymentsAttempted: false
    }, null, 2));
    await browser.close();
    console.log(`Sanitized regular-user isolation evidence: ${reportDir}`);
  });
  const startedUtc = new Date().toISOString();

  // Invalid credentials are checked without producing or retaining user tokens.
  const unauthenticatedApi = await playwrightRequest.newContext({ baseURL: apiOrigin });
  try {
    for (const tenantCode of activeTenantCodes) {
      const anonymous = await unauthenticatedApi.get("/api/v1/Customer/GetAllCustomers", { headers: { "X-Tenant-Code": tenantCode } });
      assert.equal(anonymous.status(), 401, `Anonymous access must be denied for ${tenantCode}.`);
      const malformed = await unauthenticatedApi.get("/api/v1/Customer/GetAllCustomers", { headers: { "X-Tenant-Code": tenantCode, Authorization: "Bearer invalid.phase10.token" } });
      assert.equal(malformed.status(), 401, `Malformed bearer token must be denied for ${tenantCode}.`);
    }
  } finally { await unauthenticatedApi.dispose(); }

  for (const mapping of mappings) {
    const context: BrowserContext = await browser.newContext();
    const page = await context.newPage();
    try {
      await page.goto(`${uiOrigin}/customers?tenantCode=${encodeURIComponent(mapping.tenantCode)}`, { waitUntil: "domcontentloaded" });
      console.log(`Complete normal Entra sign-in/MFA for the ${mapping.tenantCode} regular test user. No payment will be submitted.`);
      const token = await waitForOwnCustomerResponse(page, apiOrigin, mapping.tenantCode);
      const claims = decodePayload(token);
      assert.equal(String(claims.oid ?? "").toLowerCase(), mapping.objectId.toLowerCase(), `Signed-in directory object must match the provisioned ${mapping.tenantCode} user.`);
      assert.equal(String(claims.tid ?? "").toLowerCase(), manifest.directoryId.toLowerCase(), "Token must come from the expected resource directory.");
      const audience = String(claims.aud ?? "").toLowerCase();
      assert.ok([manifest.apiClientId.toLowerCase(), `api://${manifest.apiClientId}`.toLowerCase()].includes(audience), "Token audience must be the Order Processing API.");
      assert.ok(String(claims.scp ?? "").split(/\s+/).includes("access_as_user"), "Delegated API scope must be present.");
      assert.equal(String(claims["extn.applicationTenantCode"] ?? ""), mapping.tenantCode, "API access token tenant claim must match the provisioned assignment.");
      const roles = Array.isArray(claims.roles) ? claims.roles.map(String) : [];
      assert.equal(roles.some(role => ["platform-admin", "phase10-operator"].includes(role)), false, "Regular test account must not carry a privileged app role.");

      const authHeaders = { Authorization: `Bearer ${token}` };
      const runtimeResponse = await context.request.get(`${apiOrigin}/api/v1/Info/runtime-configuration`, { headers: { ...authHeaders, "X-Tenant-Code": mapping.tenantCode } });
      assert.equal(runtimeResponse.status(), 200);
      const runtime = responseEnvelope<{ availableTenants?: Array<{ tenantCode?: string }> }>(await runtimeResponse.json());
      assert.deepEqual((runtime.availableTenants ?? []).map(item => item.tenantCode).sort(), [mapping.tenantCode], "Regular user discovery must expose only the assigned tenant.");
      const selector = page.locator(".tenant-picker select");
      await selector.waitFor({ state: "visible", timeout: 15000 });
      assert.equal(await selector.locator("option").count(), 1, "Regular-user selector must contain one tenant.");
      assert.equal(await selector.isDisabled(), true, "Regular-user selector must not permit tenant switching.");

      for (const requestedTenantCode of activeTenantCodes) {
        const tenantResponse = await context.request.get(`${apiOrigin}/api/v1/Customer/GetAllCustomers`, {
          headers: { ...authHeaders, "X-Tenant-Code": requestedTenantCode }
        });
        const allowed = requestedTenantCode === mapping.tenantCode;
        assert.equal(tenantResponse.status(), allowed ? 200 : 403, `${mapping.tenantCode} must ${allowed ? "access" : "be denied"} ${requestedTenantCode}.`);
        matrix.push({ assignedTenantCode: mapping.tenantCode, requestedTenantCode, result: allowed ? "allowed" : "denied", status: "passed", httpStatus: tenantResponse.status() });
      }

      const identityHash = createHash("sha256").update(mapping.objectId.toLowerCase()).digest("hex");
      const alternate = activeTenantCodes.find(code => code !== mapping.tenantCode);
      if (alternate) {
        const deepLinkDenied = page.waitForResponse(candidate => {
          const url = new URL(candidate.url());
          return url.origin === apiOrigin && url.pathname.toLowerCase() === "/api/v1/customer/getallcustomers"
            && candidate.request().headers()["x-tenant-code"] === alternate && candidate.status() === 403;
        }, { timeout: 15000 });
        await page.goto(`${uiOrigin}/customers?tenantCode=${encodeURIComponent(alternate)}`, { waitUntil: "domcontentloaded" });
        await deepLinkDenied;
        assert.equal(await selector.inputValue(), mapping.tenantCode, "A forged tenant deep link must not change the selected tenant.");
      }
      const otherTab = await context.newPage();
      await otherTab.goto(`${uiOrigin}/customers?tenantCode=${encodeURIComponent(mapping.tenantCode)}`, { waitUntil: "domcontentloaded" });
      await otherTab.locator(".customer-link").first().waitFor({ state: "visible", timeout: 20000 });
      await signedOut(page, uiOrigin);
      await otherTab.getByRole("button", { name: "Sign in", exact: true }).waitFor({ state: "visible", timeout: 15000 });
      assert.equal(await otherTab.locator(".customer-link").count(), 0, "Sign-out must clear the other application's tab.");
      const signedOutRequest = await context.request.get(`${apiOrigin}/api/v1/Customer/GetAllCustomers`, { headers: { "X-Tenant-Code": mapping.tenantCode } });
      assert.equal(signedOutRequest.status(), 401, "A post-sign-out request without credentials must be denied.");
      await otherTab.close();
      results.push({ tenantCode: mapping.tenantCode, identitySha256: identityHash, status: "passed", forgedHeaderDenied: true, deepLinkDenied: true, signOut: true });
    } catch (error) {
      results.push({ tenantCode: mapping.tenantCode, identitySha256: createHash("sha256").update(mapping.objectId.toLowerCase()).digest("hex"), status: "failed", error: error instanceof Error ? error.message.slice(0, 300) : "Unexpected failure." });
      throw error;
    } finally {
      await context.close();
    }
  }
  assert.equal(matrix.length, activeTenantCodes.length * activeTenantCodes.length, "Every assigned/requested tenant pair must be tested exactly once.");
});
