import assert from "node:assert/strict";
import test from "node:test";
import { isAppSignedOutUrl, isCustomerListUrl, resolveBrowserApiOrigin } from "./entra-isolation-observation.js";

const ui = "https://ui.example.test";
const gateway = "https://gateway.example.test";
const customerPath = "/api/v1/Customer/GetAllCustomers";

test("the deployed empty API base resolves to the same-origin UI proxy", () => {
  const origin = resolveBrowserApiOrigin(ui, gateway, "");
  assert.equal(origin, ui);
  assert.equal(isCustomerListUrl(ui + customerPath, origin), true);
  assert.equal(isCustomerListUrl(gateway + customerPath, origin), false);
});

test("an explicitly configured gateway remains supported", () => {
  assert.equal(resolveBrowserApiOrigin(ui, gateway, gateway + "/"), gateway);
  assert.equal(isCustomerListUrl(gateway + customerPath, gateway), true);
  assert.equal(isCustomerListUrl(gateway + customerPath + "ByName", gateway), false);
});

test("unapproved bases fail closed", () => {
  for (const base of [undefined, "https://other.example.test", "http://ui.example.test", "/other", ui + "?bad", "https://user@ui.example.test"]) {
    assert.throws(() => resolveBrowserApiOrigin(ui, gateway, base), /UI runtime API base/);
  }
});

test("Entra logout may append callback state but must return to the exact app origin and path", () => {
  for (const url of [ui + "/signed-out", ui + "/signed-out?state=fixture%3D#"]) {
    assert.equal(isAppSignedOutUrl(new URL(url), ui), true);
  }
  for (const url of [gateway + "/signed-out", "https://login.live.com/logout.srf", ui + "/signed-out/other", ui + "/customers?next=/signed-out"]) {
    assert.equal(isAppSignedOutUrl(new URL(url), ui), false);
  }
});
