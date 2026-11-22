import assert from "node:assert/strict";
import { createServer } from "node:http";
import { test } from "node:test";
import { chromium, type Browser, type BrowserContext } from "playwright";
import { PaymentJourneyRunner } from "./payment-journey-runner.js";

type RunnerWithOperatorSession = {
  operatorSession?: {
    browser: Browser;
    context: BrowserContext;
    sessionStorage: Record<string, string>;
    baseUrl: string;
    authenticated: boolean;
  };
};

async function startFixtureServer(showSignOut: boolean): Promise<{ origin: string; close: () => Promise<void> }> {
  const server = createServer((request, response) => {
    response.setHeader("content-type", "text/html; charset=utf-8");
    if (request.url === "/payments/new") {
      response.end(showSignOut
        ? '<script>localStorage.setItem("orderprocessing.accessToken", "fixture-token")</script><button onclick="localStorage.removeItem(\'orderprocessing.accessToken\'); location.assign(\'/signed-out\')">Sign out</button>'
        : "<main>Payment page</main>");
      return;
    }
    if (request.url === "/signed-out") {
      response.end("<h1>Signed out of the application</h1>");
      return;
    }
    response.writeHead(404).end();
  });

  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  assert.ok(address && typeof address === "object");
  return {
    origin: `http://127.0.0.1:${address.port}`,
    close: () => new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
  };
}

async function attachAuthenticatedFixtureSession(runner: PaymentJourneyRunner, origin: string): Promise<void> {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  (runner as unknown as RunnerWithOperatorSession).operatorSession = {
    browser,
    context,
    sessionStorage: {},
    baseUrl: origin,
    authenticated: true
  };
}

test("operator sign-out verifies provider return and clears the application token without payment activity", async () => {
  const fixture = await startFixtureServer(true);
  const runner = new PaymentJourneyRunner();
  const logs: string[] = [];
  try {
    await attachAuthenticatedFixtureSession(runner, fixture.origin);
    await runner.closeOperatorAssistedSession(message => logs.push(message), true, 1000);
    assert.deepEqual(logs, ["One Entra sign-out completed after the selected tenant payment journeys; the application token was cleared."]);
  } finally {
    await fixture.close();
  }
});

test("operator sign-out reports a safe failing stage when the application control is absent", async () => {
  const fixture = await startFixtureServer(false);
  const runner = new PaymentJourneyRunner();
  const logs: string[] = [];
  try {
    await attachAuthenticatedFixtureSession(runner, fixture.origin);
    await assert.rejects(
      runner.closeOperatorAssistedSession(message => logs.push(message), true, 100),
      /Entra sign-out verification timed out while attempting to wait for the application sign-out control\./
    );
    assert.deepEqual(logs, ["Entra sign-out verification timed out while attempting to wait for the application sign-out control."]);
  } finally {
    await fixture.close();
  }
});
