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

function getPublishingCredentials(resourceGroup, functionApp) {
  try {
    const output = execFileSync('az', ['functionapp', 'deployment', 'list-publishing-credentials', '--resource-group', resourceGroup, '--name', functionApp, '--only-show-errors', '--output', 'json'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    const credentials = JSON.parse(output);
    const endpoint = new URL(credentials.scmUri);
    const expectedScmHost = `${functionApp}.scm.azurewebsites.net`.toLowerCase();
    if (endpoint.protocol !== 'https:' || endpoint.hostname.toLowerCase() !== expectedScmHost || !credentials.publishingUserName || !credentials.publishingPassword) {
      throw new Error('invalid');
    }
    return { endpoint, username: credentials.publishingUserName, password: credentials.publishingPassword };
  } catch {
    throw new Error('Could not obtain a valid HTTPS SCM publishing identity for deployed-package verification.');
  }
}

async function getScmBytes(url, credentials, fetchImpl = fetch) {
  let response;
  try {
    response = await fetchImpl(url, {
      headers: {
        authorization: `Basic ${Buffer.from(`${credentials.username}:${credentials.password}`).toString('base64')}`,
        'cache-control': 'no-store',
      },
      redirect: 'error',
      signal: AbortSignal.timeout(30_000),
    });
  } catch {
    throw new Error('Function App SCM package verification endpoint is unreachable or rejected TLS.');
  }
  if (!response.ok) throw new Error(`Function App SCM package verification returned HTTP ${response.status}.`);
  return Buffer.from(await response.arrayBuffer());
}

export async function verifyMountedFunctionPackage({ scmUri, username, password, packagePointer, expectedSha256, fetchImpl = fetch }) {
  let endpoint;
  try { endpoint = new URL(scmUri); } catch { throw new Error('Function App SCM endpoint is invalid.'); }
  if (endpoint.protocol !== 'https:' || !endpoint.hostname.toLowerCase().endsWith('.scm.azurewebsites.net')) {
    throw new Error('Function App SCM endpoint must use the expected HTTPS Azure hostname.');
  }
  const packageName = parsePackageName(packagePointer);
  const credentials = { username, password };
  const pointerUrl = new URL('/api/vfs/data/SitePackages/packagename.txt', endpoint);
  const actualPointer = (await getScmBytes(pointerUrl, credentials, fetchImpl)).toString('utf8');
  if (parsePackageName(actualPointer) !== packageName) throw new Error('Function App mounted package pointer changed during verification.');
  const packageUrl = new URL(`/api/vfs/data/SitePackages/${encodeURIComponent(packageName)}`, endpoint);
  const packageBytes = await getScmBytes(packageUrl, credentials, fetchImpl);
  return { packageName, packageSha256: verifyFunctionPackageBytes(packageBytes, expectedSha256) };
}

async function main() {
  const resourceGroup = process.env.RESOURCE_GROUP;
  const functionApp = process.env.FUNCTION_APP;
  const expectedSha256 = process.env.PACKAGE_SHA256;
  if (!/^rg-[a-z0-9-]+$/i.test(resourceGroup ?? '') || !/^[a-z0-9-]{2,60}$/i.test(functionApp ?? '')) {
    throw new Error('Function App deployment identity inputs are missing or malformed.');
  }
  const credentials = getPublishingCredentials(resourceGroup, functionApp);
  const packagePointer = (await getScmBytes(new URL('/api/vfs/data/SitePackages/packagename.txt', credentials.endpoint), credentials)).toString('utf8');
  const result = await verifyMountedFunctionPackage({ scmUri: credentials.endpoint.toString(), ...credentials, packagePointer, expectedSha256 });
  console.log(`Verified deployed Functions package ${result.packageName} against approved SHA-256 ${result.packageSha256}.`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => { console.error(`Deployed Functions package identity check failed: ${error.message}`); process.exitCode = 1; });
}
