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

type FixtureMode = "normal" | "missing-button" | "delayed-clear" | "retained-token" | "provider-error";

async function startFixtureServer(mode: FixtureMode): Promise<{ origin: string; close: () => Promise<void> }> {
  const server = createServer((request, response) => {
    response.setHeader("content-type", "text/html; charset=utf-8");
    if (request.url === "/payments/new") {
      response.end(mode !== "missing-button"
        ? `<script>
             if (sessionStorage.getItem("fixture.account") !== "test-account") throw new Error("Missing restored session");
             localStorage.setItem("orderprocessing.accessToken", "fixture-token");
             document.addEventListener("DOMContentLoaded", () => {
               document.querySelector("button").hidden = false;
               document.querySelector("button").onclick = () => {
                 sessionStorage.removeItem("fixture.account");
                 if (${mode === "normal" || mode === "provider-error"}) localStorage.removeItem("orderprocessing.accessToken");
                 location.assign("/fixture-logout-return");
               };
             });
           </script><button hidden>Sign out</button>`
        : "<main>Payment page</main>");
      return;
    }
    if (request.url === "/fixture-logout-return") {
      response.writeHead(302, { location: "/signed-out" }).end();
      return;
    }
    if (request.url === "/signed-out") {
      response.end(`<h1>Signed out of the application</h1>
        ${mode === "provider-error" ? '<p role="alert">Local access cleared. Identity-provider logout could not be confirmed.</p>' : ""}
        <script>if (${mode === "delayed-clear"} && sessionStorage.getItem("fixture.account") === null) {
          setTimeout(() => localStorage.removeItem("orderprocessing.accessToken"), 150);
        }</script>`);
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
    sessionStorage: { "fixture.account": "test-account" },
    baseUrl: origin,
    authenticated: true
  };
}

test("operator sign-out verifies provider return and clears the application token without payment activity", async () => {
  const fixture = await startFixtureServer("normal");
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
  const fixture = await startFixtureServer("missing-button");
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

test("matrix sign-out waits for token clearance after a redirect without restoring the old session again", async () => {
  const fixture = await startFixtureServer("delayed-clear");
  const runner = new PaymentJourneyRunner();
  try {
    await attachAuthenticatedFixtureSession(runner, fixture.origin);
    await runner.closeOperatorAssistedSession(undefined, true, 2000);
  } finally {
    await fixture.close();
  }
});

for (const [mode, error] of [
  ["retained-token", /timed out while attempting to verify the signed-out screen and application token clearance/],
  ["provider-error", /the application reported that identity-provider logout could not be confirmed/],
] as const) {
  test(`matrix sign-out does not pass for ${mode}`, async () => {
    const fixture = await startFixtureServer(mode);
    const runner = new PaymentJourneyRunner();
    try {
      await attachAuthenticatedFixtureSession(runner, fixture.origin);
      await assert.rejects(runner.closeOperatorAssistedSession(undefined, true, 1000), error);
    } finally {
      await fixture.close();
    }
  });
}
