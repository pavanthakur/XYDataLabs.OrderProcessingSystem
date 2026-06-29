import process from "node:process";
import fs from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";

const customerRequestPathFragment = "/api/v1/Customer/GetAllCustomers";
const defaultAttemptCount = 3;
const defaultTimeoutMs = 60000;
const localStorageKey = "orderprocessing.activeTenantCode";
const runtimeConfigurationPathFragment = "/api/v1/Info/runtime-configuration";
const tenantLabel = "Tenant";
const defaultArtifactDirectoryName = "playwright-smoke";
const defaultLatestPointerFileName = "latest-playwright-smoke.txt";

function formatIstTimestamp(date) {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone: "Asia/Kolkata",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    fractionalSecondDigits: 3,
    hour12: false
  }).format(date).replace(" ", "T") + "+05:30";
}

function formatIstStamp(date) {
  return formatIstTimestamp(date).replace(/[:+,]/g, "-").replace(/\./g, "-");
}

async function main() {
  const options = parseArgs(process.argv.slice(2));

  if (options.help) {
    printHelp();
    return;
  }

  if (!options.url) {
    throw new Error("Missing required --url argument.");
  }

  const browser = await chromium.launch({ headless: true });
  const artifactBaseRoot = path.resolve(process.cwd(), options.artifactRoot ?? path.join("test-results", defaultArtifactDirectoryName));
  const runStamp = `${formatIstStamp(new Date())}_smoke`;
  const artifactRoot = path.join(artifactBaseRoot, runStamp);
  const artifactRootDirectory = path.dirname(artifactBaseRoot);
  const latestPointerPath = path.resolve(process.cwd(), options.latestPointerPath ?? path.join("test-results", defaultLatestPointerFileName));
  const summaryPath = path.join(artifactRoot, "summary.json");
  const currentStepPath = path.join(artifactRoot, "current-step.txt");
  const rootIndexPath = path.join(artifactRootDirectory, "latest-playwright-run.txt");
  const summary = {
    target: options.target ?? "custom",
    startedUtc: new Date().toISOString(),
    startedIst: formatIstTimestamp(new Date()),
    finishedUtc: null,
    finishedIst: null,
    status: "running",
    currentStep: "initialized",
    artifactRoot,
    latestPointerPath,
    discoveredTenantCode: null,
    staleTenantCode: null,
    expectedTenantCode: null,
    activeTenantCode: null,
    customerRequestTenantCode: null
  };
  await fs.mkdir(artifactRoot, { recursive: true });
  await fs.mkdir(artifactRootDirectory, { recursive: true });
  await fs.mkdir(path.dirname(latestPointerPath), { recursive: true });
  await fs.writeFile(rootIndexPath, `${artifactRoot}\n`, "utf8");
  await fs.writeFile(latestPointerPath, `${artifactRoot}\n`, "utf8");
  await fs.writeFile(currentStepPath, "initialized\n", "utf8");
  await fs.writeFile(summaryPath, JSON.stringify(summary, null, 2), "utf8");

  try {
    const discovery = await discoverRuntimeConfiguration(browser, options.url, options.timeoutMs);
    summary.currentStep = "runtime-config-discovered";
    await fs.writeFile(currentStepPath, `${summary.currentStep}\n`, "utf8");
    await fs.writeFile(summaryPath, JSON.stringify(summary, null, 2), "utf8").catch(() => {});
    const expectedTenantCode = options.expectedTenantCode ?? discovery.runtimeConfiguration.activeTenantCode;
    const staleTenantCode = resolveStaleTenantCode(
      discovery.runtimeConfiguration.availableTenants,
      expectedTenantCode,
      options.staleTenantCode
    );

    console.log(`Discovered expected tenant: ${expectedTenantCode}`);
    console.log(`Injecting stale tenant candidate into localStorage: ${staleTenantCode}`);

    const smokeResult = await verifyTenantBootstrap(browser, {
      artifactRoot,
      expectedTenantCode,
      staleTenantCode,
      timeoutMs: options.timeoutMs,
      url: options.url,
      latestPointerPath,
      artifactRoot
    });

    summary.discoveredTenantCode = discovery.runtimeConfiguration.activeTenantCode;
    summary.currentStep = "tenant-bootstrap-verified";
    await fs.writeFile(currentStepPath, `${summary.currentStep}\n`, "utf8").catch(() => {});
    await fs.writeFile(summaryPath, JSON.stringify(summary, null, 2), "utf8").catch(() => {});
    summary.staleTenantCode = staleTenantCode;
    summary.expectedTenantCode = expectedTenantCode;
    summary.activeTenantCode = smokeResult.activeTenantCode;
    summary.customerRequestTenantCode = smokeResult.customerRequestTenantCode;
    console.log(`Tenant selector resolved: ${smokeResult.activeTenantCode}`);
    console.log(`Customer request header '${smokeResult.tenantHeaderName}' used tenant: ${smokeResult.customerRequestTenantCode}`);
    console.log("Tenant bootstrap smoke test passed.");
    summary.status = "passed";
  } finally {
    summary.finishedUtc = new Date().toISOString();
    summary.finishedIst = formatIstTimestamp(new Date());
    summary.currentStep = summary.status === "passed" ? "completed" : summary.currentStep;
    await fs.writeFile(summaryPath, JSON.stringify(summary, null, 2), "utf8").catch(() => {});
    await fs.writeFile(currentStepPath, `${summary.currentStep}\n`, "utf8").catch(() => {});
    await browser.close();
  }
}

function parseArgs(argv) {
  const options = {
    expectedTenantCode: null,
    help: false,
    target: null,
    artifactRoot: null,
    latestPointerPath: null,
    staleTenantCode: null,
    timeoutMs: defaultTimeoutMs,
    url: null
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];

    if (argument === "--help" || argument === "-h") {
      options.help = true;
      continue;
    }

    if (argument === "--url") {
      options.url = argv[++index] ?? null;
      continue;
    }

    if (argument === "--target") {
      options.target = argv[++index] ?? null;
      continue;
    }

    if (argument === "--artifact-root") {
      options.artifactRoot = argv[++index] ?? null;
      continue;
    }

    if (argument === "--latest-pointer-path") {
      options.latestPointerPath = argv[++index] ?? null;
      continue;
    }

    if (argument === "--expected-tenant") {
      options.expectedTenantCode = argv[++index] ?? null;
      continue;
    }

    if (argument === "--stale-tenant") {
      options.staleTenantCode = argv[++index] ?? null;
      continue;
    }

    if (argument === "--timeout-ms") {
      const parsedTimeout = Number.parseInt(argv[++index] ?? "", 10);
      if (!Number.isFinite(parsedTimeout) || parsedTimeout <= 0) {
        throw new Error("--timeout-ms must be a positive integer.");
      }

      options.timeoutMs = parsedTimeout;
      continue;
    }

    throw new Error(`Unknown argument: ${argument}`);
  }

  return options;
}

function printHelp() {
  console.log(`Tenant bootstrap smoke test

Required:
  --url <route-url>                Full UI route URL, for example https://localhost:5022/customers
  --target <target-key>            Logical target name used in the run summary
  --artifact-root <path>           Directory for trace/screenshot/html artifacts
  --latest-pointer-path <path>     File that records the latest artifact root

Optional:
  --expected-tenant <tenantCode>   Expected resolved tenant code; defaults to runtime bootstrap response
  --stale-tenant <tenantCode>      Stale tenant code to seed into localStorage before page load
  --timeout-ms <milliseconds>      Timeout for page and network waits; default ${defaultTimeoutMs}
  --help                           Show this help text
`);
}

async function discoverRuntimeConfiguration(browser, url, timeoutMs) {
  return withRetry("Runtime configuration discovery", async attempt => {
    const context = await browser.newContext({ ignoreHTTPSErrors: true });
    await context.tracing.start({ screenshots: true, snapshots: true, sources: true });

    try {
      const page = await context.newPage();
      const diagnostics = attachPageDiagnostics(page);

      await page.goto(url, { timeout: timeoutMs, waitUntil: "domcontentloaded" });

      const runtimeConfigurationResponse = await waitForRuntimeConfigurationResponse(page, timeoutMs, diagnostics, attempt);
      const runtimeConfiguration = await runtimeConfigurationResponse.json();

      validateRuntimeConfiguration(runtimeConfiguration);

      return {
        runtimeConfiguration
      };
    } finally {
      await context.tracing.stop({ path: path.join(process.cwd(), "test-results", defaultArtifactDirectoryName, `runtime-config-attempt-${attempt}.zip`) }).catch(() => {});
      await context.close();
    }
  });
}

function resolveStaleTenantCode(availableTenants, expectedTenantCode, requestedStaleTenantCode) {
  const normalizedExpectedTenantCode = expectedTenantCode.trim().toLowerCase();

  if (requestedStaleTenantCode) {
    const explicitMatch = availableTenants.find(tenant =>
      tenant.tenantCode.trim().toLowerCase() === requestedStaleTenantCode.trim().toLowerCase());

    if (!explicitMatch) {
      throw new Error(`Requested stale tenant '${requestedStaleTenantCode}' is not an active tenant in runtime bootstrap.`);
    }

    if (explicitMatch.tenantCode.trim().toLowerCase() === normalizedExpectedTenantCode) {
      throw new Error("Requested stale tenant matches the expected tenant, so the smoke test cannot detect a regression.");
    }

    return explicitMatch.tenantCode;
  }

  const alternateTenant = availableTenants.find(tenant => tenant.tenantCode.trim().toLowerCase() !== normalizedExpectedTenantCode);
  if (!alternateTenant) {
    throw new Error("Runtime bootstrap exposed only one active tenant, so a stale-tenant regression cannot be exercised.");
  }

  return alternateTenant.tenantCode;
}

async function verifyTenantBootstrap(browser, options) {
  return withRetry("Tenant bootstrap verification", async attempt => {
    const context = await browser.newContext({ ignoreHTTPSErrors: true });
    await context.tracing.start({ screenshots: true, snapshots: true, sources: true });

    try {
      const page = await context.newPage();
      const diagnostics = attachPageDiagnostics(page);
      const customerRequestPromise = page.waitForRequest(
        request => request.url().includes(customerRequestPathFragment),
        { timeout: options.timeoutMs }
      );

      await page.addInitScript(({ nextTenantCode, storageKey }) => {
        window.localStorage.setItem(storageKey, nextTenantCode);
      }, {
        nextTenantCode: options.staleTenantCode,
        storageKey: localStorageKey
      });

      await page.goto(options.url, { timeout: options.timeoutMs, waitUntil: "domcontentloaded" });

      const runtimeConfigurationResponse = await waitForRuntimeConfigurationResponse(page, options.timeoutMs, diagnostics, attempt);
      const runtimeConfiguration = await runtimeConfigurationResponse.json();

      validateRuntimeConfiguration(runtimeConfiguration);

      const select = page.getByLabel(tenantLabel);
      await select.waitFor({ state: "visible", timeout: options.timeoutMs });
      await waitForTenantValue(page, select, options.expectedTenantCode, options.timeoutMs);

      const activeTenantCode = await select.inputValue();
      if (!equalsIgnoreCase(activeTenantCode, options.expectedTenantCode)) {
        throw new Error(`Tenant selector value '${activeTenantCode}' does not match expected tenant '${options.expectedTenantCode}'.`);
      }

      const persistedTenantCode = await page.evaluate(storageKey => window.localStorage.getItem(storageKey), localStorageKey);
      if (!equalsIgnoreCase(persistedTenantCode, options.expectedTenantCode)) {
        throw new Error(`Persisted tenant '${persistedTenantCode}' does not match expected tenant '${options.expectedTenantCode}'.`);
      }

      const customerRequest = await customerRequestPromise;
      const customerRequestHeaders = normalizeHeaders(customerRequest.headers());
      const tenantHeaderName = runtimeConfiguration.tenantHeaderName;
      const customerRequestTenantCode = customerRequestHeaders[tenantHeaderName.toLowerCase()] ?? null;

      if (!equalsIgnoreCase(customerRequestTenantCode, options.expectedTenantCode)) {
        throw new Error(
          `Customer request header '${tenantHeaderName}' used '${customerRequestTenantCode}', expected '${options.expectedTenantCode}'.`
        );
      }

      return {
        activeTenantCode,
        customerRequestTenantCode,
        tenantHeaderName
      };
    } catch (error) {
      await captureFailureArtifacts(context, options.artifactRoot, `tenant-bootstrap-attempt-${attempt}`, error);
      throw error;
    } finally {
      await context.tracing.stop({ path: path.join(options.artifactRoot, `tenant-bootstrap-attempt-${attempt}.zip`) }).catch(() => {});
      await context.close();
    }
  });
}

async function withRetry(operationName, operation, attemptCount = defaultAttemptCount) {
  let lastError = null;

  for (let attempt = 1; attempt <= attemptCount; attempt += 1) {
    try {
      if (attempt > 1) {
        console.log(`${operationName}: retrying attempt ${attempt}/${attemptCount}...`);
      }

      return await operation(attempt);
    } catch (error) {
      lastError = error;
      const message = error instanceof Error ? error.message : String(error);

      if (attempt === attemptCount) {
        break;
      }

      console.warn(`${operationName}: attempt ${attempt}/${attemptCount} failed. ${message}`);
      await delay(Math.min(2000 * attempt, 5000));
    }
  }

  throw new Error(`${operationName} failed after ${attemptCount} attempts. ${lastError instanceof Error ? lastError.message : String(lastError)}`);
}

async function captureFailureArtifacts(context, artifactRoot, name, error) {
  const safeName = name.replace(/[^a-z0-9-_]+/gi, "-");
  const screenshotPath = path.join(artifactRoot, `${safeName}.png`);
  const htmlPath = path.join(artifactRoot, `${safeName}.html`);

  try {
    const pages = context.pages();
    const page = pages[0];
    if (!page) {
      return;
    }

    await page.screenshot({ path: screenshotPath, fullPage: true }).catch(() => {});
    await fs.writeFile(htmlPath, await page.content(), "utf8").catch(() => {});
    console.warn(`Captured failure artifacts for ${safeName}: ${screenshotPath}`);
    if (error instanceof Error) {
      console.warn(error.message);
    }
  } catch {
    // Best effort only.
  }
}

async function waitForRuntimeConfigurationResponse(page, timeoutMs, diagnostics, attempt) {
  const response = await page.waitForResponse(
    candidate => candidate.url().includes(runtimeConfigurationPathFragment),
    { timeout: timeoutMs }
  ).catch(async error => {
    throw new Error(await buildRuntimeConfigurationDiagnostics(page, diagnostics, attempt, error));
  });

  if (!response.ok()) {
    const bodySnippet = await safeReadResponseBody(response);
    throw new Error(
      `Runtime configuration request returned HTTP ${response.status()} on attempt ${attempt}. ${bodySnippet}`
    );
  }

  return response;
}

function attachPageDiagnostics(page) {
  const consoleMessages = [];
  const pageErrors = [];
  const failedRequests = [];

  page.on("console", message => {
    if (consoleMessages.length < 10) {
      consoleMessages.push(`${message.type()}: ${message.text()}`);
    }
  });

  page.on("pageerror", error => {
    if (pageErrors.length < 10) {
      pageErrors.push(error.message);
    }
  });

  page.on("requestfailed", request => {
    if (failedRequests.length < 10) {
      failedRequests.push(`${request.url()} -> ${request.failure()?.errorText ?? "unknown failure"}`);
    }
  });

  return {
    consoleMessages,
    failedRequests,
    pageErrors
  };
}

async function buildRuntimeConfigurationDiagnostics(page, diagnostics, attempt, error) {
  const shellState = await page.evaluate(() => ({
    errorBanner: document.querySelector(".error-banner")?.textContent ?? null,
    location: window.location.href,
    rootPresent: Boolean(document.getElementById("root")),
    shellMeta: document.querySelector(".shell-meta")?.textContent ?? null,
    title: document.title,
    tenantValue: document.querySelector("select")?.value ?? null
  })).catch(() => null);

  const parts = [
    `Timed out waiting for runtime configuration response on attempt ${attempt}: ${error instanceof Error ? error.message : String(error)}`
  ];

  if (shellState) {
    parts.push(`Page title: ${shellState.title}`);
    parts.push(`Page URL: ${shellState.location}`);
    parts.push(`Shell status: ${shellState.shellMeta ?? "n/a"}`);
    parts.push(`Error banner: ${shellState.errorBanner ?? "none"}`);
    parts.push(`Tenant select value: ${shellState.tenantValue ?? "n/a"}`);
  }

  if (diagnostics.pageErrors.length > 0) {
    parts.push(`Page errors: ${diagnostics.pageErrors.join(" | ")}`);
  }

  if (diagnostics.failedRequests.length > 0) {
    parts.push(`Failed requests: ${diagnostics.failedRequests.join(" | ")}`);
  }

  if (diagnostics.consoleMessages.length > 0) {
    parts.push(`Console: ${diagnostics.consoleMessages.join(" | ")}`);
  }

  return parts.join("\n");
}

async function safeReadResponseBody(response) {
  const bodyText = await response.text().catch(() => "");
  if (!bodyText) {
    return "Response body was empty.";
  }

  const compactBody = bodyText.replace(/\s+/g, " ").trim();
  const truncatedBody = compactBody.length > 300 ? `${compactBody.slice(0, 300)}...` : compactBody;
  return `Response body: ${truncatedBody}`;
}

function delay(milliseconds) {
  return new Promise(resolve => {
    setTimeout(resolve, milliseconds);
  });
}

async function waitForTenantValue(page, locator, expectedTenantCode, timeoutMs) {
  const startedAt = Date.now();

  while ((Date.now() - startedAt) < timeoutMs) {
    const currentValue = await locator.inputValue().catch(() => "");
    if (equalsIgnoreCase(currentValue, expectedTenantCode)) {
      return;
    }

    await page.waitForTimeout(250);
  }

  throw new Error(`Timed out waiting for tenant selector to resolve '${expectedTenantCode}'.`);
}

function validateRuntimeConfiguration(runtimeConfiguration) {
  if (!runtimeConfiguration || typeof runtimeConfiguration !== "object") {
    throw new Error("Runtime configuration response was empty or invalid.");
  }

  if (typeof runtimeConfiguration.activeTenantCode !== "string" || runtimeConfiguration.activeTenantCode.trim().length === 0) {
    throw new Error("Runtime configuration did not include a valid activeTenantCode.");
  }

  if (typeof runtimeConfiguration.tenantHeaderName !== "string" || runtimeConfiguration.tenantHeaderName.trim().length === 0) {
    throw new Error("Runtime configuration did not include a valid tenantHeaderName.");
  }

  if (!Array.isArray(runtimeConfiguration.availableTenants) || runtimeConfiguration.availableTenants.length === 0) {
    throw new Error("Runtime configuration did not include any available tenants.");
  }
}

function normalizeHeaders(headers) {
  return Object.fromEntries(
    Object.entries(headers).map(([headerName, headerValue]) => [headerName.toLowerCase(), headerValue])
  );
}

function equalsIgnoreCase(left, right) {
  if (typeof left !== "string" || typeof right !== "string") {
    return false;
  }

  return left.trim().toLowerCase() === right.trim().toLowerCase();
}

main().catch(error => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
