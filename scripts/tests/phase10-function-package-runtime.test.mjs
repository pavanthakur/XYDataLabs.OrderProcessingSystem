import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { getEntraAccessToken, parsePackageName, verifyFunctionPackageBytes, verifyMountedFunctionPackage } from '../verify-phase10-function-package-runtime.mjs';

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

test('obtains the CLI access token for the Azure Resource Manager audience without exposing it', () => {
  const token = 'eyJhbGciOiJub25lIn0.eyJhdWQiOiJtYW5hZ2VtZW50In0.signature';
  let call;
  assert.equal(getEntraAccessToken((...args) => { call = args; return token; }), token);
  assert.equal(call[0], 'az');
  assert.deepEqual(call[1].slice(0, 3), ['account', 'get-access-token', '--resource']);
  assert.ok(call[1].includes('https://management.azure.com/'));
  assert.ok(!JSON.stringify(call).includes(token));
});

test('does not reveal Azure CLI errors or token output when OIDC token acquisition fails', () => {
  assert.throws(() => getEntraAccessToken(() => { throw new Error('secret-token-value'); }), (error) => {
    assert.match(error.message, /active Azure CLI OIDC session/);
    assert.ok(!error.message.includes('secret-token-value'));
    return true;
  });
  assert.throws(() => getEntraAccessToken(() => 'token with whitespace'), /Could not obtain/);
});

test('uses Bearer auth only on the exact HTTPS SCM host and verifies the active mounted package bytes', async () => {
  const bytes = Buffer.from('approved mounted package');
  const sha = createHash('sha256').update(bytes).digest('hex');
  const token = 'entra-token-not-for-logs';
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url: String(url), init });
    if (calls.length === 1 || calls.length === 3) return new Response('functions-abc123.zip\n', { status: 200 });
    return new Response(bytes, { status: 200 });
  };
  const result = await verifyMountedFunctionPackage({
    functionApp: 'orders-functions-dev', accessToken: token, expectedSha256: sha, fetchImpl,
  });
  assert.deepEqual(result, { packageName: 'functions-abc123.zip', packageSha256: sha });
  assert.equal(calls.length, 3);
  assert.ok(calls.every(({ url }) => url.startsWith('https://orders-functions-dev.scm.azurewebsites.net/api/vfs/data/SitePackages/')));
  assert.ok(calls.every(({ url, init }) => !url.includes(token) && init.headers.authorization === `Bearer ${token}`));
  assert.ok(calls.every(({ init }) => init.redirect === 'error' && init.signal instanceof AbortSignal));
});

test('rejects an SCM hostname that cannot be derived from a valid Function App name', async () => {
  await assert.rejects(verifyMountedFunctionPackage({
    functionApp: 'attacker.example', accessToken: 'entra-token', expectedSha256: 'a'.repeat(64),
    fetchImpl: async () => { throw new Error('must not fetch'); },
  }), /deployment identity inputs are missing or malformed/);
});

test('rejects a changed package pointer rather than reporting an unstable mount as verified', async () => {
  const bytes = Buffer.from('approved package');
  const sha = createHash('sha256').update(bytes).digest('hex');
  let callCount = 0;
  await assert.rejects(verifyMountedFunctionPackage({
    functionApp: 'orders-functions-dev', accessToken: 'entra-token', expectedSha256: sha,
    fetchImpl: async () => {
      callCount += 1;
      if (callCount === 1) return new Response('functions-first.zip', { status: 200 });
      if (callCount === 2) return new Response(bytes, { status: 200 });
      return new Response('functions-second.zip', { status: 200 });
    },
  }), /pointer changed during verification/);
});

test('rejects an SCM redirect instead of forwarding the Entra bearer token', async () => {
  const sha = createHash('sha256').update(Buffer.from('approved package')).digest('hex');
  await assert.rejects(verifyMountedFunctionPackage({
    functionApp: 'orders-functions-dev', accessToken: 'entra-token', expectedSha256: sha,
    fetchImpl: async (_url, init) => {
      assert.equal(init.redirect, 'error');
      throw new Error('redirect rejected');
    },
  }), /unreachable or rejected TLS/);
});
