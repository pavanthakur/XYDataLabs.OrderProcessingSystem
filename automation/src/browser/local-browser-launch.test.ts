import test from "node:test";
import assert from "node:assert/strict";
import { launchLocalBrowser } from "./local-browser-launch.js";

test("operator browser launches headed directly without a chat browser connection", async () => {
  let options: unknown;
  const browser = {};
  assert.equal(await launchLocalBrowser(async (input) => { options = input; return browser; }, false, true), browser);
  assert.deepEqual(options, { headless: false, args: ["--start-maximized"] });
});
test("launch failure is actionable and never emits raw launcher diagnostics", async () => {
  await assert.rejects(launchLocalBrowser(async () => { throw new Error("sensitive launcher diagnostic"); }, false, true), (error: Error) => {
    assert.match(error.message, /BROWSER_LAUNCH_FAILED/);
    assert.doesNotMatch(error.message, /sensitive/);
    return true;
  });
});
