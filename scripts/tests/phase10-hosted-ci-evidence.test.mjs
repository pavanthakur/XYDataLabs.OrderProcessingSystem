import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { REQUIRED_CHECKS } from '../hosted-ci-evidence.mjs';
import { REQUIRED_TRX_FILES, verifyHostedCiEvidenceDirectory } from '../verify-phase10-hosted-ci-evidence.mjs';

async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'phase10-hosted-ci-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const sha = 'a'.repeat(40);
  const expected = { runId: '123', runAttempt: '2', sourceSha: sha, branch: 'dev' };
  const record = {
    schemaVersion: 1,
    workflowFile: '.github/workflows/ci.yml',
    runId: expected.runId,
    runAttempt: 2,
    event: 'push',
    ref: 'refs/heads/dev',
    eventSha: sha,
    checkoutSha: sha,
    profile: 'hosted-foundation',
    status: 'PASS',
    checks: Object.fromEntries([...REQUIRED_CHECKS.map((check) => [check, 'success']), ['evidenceFiles', 'success']]),
    artifacts: { trxDirectory: 'trx/', trxFiles: [...REQUIRED_TRX_FILES] },
  };
  await writeFile(path.join(directory, 'hosted-ci-evidence.json'), JSON.stringify(record));
  for (const relative of REQUIRED_TRX_FILES) {
    const file = path.join(directory, ...relative.split('/'));
    await mkdir(path.dirname(file), { recursive: true });
    await writeFile(file, '<TestRun />');
  }
  return { directory, expected, record };
}

test('accepts exact-SHA, successful hosted CI evidence with all expected TRX files', async (t) => {
  const { directory, expected } = await fixture(t);
  assert.equal((await verifyHostedCiEvidenceDirectory(directory, expected)).status, 'PASS');
});

test('rejects incomplete, stale, unbound, or incorrectly inventoried hosted evidence', async (t) => {
  const { directory, expected, record } = await fixture(t);
  for (const invalid of [
    { ...record, status: 'INCOMPLETE' },
    { ...record, eventSha: 'b'.repeat(40) },
    { ...record, ref: 'refs/heads/staging' },
    { ...record, checks: { ...record.checks, 'release-contract-tests': 'skipped' } },
    { ...record, artifacts: { trxFiles: ['trx/domain/domain.trx'] } },
  ]) {
    await writeFile(path.join(directory, 'hosted-ci-evidence.json'), JSON.stringify(invalid));
    await assert.rejects(verifyHostedCiEvidenceDirectory(directory, expected));
  }
});

test('rejects missing test result bytes even when the evidence packet claims PASS', async (t) => {
  const { directory, expected } = await fixture(t);
  await rm(path.join(directory, ...REQUIRED_TRX_FILES[0].split('/')));
  await assert.rejects(verifyHostedCiEvidenceDirectory(directory, expected), /missing a required test result/);
});
