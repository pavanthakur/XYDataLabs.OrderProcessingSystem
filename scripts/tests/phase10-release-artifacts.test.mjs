import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { BUILD_INPUTS, REQUIRED_IMAGES, createReleaseManifest, validateReleaseManifest } from '../phase10-release-manifest.mjs';
import { validateFunctionArchiveEntries, validateFunctionPublishDirectory } from '../phase10-function-package.mjs';

const sourceSha = 'a'.repeat(40);
const digest = (char) => `sha256:${char.repeat(64)}`;
const fragments = () => Object.entries(REQUIRED_IMAGES).map(([name, repository], index) => ({
  name, repository, sourceSha, image: `xyopsphase10.azurecr.io/${repository}`, digest: digest((index + 1).toString(16)),
}));

async function fixture(t, callback) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'phase10-release-test-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  return callback(root);
}

test('release manifest binds six expected images and Functions ZIP to one source/run', async (t) => fixture(t, async (root) => {
  const source = path.resolve('..');
  for (const item of BUILD_INPUTS) {
    const destination = path.join(root, 'repo', item);
    await mkdir(path.dirname(destination), { recursive: true });
    await writeFile(destination, `fixture:${item}`);
  }
  const zip = path.join(root, 'functions.zip');
  await writeFile(zip, 'synthetic package');
  const manifest = await createReleaseManifest({ repository: 'owner/repo', sourceSha, runId: '12345', runAttempt: '2', fragments: fragments(), functionsZip: zip, repoRoot: path.join(root, 'repo') });
  assert.equal(manifest.images.length, 6);
  assert.ok(manifest.images.every((image) => image.image.includes('@sha256:')));
  assert.equal(manifest.buildInputs.length, BUILD_INPUTS.length);
  await validateReleaseManifest(manifest, { repository: 'owner/repo', sourceSha, runId: '12345', runAttempt: '2', functionsZip: zip });
}));

test('release manifest rejects incomplete, duplicate, mixed-SHA, malformed and mutable images', async (t) => fixture(t, async (root) => {
  const zip = path.join(root, 'functions.zip');
  await writeFile(zip, 'zip');
  const invalid = [
    fragments().slice(0, 5),
    [...fragments().slice(0, 5), fragments()[0]],
    fragments().map((item, i) => i ? item : { ...item, sourceSha: 'b'.repeat(40) }),
    fragments().map((item, i) => i ? item : { ...item, digest: 'latest' }),
  ];
  for (const records of invalid) {
    await assert.rejects(createReleaseManifest({ repository: 'owner/repo', sourceSha, runId: '1', runAttempt: '1', fragments: records, functionsZip: zip, repoRoot: root }));
  }
}));

test('manifest validator rejects wrong producer, source, or tampered Functions package', async (t) => fixture(t, async (root) => {
  const repo = path.join(root, 'repo');
  for (const item of BUILD_INPUTS) {
    await mkdir(path.dirname(path.join(repo, item)), { recursive: true });
    await writeFile(path.join(repo, item), item);
  }
  const zip = path.join(root, 'functions.zip');
  await writeFile(zip, 'correct');
  const manifest = await createReleaseManifest({ repository: 'owner/repo', sourceSha, runId: '8', runAttempt: '1', fragments: fragments(), functionsZip: zip, repoRoot: repo });
  await assert.rejects(validateReleaseManifest(manifest, { repository: 'owner/repo', sourceSha: 'c'.repeat(40), runId: '8', runAttempt: '1', functionsZip: zip }), /source SHA mismatch/);
  await assert.rejects(validateReleaseManifest(manifest, { repository: 'owner/repo', sourceSha, runId: '9', runAttempt: '1', functionsZip: zip }), /producer run identity mismatch/);
  await writeFile(zip, 'tampered');
  await assert.rejects(validateReleaseManifest(manifest, { repository: 'owner/repo', sourceSha, runId: '8', runAttempt: '1', functionsZip: zip }), /checksum or size mismatch/);
}));

test('Functions package contract requires flat host metadata and excludes local settings', async (t) => fixture(t, async (root) => {
  await writeFile(path.join(root, 'host.json'), '{}');
  await writeFile(path.join(root, 'functions.metadata'), '[{"name":"Process"}]');
  assert.equal((await validateFunctionPublishDirectory(root)).functionCount, 1);
  assert.equal(validateFunctionArchiveEntries(['host.json', 'functions.metadata', 'app.deps.json', 'app.runtimeconfig.json']), true);
  assert.throws(() => validateFunctionArchiveEntries(['nested/host.json', 'functions.metadata', 'app.deps.json', 'app.runtimeconfig.json']), /host.json at its root/);
  assert.throws(() => validateFunctionArchiveEntries(['host.json', 'functions.metadata', 'local.settings.json', 'app.deps.json', 'app.runtimeconfig.json']), /must not include/);
  await writeFile(path.join(root, 'local.settings.json'), '{}');
  await assert.rejects(validateFunctionPublishDirectory(root), /must not contain/);
}));

console.log('Phase 10 immutable release artifact tests passed.');
