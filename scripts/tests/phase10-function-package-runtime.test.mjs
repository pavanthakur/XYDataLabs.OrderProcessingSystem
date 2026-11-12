import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { parsePackageName, verifyFunctionPackageBytes, verifyMountedFunctionPackage } from '../verify-phase10-function-package-runtime.mjs';

test('accepts the mounted package pointer and verifies the exact package bytes', () => {
  const bytes = Buffer.from('approved package');
  const sha = createHash('sha256').update(bytes).digest('hex');
  assert.equal(parsePackageName('functions-abc123.zip'), 'functions-abc123.zip');
  assert.equal(verifyFunctionPackageBytes(bytes, sha), sha);
});

test('rejects unsafe package pointers and byte mismatches', () => {
  for (const pointer of ['../functions.zip', 'C:\\temp\\functions.zip', 'functions.zip?sig=secret', '/package.zip']) {
    assert.throws(() => parsePackageName(pointer), /missing or unsafe/);
  }
  assert.throws(() => verifyFunctionPackageBytes(Buffer.from('wrong'), 'a'.repeat(64)), /do not match/);
});

test('retrieves only the active mounted package from the exact HTTPS SCM host without following redirects', async () => {
  const bytes = Buffer.from('approved mounted package');
  const sha = createHash('sha256').update(bytes).digest('hex');
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url: String(url), init });
    return calls.length === 1
      ? new Response('functions-abc123.zip\n', { status: 200 })
      : new Response(bytes, { status: 200 });
  };
  const result = await verifyMountedFunctionPackage({
    scmUri: 'https://orders-functions-dev.scm.azurewebsites.net',
    username: 'operator',
    password: 'not-logged',
    packagePointer: 'functions-abc123.zip',
    expectedSha256: sha,
    fetchImpl,
  });
  assert.equal(result.packageSha256, sha);
  assert.equal(calls.length, 2);
  assert.ok(calls.every(({ url, init }) => url.startsWith('https://orders-functions-dev.scm.azurewebsites.net/api/vfs/data/SitePackages/')));
  assert.ok(calls.every(({ init }) => init.redirect === 'error' && init.signal instanceof AbortSignal));
});

test('rejects an SCM redirect instead of forwarding publishing credentials', async () => {
  const bytes = Buffer.from('approved package');
  const sha = createHash('sha256').update(bytes).digest('hex');
  await assert.rejects(verifyMountedFunctionPackage({
    scmUri: 'https://orders-functions-dev.scm.azurewebsites.net',
    username: 'operator',
    password: 'not-logged',
    packagePointer: 'functions-abc123.zip',
    expectedSha256: sha,
    fetchImpl: async (_url, init) => {
      assert.equal(init.redirect, 'error');
      throw new Error('redirect rejected');
    },
  }), /unreachable or rejected TLS/);
});
