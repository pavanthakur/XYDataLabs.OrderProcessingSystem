import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createReleaseManifest, REQUIRED_IMAGES } from '../phase10-release-manifest.mjs';
import { calculateDeploymentIdentity } from '../phase10-deployment-identity.mjs';
import { verifyReleaseInputs } from '../verify-phase10-release-inputs.mjs';

const sourceSha = 'a'.repeat(40);
const digest = (number) => `sha256:${number.toString(16).padStart(64, '0')}`;
const hash = (value) => createHash('sha256').update(value).digest('hex');

test('release inputs require checksummed files, exact image set and reviewed parameters', async (t) => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'phase10-inputs-test-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const packageZip = path.join(root, 'functions.zip');
  await writeFile(packageZip, 'synthetic zip bytes');
  const fragments = Object.entries(REQUIRED_IMAGES).map(([name, repository], index) => ({
    name, repository, sourceSha, image: `xyopsphase10.azurecr.io/${repository}`, digest: digest(index + 1),
  }));
  const repoRoot = path.resolve('.');
  const manifest = await createReleaseManifest({ repository: 'pavanthakur/XYDataLabs.OrderProcessingSystem', sourceSha, runId: '99', runAttempt: '1', fragments, functionsZip: packageZip, repoRoot });
  const releaseDirectory = path.join(root, 'release');
  await mkdir(releaseDirectory);
  await writeFile(path.join(releaseDirectory, 'functions.zip'), await import('node:fs/promises').then(({ readFile }) => readFile(packageZip)));
  await writeFile(path.join(releaseDirectory, 'release-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  await writeFile(path.join(releaseDirectory, 'SHA256SUMS'), `
${hash(await import('node:fs/promises').then(({ readFile }) => readFile(path.join(releaseDirectory, 'release-manifest.json'))))}  release-manifest.json
${hash(await import('node:fs/promises').then(({ readFile }) => readFile(path.join(releaseDirectory, 'functions.zip'))))}  functions.zip
`.trimStart());
  const identity = await calculateDeploymentIdentity({ repositoryRoot: repoRoot, environment: 'dev', location: 'centralindia' });
  const images = Object.fromEntries(manifest.images.map((image) => [image.name, image.image]));
  const options = {
    releaseDirectory, repository: manifest.repository, sourceSha, deploymentWorkflowSha: 'c'.repeat(40), runId: '99', runAttempt: '1',
    artifactName: `phase10-release-${sourceSha}`, functionsPackageSha256: manifest.functionsPackage.sha256,
    approvedParameterIdentity: identity.identitySha256, images,
    deployment: { repositoryRoot: repoRoot, environment: 'dev', location: 'centralindia' },
  };
  assert.equal((await verifyReleaseInputs(options)).manifest.sourceSha, sourceSha);
  await assert.rejects(verifyReleaseInputs({ ...options, actualWorkflowSha: 'd'.repeat(40) }), /does not match the workflow revision/);
  assert.equal((await verifyReleaseInputs({ ...options, actualWorkflowSha: options.deploymentWorkflowSha })).manifest.sourceSha, sourceSha);
  await assert.rejects(verifyReleaseInputs({ ...options, images: { ...images, ui: `${images.ui}-tampered` } }), /ui image input/);
  await assert.rejects(verifyReleaseInputs({ ...options, approvedParameterIdentity: 'b'.repeat(64) }), /parameter identity changed/);
  await writeFile(path.join(releaseDirectory, 'functions.zip'), 'tampered');
  await assert.rejects(verifyReleaseInputs(options), /checksum mismatch/);
});
