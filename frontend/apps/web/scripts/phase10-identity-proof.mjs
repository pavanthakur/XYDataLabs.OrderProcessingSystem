import { chromium, request as playwrightRequest } from "playwright";
import fs from "node:fs/promises";
import path from "node:path";

const argumentsMap = parseArguments(process.argv.slice(2));
const appBaseUrl = argumentsMap.get("url") ?? "http://localhost:5022";
const legacyApiBaseUrl = argumentsMap.get("api-url");
const gatewayApiBaseUrl = argumentsMap.get("gateway-api-url") ?? legacyApiBaseUrl ?? "http://localhost:5080";
const ordersApiBaseUrl = argumentsMap.get("orders-api-url") ?? legacyApiBaseUrl ?? "http://localhost:5081";
const paymentsApiBaseUrl = argumentsMap.get("payments-api-url") ?? legacyApiBaseUrl ?? "http://localhost:5084";
const approvalApiBaseUrl = argumentsMap.get("approval-api-url") ?? ordersApiBaseUrl;
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
  const anonymousOrdersApi = await playwrightRequest.newContext({ baseURL: ordersApiBaseUrl });
  try {
    const runtimeConfigurationResponse = await anonymousOrdersApi.get("/api/v1/Info/runtime-configuration");
    record("anonymous-runtime-configuration-remains-public", runtimeConfigurationResponse.status() === 200, {
      expected: 200,
      actual: runtimeConfigurationResponse.status()
    });

    const protectedCustomerResponse = await anonymousOrdersApi.get("/api/v1/Customer/GetAllCustomers");
    record("anonymous-protected-request", protectedCustomerResponse.status() === 401, {
      expected: 401,
      actual: protectedCustomerResponse.status()
    });

    const invalidBearerResponse = await anonymousOrdersApi.get(
      "/api/v1/Customer/GetAllCustomers",
      {
        headers: {
          Authorization: "Bearer invalid-local-proof-token"
        }
      });
    record("invalid-bearer-request-is-forbidden", invalidBearerResponse.status() === 403, {
      expected: 403,
      actual: invalidBearerResponse.status()
    });
  }
  finally {
    await anonymousOrdersApi.dispose();
  }

  const anonymousPaymentsApi = await playwrightRequest.newContext({ baseURL: paymentsApiBaseUrl });
  try {
    const webhookResponse = await anonymousPaymentsApi.post(
      "/api/v1/webhook/Razorpay",
      {
        headers: {
          "Content-Type": "application/json",
          "X-Razorpay-Signature": "invalid-local-proof-signature"
        },
        data: { event: "payment.authorized" }
      });
    record(
      "anonymous-webhook-rejects-invalid-request",
      webhookResponse.status() === 400 || webhookResponse.status() === 401,
      {
        expected: "400 or 401",
        actual: webhookResponse.status(),
        note: "The local host contract may reject malformed webhook input before or after auth handling."
      });
  }
  finally {
    await anonymousPaymentsApi.dispose();
  }

  const normalUser = await login("tenant-user", "TenantA");
  try {
    const normalUserClaims = decodeJwtPayload(normalUser.token);
    record("tenant-user-lacks-operator-role", !(normalUserClaims.realm_access?.roles ?? []).includes("phase10-operator"), {
      tenantCode: normalUserClaims.tenant_code ?? null,
      roles: normalUserClaims.realm_access?.roles ?? []
    });

    await assertProtectedTenantRequest(
      normalUser.token,
      "TenantA",
      200,
      "matching-tenant-protected-request");
    await assertProtectedProductRequest(
      normalUser.token,
      "TenantA",
      200,
      "matching-tenant-gateway-product-request");
    await assertProtectedTenantRequest(
      normalUser.token,
      "TenantB",
      403,
      "mismatched-tenant-protected-request");

    const normalUserApprovalResponse = await normalUser.context.request.post(
      `${approvalApiBaseUrl}/api/v1/admin/dlq/${crypto.randomUUID()}/approve`,
      { headers: authorizationHeaders(normalUser.token, "TenantA") });
    record("tenant-user-cannot-approve-replay", normalUserApprovalResponse.status() === 403, {
      expected: 403,
      actual: normalUserApprovalResponse.status()
    });
  }
  finally {
    await normalUser.context.close();
  }

  const operator = await login("tenant-admin", "TenantA");
  try {
    const operatorClaims = decodeJwtPayload(operator.token);
    record("tenant-admin-has-operator-role", (operatorClaims.realm_access?.roles ?? []).includes("phase10-operator"), {
      tenantCode: operatorClaims.tenant_code ?? null,
      roles: operatorClaims.realm_access?.roles ?? []
    });

    const approvalResponse = await operator.context.request.post(
      `${approvalApiBaseUrl}/api/v1/admin/dlq/${crypto.randomUUID()}/approve`,
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

async function assertProtectedTenantRequest(token, tenantCode, expectedStatus, name) {
  const api = await playwrightRequest.newContext({
    baseURL: ordersApiBaseUrl,
    extraHTTPHeaders: authorizationHeaders(token, tenantCode)
  });
  try {
    const response = await api.get("/api/v1/Customer/GetAllCustomers");
    record(name, response.status() === expectedStatus, {
      expected: expectedStatus,
      actual: response.status()
    });
  }
  finally {
    await api.dispose();
  }
}

async function assertProtectedProductRequest(token, tenantCode, expectedStatus, name) {
  const api = await playwrightRequest.newContext({
    baseURL: gatewayApiBaseUrl,
    extraHTTPHeaders: authorizationHeaders(token, tenantCode)
  });
  try {
    const response = await api.get("/api/v1/Product/GetAllProducts");
    record(name, response.status() === expectedStatus, {
      expected: expectedStatus,
      actual: response.status()
    });
  }
  finally {
    await api.dispose();
  }
}

function decodeJwtPayload(token) {
  const parts = token.split(".");
  if (parts.length < 2) {
    throw new Error("Access token is not a JWT.");
  }

  const payloadJson = Buffer.from(parts[1], "base64url").toString("utf8");
  return JSON.parse(payloadJson);
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
