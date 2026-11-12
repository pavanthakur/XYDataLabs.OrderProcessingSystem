import { createHash } from 'node:crypto';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const REQUIRED_IMAGES = Object.freeze({
  gateway: 'orderprocessing-gateway',
  orders: 'orderprocessing-orders',
  payments: 'orderprocessing-payments',
  inventory: 'orderprocessing-inventory',
  notifications: 'orderprocessing-notifications',
  ui: 'orderprocessing-ui',
});

export const BUILD_INPUTS = Object.freeze([
  'XYDataLabs.OrderProcessingSystem.Gateway/Dockerfile',
  'XYDataLabs.OrderProcessingSystem.Orders.Host/Dockerfile',
  'XYDataLabs.OrderProcessingSystem.Payments.Host/Dockerfile',
  'XYDataLabs.OrderProcessingSystem.Inventory.Host/Dockerfile',
  'XYDataLabs.OrderProcessingSystem.Notifications.Host/Dockerfile',
  'frontend/apps/web/Dockerfile',
  'global.json',
  'Directory.Packages.props',
  'NuGet.Config',
  'frontend/package-lock.json',
  'automation/package-lock.json',
  'XYDataLabs.OrderProcessingSystem.Functions/XYDataLabs.OrderProcessingSystem.Functions.csproj',
]);

const sha256 = (value) => createHash('sha256').update(value).digest('hex');

function requireSha(value, label) {
  if (typeof value !== 'string' || !/^[0-9a-f]{40}$/i.test(value)) {
    throw new Error(`${label} must be a full 40-character commit SHA.`);
  }
  return value.toLowerCase();
}

function requireDigest(value, label) {
  if (typeof value !== 'string' || !/^sha256:[0-9a-f]{64}$/i.test(value)) {
    throw new Error(`${label} must be a sha256 digest.`);
  }
  return value.toLowerCase();
}

export async function createReleaseManifest({ repository, sourceSha, runId, runAttempt, fragments, functionsZip, repoRoot }) {
  const commit = requireSha(sourceSha, 'sourceSha');
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository ?? '')) throw new Error('repository must be owner/name.');
  if (!/^\d+$/.test(String(runId ?? ''))) throw new Error('runId must be numeric.');
  if (!/^\d+$/.test(String(runAttempt ?? ''))) throw new Error('runAttempt must be numeric.');

  const names = Object.keys(REQUIRED_IMAGES);
  if (!Array.isArray(fragments) || fragments.length !== names.length) throw new Error('Exactly six image fragments are required.');
  const seen = new Set();
  const images = fragments.map((fragment) => {
    const expectedRepository = REQUIRED_IMAGES[fragment?.name];
    if (!expectedRepository || seen.has(fragment.name)) throw new Error('Image fragments contain an unexpected or duplicate workload.');
    seen.add(fragment.name);
    if (fragment.repository !== expectedRepository) throw new Error(`Image repository does not match the ${fragment.name} workload contract.`);
    if (requireSha(fragment.sourceSha, `${fragment.name}.sourceSha`) !== commit) throw new Error('Image fragments contain mixed source revisions.');
    const digest = requireDigest(fragment.digest, `${fragment.name}.digest`);
    const prefix = String(fragment.image ?? '');
    if (!/^[-a-z0-9.]+\.azurecr\.io\/[a-z0-9-]+$/i.test(prefix) || !prefix.endsWith(`/${expectedRepository}`)) {
      throw new Error(`Image reference for ${fragment.name} must use the expected ACR repository.`);
    }
    return { name: fragment.name, repository: expectedRepository, image: `${prefix}@${digest}`, digest };
  });
  for (const name of names) if (!seen.has(name)) throw new Error(`Missing image workload: ${name}.`);
  images.sort((a, b) => names.indexOf(a.name) - names.indexOf(b.name));

  const zipBytes = await readFile(functionsZip);
  if (zipBytes.length === 0) throw new Error('Functions package must not be empty.');
  const buildInputs = [];
  for (const relativePath of BUILD_INPUTS) {
    const bytes = await readFile(path.join(repoRoot, relativePath));
    buildInputs.push({ path: relativePath.replaceAll('\\', '/'), sha256: sha256(bytes) });
  }

  return {
    schemaVersion: 1,
    repository,
    sourceSha: commit,
    producer: {
      workflow: '.github/workflows/build-phase10-images.yml',
      runId: String(runId),
      runAttempt: String(runAttempt),
    },
    images,
    functionsPackage: {
      file: 'functions.zip',
      sha256: sha256(zipBytes),
      sizeBytes: zipBytes.length,
    },
    buildInputs,
  };
}

export async function validateReleaseManifest(manifest, { repository, sourceSha, runId, runAttempt, functionsZip }) {
  const expectedSha = requireSha(sourceSha, 'expected sourceSha');
  if (manifest?.schemaVersion !== 1) throw new Error('Unsupported release manifest schema.');
  if (manifest.repository !== repository) throw new Error('Release manifest repository mismatch.');
  if (requireSha(manifest.sourceSha, 'manifest sourceSha') !== expectedSha) throw new Error('Release manifest source SHA mismatch.');
  if (manifest.producer?.workflow !== '.github/workflows/build-phase10-images.yml' ||
      String(manifest.producer?.runId) !== String(runId) || String(manifest.producer?.runAttempt) !== String(runAttempt)) {
    throw new Error('Release producer run identity mismatch.');
  }
  if (!Array.isArray(manifest.images) || manifest.images.length !== Object.keys(REQUIRED_IMAGES).length) throw new Error('Release manifest must contain exactly six images.');
  const seen = new Set();
  for (const image of manifest.images) {
    const expected = REQUIRED_IMAGES[image?.name];
    if (!expected || seen.has(image.name) || image.repository !== expected) throw new Error('Release manifest has an unexpected, duplicate, or mismatched image workload.');
    seen.add(image.name);
    const digest = requireDigest(image.digest, `${image.name}.digest`);
    if (typeof image.image !== 'string' || !new RegExp(`^[a-z0-9-]+\\.azurecr\\.io/${expected}@${digest}$`, 'i').test(image.image)) {
      throw new Error(`${image.name} image must be selected by its digest-qualified repository reference.`);
    }
  }
  for (const name of Object.keys(REQUIRED_IMAGES)) if (!seen.has(name)) throw new Error(`Missing image workload: ${name}.`);
  if (!Array.isArray(manifest.buildInputs) || manifest.buildInputs.length !== BUILD_INPUTS.length || new Set(manifest.buildInputs.map((entry) => entry.path)).size !== BUILD_INPUTS.length || !BUILD_INPUTS.every((item) => manifest.buildInputs.some((entry) => entry.path === item && /^[0-9a-f]{64}$/i.test(entry.sha256 ?? '')))) {
    throw new Error('Release manifest is missing required build input fingerprints.');
  }
  const packageInfo = manifest.functionsPackage;
  if (packageInfo?.file !== 'functions.zip' || !/^[0-9a-f]{64}$/i.test(packageInfo.sha256 ?? '') || !Number.isSafeInteger(packageInfo.sizeBytes) || packageInfo.sizeBytes < 1) {
    throw new Error('Functions package metadata is invalid.');
  }
  const actualZip = await readFile(functionsZip);
  if (actualZip.length !== packageInfo.sizeBytes || sha256(actualZip) !== packageInfo.sha256.toLowerCase()) throw new Error('Functions package checksum or size mismatch.');
  return true;
}

async function main() {
  const [mode, ...args] = process.argv.slice(2);
  if (mode === 'create') {
    const options = Object.fromEntries(args.map((arg, index) => arg.startsWith('--') ? [arg.slice(2), args[index + 1]] : null).filter(Boolean));
    const fragments = [];
    for (const file of (await readdir(options.fragmentsDir)).filter((name) => name.endsWith('.json')).sort()) {
      fragments.push(JSON.parse(await readFile(path.join(options.fragmentsDir, file), 'utf8')));
    }
    const manifest = await createReleaseManifest({ repository: options.repository, sourceSha: options.sourceSha, runId: options.runId, runAttempt: options.runAttempt, fragments, functionsZip: options.functionsZip, repoRoot: options.repoRoot });
    await writeFile(options.output, `${JSON.stringify(manifest, null, 2)}\n`, { flag: 'wx' });
    return;
  }
  if (mode === 'validate') {
    const options = Object.fromEntries(args.map((arg, index) => arg.startsWith('--') ? [arg.slice(2), args[index + 1]] : null).filter(Boolean));
    const manifest = JSON.parse(await readFile(options.manifest, 'utf8'));
    await validateReleaseManifest(manifest, { repository: options.repository, sourceSha: options.sourceSha, runId: options.runId, runAttempt: options.runAttempt, functionsZip: options.functionsZip });
    return;
  }
  throw new Error('Usage: phase10-release-manifest.mjs create|validate --name value ...');
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => { console.error(`Phase 10 release manifest rejected: ${error.message}`); process.exitCode = 1; });
}
