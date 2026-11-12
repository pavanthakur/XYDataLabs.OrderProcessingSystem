import assert from "node:assert/strict";
import { test } from "node:test";
import { JsonRuntimeTargetCatalog } from "./json-runtime-target-catalog.js";

const uiKey = "XYDATALABS_RUNTIME_TARGET_AZURE_DEV_BASE_URL";
const apiKey = "XYDATALABS_RUNTIME_TARGET_AZURE_DEV_API_BASE_URL";

test("generated Azure-dev target fails closed without both live origins", async () => {
  const previousUi = process.env[uiKey];
  const previousApi = process.env[apiKey];
  try {
    delete process.env[uiKey];
    delete process.env[apiKey];
    await assert.rejects(new JsonRuntimeTargetCatalog().resolve("azure-dev"), /both live/);
  } finally {
    if (previousUi === undefined) delete process.env[uiKey]; else process.env[uiKey] = previousUi;
    if (previousApi === undefined) delete process.env[apiKey]; else process.env[apiKey] = previousApi;
  }
});

test("generated Azure-dev target consumes only HTTPS ACA origins supplied by its workflow", async () => {
  const previousUi = process.env[uiKey];
  const previousApi = process.env[apiKey];
  try {
    process.env[uiKey] = "https://orderprocessing-ui-dev.sample.centralindia.azurecontainerapps.io";
    process.env[apiKey] = "https://orderprocessing-gate-dev.sample.centralindia.azurecontainerapps.io";
    const target = await new JsonRuntimeTargetCatalog().resolve("azure-dev");
    assert.equal(target.publicUiBaseUrl, process.env[uiKey]);
    assert.equal(target.publicApiBaseUrl, process.env[apiKey]);
    process.env[apiKey] = "https://wrong.example.test";
    await assert.rejects(new JsonRuntimeTargetCatalog().resolve("azure-dev"), /invalid generated API origin/);
    process.env[apiKey] = "https://orderprocessing-gate-dev.other.centralindia.azurecontainerapps.io";
    await assert.rejects(new JsonRuntimeTargetCatalog().resolve("azure-dev"), /different ACA environments/);
  } finally {
    if (previousUi === undefined) delete process.env[uiKey]; else process.env[uiKey] = previousUi;
    if (previousApi === undefined) delete process.env[apiKey]; else process.env[apiKey] = previousApi;
  }
});
