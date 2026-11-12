import test from 'node:test';
import assert from 'node:assert/strict';
import { resolveGeneratedDevUrls } from '../resolve-phase10-azure-generated-urls.mjs';

const suffix = 'sample.centralindia.azurecontainerapps.io';
const ui = `https://orderprocessing-ui-dev.${suffix}`;
const api = `https://orderprocessing-gate-dev.${suffix}`;

test('Azure dev derives exact public origins without storing a generated hostname in the catalog', () => {
  const value = resolveGeneratedDevUrls({ targetKey: 'azure-dev', defaultDomain: suffix, expectedUiOrigin: ui });
  assert.equal(value.uiOrigin, ui);
  assert.equal(value.apiOrigin, api);
  assert.equal(value.gatewayFqdn, `orderprocessing-gate-dev.${suffix}`);
});

test('generated origin resolution rejects foreign apps, wrong Entra origin, and other environments', () => {
  const input = { targetKey: 'azure-dev', defaultDomain: suffix };
  assert.throws(() => resolveGeneratedDevUrls({ ...input, gatewayFqdn: `other.${suffix}` }), /Gateway FQDN/);
  assert.throws(() => resolveGeneratedDevUrls({ ...input, uiFqdn: `other.${suffix}` }), /UI FQDN/);
  assert.throws(() => resolveGeneratedDevUrls({ ...input, requireLiveApps: true }), /Both live/);
  assert.throws(() => resolveGeneratedDevUrls({ ...input, expectedUiOrigin: 'https://wrong.example.test' }), /IDENTITY_PUBLIC_WEB_ORIGIN/);
  assert.throws(() => resolveGeneratedDevUrls({ ...input, defaultDomain: 'evil.example.test' }), /domain/);
  assert.throws(() => resolveGeneratedDevUrls({ ...input, targetKey: 'azure-stg' }), /only/);
});
