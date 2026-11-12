import { readFile, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export const REQUIRED_REPOSITORIES = Object.freeze([
  'orderprocessing-gateway',
  'orderprocessing-orders',
  'orderprocessing-payments',
  'orderprocessing-inventory',
  'orderprocessing-notifications',
  'orderprocessing-ui',
]);
export const REQUIRED_ENVIRONMENTS = Object.freeze(['dev', 'staging', 'prod']);

const DIGEST = /^sha256:[a-f0-9]{64}$/i;

export function planAcrRetention({ manifests, activeDigests, rollbackDigests, inventoryComplete, activeRevisionEnvironments, now = new Date(), keepLatest = 10, olderThanDays = 30 }) {
  if (!Array.isArray(manifests) || !Array.isArray(activeDigests) || !Array.isArray(rollbackDigests)) {
    throw new Error('Complete manifest, active-digest, and rollback-digest inventories are required.');
  }
  const hasCompleteEnvironmentSet = Array.isArray(activeRevisionEnvironments)
    && activeRevisionEnvironments.length === REQUIRED_ENVIRONMENTS.length
    && REQUIRED_ENVIRONMENTS.every((environment) => activeRevisionEnvironments.includes(environment));
  if (inventoryComplete?.manifests !== true || inventoryComplete?.activeRevisions !== true || !hasCompleteEnvironmentSet) {
    throw new Error('Complete manifest and active-revision inventories for dev, staging, and prod are required.');
  }
  if (!Number.isInteger(keepLatest) || keepLatest < 2 || !Number.isInteger(olderThanDays) || olderThanDays < 1) {
    throw new Error('Retention limits must keep at least two manifests per service and use a positive age threshold.');
  }

  if (!Number.isFinite(new Date(now).getTime())) throw new Error('Retention preview timestamp is invalid.');
  const byDigest = new Map();
  const normalizedManifests = [];
  for (const item of manifests) {
    if (!REQUIRED_REPOSITORIES.includes(item?.repository) || !DIGEST.test(item?.digest ?? '')
      || (item.tags !== undefined && item.tags !== null && !Array.isArray(item.tags))
      || !Number.isFinite(Date.parse(item.lastUpdateTime ?? ''))) {
      throw new Error('Manifest inventory contains an invalid repository, digest, tags, or timestamp.');
    }
    const key = `${item.repository}@${item.digest}`;
    if (byDigest.has(key)) throw new Error('Manifest inventory contains duplicate repository digests.');
    const normalized = { ...item, tags: item.tags ?? [], lastUpdateTime: new Date(item.lastUpdateTime).toISOString() };
    byDigest.set(key, normalized);
    normalizedManifests.push(normalized);
  }
  for (const repository of REQUIRED_REPOSITORIES) {
    if (!normalizedManifests.some((item) => item.repository === repository)) throw new Error(`Manifest inventory is incomplete for ${repository}.`);
    const backups = rollbackDigests.filter((item) => item?.repository === repository);
    if (backups.length !== 1) throw new Error(`Exactly one verified rollback digest is required for ${repository}.`);
    if (!DIGEST.test(backups[0]?.digest ?? '') || backups[0].verified !== true
      || !/^[a-f0-9]{40,64}$/i.test(backups[0].sourceSha ?? '')
      || typeof backups[0].evidenceRef !== 'string' || backups[0].evidenceRef.trim().length === 0) {
      throw new Error(`Rollback evidence is invalid for ${repository}.`);
    }
    const active = activeDigests.filter((item) => item?.repository === repository).map((item) => item.digest);
    if (active.includes(backups[0].digest)) throw new Error(`Rollback digest for ${repository} must differ from its currently deployed digest.`);
  }
  const protectedItems = [...activeDigests, ...rollbackDigests];
  if (activeDigests.some((item) => !REQUIRED_ENVIRONMENTS.includes(item?.environment))
    || protectedItems.some((item) => !REQUIRED_REPOSITORIES.includes(item?.repository) || !DIGEST.test(item?.digest ?? '')
    || !byDigest.has(`${item.repository}@${item.digest}`))) {
    throw new Error('An active or rollback digest is invalid or absent from the complete ACR manifest inventory.');
  }

  const protectedSet = new Set(protectedItems.map((item) => `${item.repository}@${item.digest}`));
  const cutoff = new Date(now).getTime() - olderThanDays * 24 * 60 * 60 * 1000;
  const decisions = [];
  for (const repository of REQUIRED_REPOSITORIES) {
    const ordered = normalizedManifests.filter((item) => item.repository === repository)
      .slice().sort((a, b) => Date.parse(b.lastUpdateTime) - Date.parse(a.lastUpdateTime));
    ordered.forEach((item, index) => {
      const reasons = [];
      if (index < keepLatest) reasons.push('within-latest-retention');
      if (Date.parse(item.lastUpdateTime) >= cutoff) reasons.push('within-age-retention');
      if (protectedSet.has(`${repository}@${item.digest}`)) reasons.push('active-or-verified-rollback');
      decisions.push({ repository, digest: item.digest, tags: [...item.tags].sort(), action: reasons.length ? 'keep' : 'candidate', reasons });
    });
  }
  return { status: 'PREVIEW_ONLY', deletionEnabled: false, inventoryComplete: { manifests: true, activeRevisions: true, environments: [...activeRevisionEnvironments].sort() }, decisions };
}

async function main(args) {
  const inputIndex = args.indexOf('--input');
  const outputIndex = args.indexOf('--output');
  if (inputIndex < 0 || !args[inputIndex + 1]) throw new Error('Usage: node scripts/phase10-acr-retention.mjs --input inventory.json [--output report.json]');
  const input = JSON.parse(await readFile(args[inputIndex + 1], 'utf8'));
  const report = planAcrRetention(input);
  const json = `${JSON.stringify(report, null, 2)}\n`;
  if (outputIndex >= 0 && args[outputIndex + 1]) await writeFile(args[outputIndex + 1], json, { flag: 'wx' });
  else process.stdout.write(json);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(`ACR retention preview blocked: ${error.message}`);
    process.exitCode = 1;
  });
}
