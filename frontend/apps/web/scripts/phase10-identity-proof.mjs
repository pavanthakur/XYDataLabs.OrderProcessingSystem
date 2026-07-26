import { chromium, request as playwrightRequest } from "playwright";
import fs from "node:fs/promises";
import path from "node:path";

const argumentsMap = parseArguments(process.argv.slice(2));
const appBaseUrl = argumentsMap.get("url") ?? "http://localhost:5022";
const apiBaseUrl = argumentsMap.get("api-url") ?? "http://localhost:5080";
const outputPath = argumentsMap.get("output");
const password = process.env.KEYCLOAK_TENANT_ADMIN_PASSWORD
  ?? process.env.LOCAL_KEYCLOAK_TEST_PASSWORD;

if (!password) {
  throw new Error(
    "KEYCLOAK_TENANT_ADMIN_PASSWORD or LOCAL_KEYCLOAK_TEST_PASSWORD is required.");
}

const evidence = {
  startedAtIst: formatIst(new Date()),
  completedAtIst: null,
  status: "running",
  checks: []
};

const browser = await chromium.launch({ headless: true });
try {
  const anonymousApi = await playwrightRequest.newContext({ baseURL: apiBaseUrl });
  try {
    const anonymousResponse = await anonymousApi.get(
      "/api/v1/Info/runtime-configuration",
      { headers: { "X-Tenant-Code": "TenantA" } });
    record("anonymous-protected-request", anonymousResponse.status() === 401, {
      expected: 401,
      actual: anonymousResponse.status()
    });

    const webhookResponse = await anonymousApi.post(
      "/api/v1/webhook/Razorpay",
      {
        headers: {
          "Content-Type": "application/json",
          "X-Razorpay-Signature": "invalid-local-proof-signature"
        },
        data: { event: "payment.authorized" }
      });
    const webhookBody = await webhookResponse.text();
    record(
      "anonymous-webhook-remains-signature-protected",
      webhookResponse.status() === 401
        && webhookBody.toLowerCase().includes("signature"),
      { expected: "401 signature rejection", actual: webhookResponse.status() });
  }
  finally {
    await anonymousApi.dispose();
  }

  const normalUser = await login("tenant-user", "TenantA");
  try {
    await assertTenantRequest(normalUser.token, "TenantA", 200, "matching-tenant");
    await assertTenantRequest(normalUser.token, "TenantB", 403, "mismatched-tenant");

    const approvalResponse = await normalUser.context.request.post(
      `${apiBaseUrl}/api/v1/admin/dlq/${crypto.randomUUID()}/approve`,
      { headers: authorizationHeaders(normalUser.token, "TenantA") });
    record("normal-user-cannot-approve-replay", approvalResponse.status() === 403, {
      expected: 403,
      actual: approvalResponse.status()
    });
  }
  finally {
    await normalUser.context.close();
  }

  const operator = await login("tenant-admin", "TenantA");
  try {
    const approvalResponse = await operator.context.request.post(
      `${apiBaseUrl}/api/v1/admin/dlq/${crypto.randomUUID()}/approve`,
      { headers: authorizationHeaders(operator.token, "TenantA") });
    record("operator-reaches-replay-approval", approvalResponse.status() === 404, {
      expected: 404,
      actual: approvalResponse.status(),
      meaning: "Authorization passed and the random quarantine record was not found."
    });
  }
  finally {
    await operator.context.close();
  }

  evidence.status = evidence.checks.every((check) => check.passed)
    ? "passed"
    : "failed";
}
catch (error) {
  evidence.status = "failed";
  evidence.error = error instanceof Error ? error.message : String(error);
  throw error;
}
finally {
  evidence.completedAtIst = formatIst(new Date());
  await browser.close();
  if (outputPath) {
    await fs.mkdir(path.dirname(outputPath), { recursive: true });
    await fs.writeFile(outputPath, JSON.stringify(evidence, null, 2), "utf8");
  }
}

if (evidence.status !== "passed") {
  throw new Error("Phase 10 local identity proof failed.");
}

async function login(username, tenantCode) {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto(
    `${appBaseUrl}/customers?tenantCode=${encodeURIComponent(tenantCode)}`,
    { waitUntil: "domcontentloaded" });
  await page.locator("#username").fill(username);
  await page.locator("#password").fill(password);
  await page.locator("#kc-login").click();
  await page.waitForURL(
    (url) => url.toString().startsWith(appBaseUrl),
    { timeout: 60_000 });
  await page.getByRole("heading", { name: /Customers, orders, and card payments/i })
    .waitFor({ timeout: 60_000 });
  const currentUrl = page.url();
  const errorBanner = await page.locator(".error-banner").textContent().catch(() => null);
  const token = await page.evaluate(() =>
    window.localStorage.getItem("orderprocessing.accessToken"));
  if (!token) {
    await context.close();
    throw new Error(`PKCE login for ${username} returned no access token. URL=${currentUrl}. Error=${errorBanner ?? "none"}.`);
  }

  record(`pkce-login-${username}`, true, { tenantCode });
  return { context, token };
}

async function assertTenantRequest(token, tenantCode, expectedStatus, name) {
  const api = await playwrightRequest.newContext({
    baseURL: apiBaseUrl,
    extraHTTPHeaders: authorizationHeaders(token, tenantCode)
  });
  try {
    const response = await api.get("/api/v1/Info/runtime-configuration");
    record(name, response.status() === expectedStatus, {
      expected: expectedStatus,
      actual: response.status()
    });
  }
  finally {
    await api.dispose();
  }
}

function authorizationHeaders(token, tenantCode) {
  return {
    Authorization: `Bearer ${token}`,
    "X-Tenant-Code": tenantCode
  };
}

function record(name, passed, details) {
  evidence.checks.push({ name, passed, details });
}

function parseArguments(values) {
  const result = new Map();
  for (let index = 0; index < values.length; index += 1) {
    const current = values[index];
    if (!current.startsWith("--")) {
      continue;
    }

    result.set(current.slice(2), values[index + 1]);
    index += 1;
  }
  return result;
}

function formatIst(value) {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone: "Asia/Kolkata",
    dateStyle: "short",
    timeStyle: "long"
  }).format(value);
}
