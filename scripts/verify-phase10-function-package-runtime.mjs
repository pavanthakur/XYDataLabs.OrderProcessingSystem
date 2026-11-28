import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export function parsePackageName(value) {
  const name = String(value ?? '').trim();
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,180}\.zip$/i.test(name) || name.includes('..')) {
    throw new Error('Function App package pointer is missing or unsafe.');
  }
  return name;
}

export function verifyFunctionPackageBytes(bytes, expectedSha256) {
  if (!/^[0-9a-f]{64}$/i.test(expectedSha256 ?? '')) throw new Error('Expected Functions package identity is malformed.');
  const actual = createHash('sha256').update(bytes).digest('hex');
  if (actual !== expectedSha256.toLowerCase()) throw new Error('Function App mounted package bytes do not match the approved release package.');
  return actual;
}

export function getEntraAccessToken(execFile = execFileSync) {
  try {
    const token = execFile('az', [
      'account', 'get-access-token',
      '--resource', 'https://management.azure.com/',
      '--query', 'accessToken',
      '--output', 'tsv',
      '--only-show-errors',
    ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
    if (!token || /\s/.test(token)) throw new Error('invalid');
    return token;
  } catch {
    throw new Error('Could not obtain a Microsoft Entra access token from the active Azure CLI OIDC session.');
  }
}

function getFunctionScmEndpoint(functionApp) {
  if (!/^[a-z0-9](?:[a-z0-9-]{0,58}[a-z0-9])?$/i.test(functionApp ?? '')) {
    throw new Error('Function App deployment identity inputs are missing or malformed.');
  }
  return new URL(`https://${functionApp}.scm.azurewebsites.net`);
}

const SCM_RETRYABLE_STATUSES = new Set([429, 502, 503, 504]);
const SCM_RETRY_DELAYS_MS = [1_000, 2_000, 4_000, 8_000];

function retryAfterDelayMs(response) {
  const raw = response.headers?.get?.('retry-after');
  if (!raw) return undefined;
  const seconds = Number(raw);
  if (Number.isFinite(seconds) && seconds >= 0) return Math.min(seconds * 1_000, 10_000);
  const date = Date.parse(raw);
  return Number.isFinite(date) ? Math.min(Math.max(date - Date.now(), 0), 10_000) : undefined;
}

async function getScmBytes(url, accessToken, fetchImpl = fetch, sleepImpl = (ms) => new Promise((resolve) => setTimeout(resolve, ms))) {
  if (typeof accessToken !== 'string' || !accessToken || /\s/.test(accessToken)) {
    throw new Error('A valid Microsoft Entra access token is required for Function App package verification.');
  }
  for (let attempt = 0; attempt <= SCM_RETRY_DELAYS_MS.length; attempt += 1) {
    let response;
    try {
      response = await fetchImpl(url, {
        headers: {
          authorization: `Bearer ${accessToken}`,
          'cache-control': 'no-store',
        },
        redirect: 'error',
        signal: AbortSignal.timeout(30_000),
      });
    } catch {
      throw new Error('Function App SCM package verification endpoint is unreachable or rejected TLS.');
    }
    if (response.ok) return Buffer.from(await response.arrayBuffer());
    if (!SCM_RETRYABLE_STATUSES.has(response.status) || attempt === SCM_RETRY_DELAYS_MS.length) {
      throw new Error(`Function App SCM package verification returned HTTP ${response.status}.`);
    }
    const delay = retryAfterDelayMs(response) ?? SCM_RETRY_DELAYS_MS[attempt];
    await sleepImpl(delay);
  }
  throw new Error('Function App SCM package verification exhausted its bounded retries.');
}

export async function verifyMountedFunctionPackage({ functionApp, accessToken, expectedSha256, fetchImpl = fetch, sleepImpl }) {
  const endpoint = getFunctionScmEndpoint(functionApp);
  const pointerUrl = new URL('/api/vfs/data/SitePackages/packagename.txt', endpoint);
  const firstPointer = parsePackageName((await getScmBytes(pointerUrl, accessToken, fetchImpl, sleepImpl)).toString('utf8'));
  const packageUrl = new URL(`/api/vfs/data/SitePackages/${encodeURIComponent(firstPointer)}`, endpoint);
  const packageBytes = await getScmBytes(packageUrl, accessToken, fetchImpl, sleepImpl);
  const secondPointer = parsePackageName((await getScmBytes(pointerUrl, accessToken, fetchImpl, sleepImpl)).toString('utf8'));
  if (secondPointer !== firstPointer) throw new Error('Function App mounted package pointer changed during verification.');
  return { packageName: firstPointer, packageSha256: verifyFunctionPackageBytes(packageBytes, expectedSha256) };
}

async function main() {
  const functionApp = process.env.FUNCTION_APP;
  const expectedSha256 = process.env.PACKAGE_SHA256;
  const accessToken = getEntraAccessToken();
  const result = await verifyMountedFunctionPackage({ functionApp, accessToken, expectedSha256 });
  console.log(`Verified deployed Functions package ${result.packageName} against approved SHA-256 ${result.packageSha256}.`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => { console.error(`Deployed Functions package identity check failed: ${error.message}`); process.exitCode = 1; });
}
