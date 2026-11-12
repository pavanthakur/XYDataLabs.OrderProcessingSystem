import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateReleaseManifest } from './phase10-release-manifest.mjs';
import { calculateDeploymentIdentity } from './phase10-deployment-identity.mjs';

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

export async function verifyReleaseInputs({ releaseDirectory, repository, sourceSha, deploymentWorkflowSha, actualWorkflowSha, runId, runAttempt, artifactName, functionsPackageSha256, approvedParameterIdentity, images, deployment }) {
  if (!/^[0-9a-f]{40}$/.test(sourceSha ?? '')) throw new Error('A full lowercase candidate SHA is required.');
  if (!/^[0-9a-f]{40}$/.test(deploymentWorkflowSha ?? '')) throw new Error('A full lowercase deployment workflow SHA is required.');
  if (actualWorkflowSha && deploymentWorkflowSha !== actualWorkflowSha) throw new Error('Deployment workflow SHA does not match the workflow revision running this job.');
  if (!/^[0-9]+$/.test(String(runId)) || !/^[0-9]+$/.test(String(runAttempt))) throw new Error('Release run ID and attempt are required.');
  if (artifactName !== `phase10-release-${sourceSha}`) throw new Error('Release artifact name does not match the source SHA.');
  if (!/^[0-9a-f]{64}$/.test(functionsPackageSha256 ?? '') || !/^[0-9a-f]{64}$/.test(approvedParameterIdentity ?? '')) throw new Error('Functions package hash and approved parameter identity must be SHA-256 values.');

  const manifestPath = path.join(releaseDirectory, 'release-manifest.json');
  const zipPath = path.join(releaseDirectory, 'functions.zip');
  const sumsText = await readFile(path.join(releaseDirectory, 'SHA256SUMS'), 'utf8');
  const manifestBytes = await readFile(manifestPath);
  const zipBytes = await readFile(zipPath);
  const expectedSums = new Map();
  for (const line of sumsText.split(/\r?\n/).filter(Boolean)) {
    const match = line.match(/^([0-9a-f]{64})  (release-manifest\.json|functions\.zip)$/i);
    if (!match || expectedSums.has(match[2])) throw new Error('Release checksum file is malformed or contains unexpected paths.');
    expectedSums.set(match[2], match[1].toLowerCase());
  }
  if (expectedSums.size !== 2 || expectedSums.get('release-manifest.json') !== sha256(manifestBytes) || expectedSums.get('functions.zip') !== sha256(zipBytes)) {
    throw new Error('Release artifact file checksum mismatch.');
  }
  const manifest = JSON.parse(manifestBytes.toString('utf8'));
  await validateReleaseManifest(manifest, { repository, sourceSha, runId, runAttempt, functionsZip: zipPath });
  if (manifest.functionsPackage.sha256 !== functionsPackageSha256) throw new Error('Functions package hash does not match the approved workflow input.');
  for (const name of ['gateway', 'orders', 'payments', 'inventory', 'notifications', 'ui']) {
    const expected = manifest.images.find((image) => image.name === name)?.image;
    if (!expected || images?.[name] !== expected) throw new Error(`${name} image input does not match the immutable release manifest.`);
  }

  const identity = await calculateDeploymentIdentity(deployment);
  if (identity.identitySha256 !== approvedParameterIdentity) throw new Error('Deployment parameter identity changed after review.');
  return { manifest, parameterIdentity: identity };
}

async function main() {
  const result = await verifyReleaseInputs({
    releaseDirectory: process.env.RELEASE_DIRECTORY ?? 'phase10-release',
    repository: process.env.GITHUB_REPOSITORY,
    sourceSha: process.env.CANDIDATE_SHA,
    deploymentWorkflowSha: process.env.DEPLOYMENT_WORKFLOW_SHA,
    actualWorkflowSha: process.env.ACTUAL_WORKFLOW_SHA,
    runId: process.env.RELEASE_RUN_ID,
    runAttempt: process.env.RELEASE_RUN_ATTEMPT,
    artifactName: process.env.RELEASE_ARTIFACT_NAME,
    functionsPackageSha256: process.env.FUNCTIONS_PACKAGE_SHA256,
    approvedParameterIdentity: process.env.APPROVED_PARAMETER_IDENTITY,
    images: {
      gateway: process.env.GATEWAY_IMAGE,
      orders: process.env.ORDERS_IMAGE,
      payments: process.env.PAYMENTS_IMAGE,
      inventory: process.env.INVENTORY_IMAGE,
      notifications: process.env.NOTIFICATIONS_IMAGE,
      ui: process.env.UI_IMAGE,
    },
    deployment: {
      repositoryRoot: process.cwd(),
      environment: process.env.TARGET_ENVIRONMENT,
      location: process.env.TARGET_LOCATION,
      publicDomain: process.env.PUBLIC_DOMAIN ?? '',
      bindAliases: process.env.BIND_ALIASES === 'true',
      aliasMode: process.env.ALIAS_MODE ?? 'direct',
      cleanupInfra: process.env.CLEANUP_INFRA === 'true',
    },
  });
  console.log(`Verified release source ${result.manifest.sourceSha}, deployment workflow ${process.env.DEPLOYMENT_WORKFLOW_SHA}, six immutable images, Functions package, and approved deployment parameter identity.`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => { console.error(`Phase 10 release inputs rejected: ${error.message}`); process.exitCode = 1; });
}
