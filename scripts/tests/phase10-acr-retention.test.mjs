import test from 'node:test';
import assert from 'node:assert/strict';
import { planAcrRetention, REQUIRED_REPOSITORIES } from '../phase10-acr-retention.mjs';

const digest = (n) => `sha256:${String(n).padStart(64, '0')}`;
const fixture = () => {
  const manifests = [];
  const rollbackDigests = [];
  REQUIRED_REPOSITORIES.forEach((repository, service) => {
    for (let index = 0; index < 12; index++) {
      manifests.push({ repository, digest: digest(service * 20 + index + 1), tags: index === 0 ? ['latest', 'release'] : [`build-${index}`], lastUpdateTime: new Date(Date.UTC(2025, 0, 1 + index)).toISOString() });
    }
    rollbackDigests.push({ repository, digest: digest(service * 20 + 1), verified: true, sourceSha: 'a'.repeat(40), evidenceRef: `release-run-${service + 1}` });
  });
  return {
    manifests,
    inventoryComplete: { manifests: true, activeRevisions: true },
    activeRevisionEnvironments: ['dev', 'staging', 'prod'],
    activeDigests: [
      { environment: 'dev', repository: REQUIRED_REPOSITORIES[0], digest: digest(12) },
      { environment: 'staging', repository: REQUIRED_REPOSITORIES[1], digest: digest(32) },
      { environment: 'prod', repository: REQUIRED_REPOSITORIES[2], digest: digest(52) },
    ],
    rollbackDigests,
    now: new Date('2026-01-01T00:00:00Z'),
  };
};

test('retention inventory covers Payments and protects active and one verified rollback digest per repository', () => {
  const report = planAcrRetention(fixture());
  assert.equal(report.status, 'PREVIEW_ONLY');
  assert.equal(report.deletionEnabled, false);
  assert.ok(report.decisions.some((item) => item.repository === 'orderprocessing-payments'));
  assert.equal(report.decisions.find((item) => item.digest === digest(12)).action, 'keep');
  assert.equal(report.decisions.find((item) => item.digest === digest(1)).action, 'keep');
  assert.equal(report.decisions.find((item) => item.digest === digest(32)).action, 'keep');
  assert.equal(report.decisions.find((item) => item.digest === digest(52)).action, 'keep');
});

test('multiple tags remain one digest decision and no protected manifest is a candidate', () => {
  const report = planAcrRetention(fixture());
  assert.equal(report.decisions.filter((item) => item.digest === digest(1)).length, 1);
  assert.ok(report.decisions.filter((item) => item.action === 'candidate').every((item) => item.digest !== digest(1) && item.digest !== digest(12)));
});

test('untagged manifests remain in the digest inventory without inventing a tag', () => {
  const input = fixture();
  const untagged = input.manifests.find((item) => item.repository === REQUIRED_REPOSITORIES[3]);
  untagged.tags = null;
  const report = planAcrRetention(input);
  assert.deepEqual(report.decisions.find((item) => item.digest === untagged.digest).tags, []);
});

test('incomplete, duplicate, malformed and unprotected rollback evidence fails closed', () => {
  const base = fixture();
  assert.throws(() => planAcrRetention({ ...base, inventoryComplete: { manifests: true, activeRevisions: false } }), /Complete manifest and active-revision inventories/);
  assert.throws(() => planAcrRetention({ ...base, activeRevisionEnvironments: ['dev', 'staging'] }), /Complete manifest and active-revision inventories/);
  assert.throws(() => planAcrRetention({ ...base, activeRevisionEnvironments: ['dev', 'staging', 'prod', 'prod'] }), /Complete manifest and active-revision inventories/);
  assert.throws(() => planAcrRetention({ ...base, manifests: base.manifests.filter((item) => item.repository !== 'orderprocessing-payments') }), /incomplete/);
  assert.throws(() => planAcrRetention({ ...base, manifests: [...base.manifests, base.manifests[0]] }), /duplicate/);
  assert.throws(() => planAcrRetention({ ...base, activeDigests: [{ digest: 'not-a-digest' }] }), /invalid/);
  assert.throws(() => planAcrRetention({ ...base, rollbackDigests: [] }), /verified rollback/);
  assert.throws(() => planAcrRetention({ ...base, activeDigests: [...base.activeDigests, { ...base.activeDigests[0], digest: digest(1) }] }), /must differ/);
  assert.throws(() => planAcrRetention({ ...base, rollbackDigests: [...base.rollbackDigests, { ...base.rollbackDigests[0], digest: 'invalid' }] }), /verified rollback/);
  assert.throws(() => planAcrRetention({ ...base, rollbackDigests: base.rollbackDigests.map((entry, index) => index === 0 ? { ...entry, sourceSha: 'not-a-commit' } : entry) }), /Rollback evidence is invalid/);
  assert.throws(() => planAcrRetention({ ...base, rollbackDigests: base.rollbackDigests.map((entry) => ({ ...entry, digest: digest(999) })) }), /absent/);
  assert.throws(() => planAcrRetention({ ...base, rollbackDigests: base.rollbackDigests.map((entry) => ({ ...entry, verified: false })) }), /Rollback evidence is invalid/);
});

test('retention selection never opts into deletion and preserves latest and recent history', () => {
  const report = planAcrRetention(fixture());
  assert.ok(report.decisions.filter((item) => item.action === 'candidate').every((item) => item.reasons.length === 0));
  assert.ok(report.decisions.filter((item) => item.repository === REQUIRED_REPOSITORIES[0]).slice(0, 10).every((item) => item.action === 'keep'));
});

test('a newly published active digest remains protected in a read-only preview', () => {
  const input = fixture();
  const published = { repository: REQUIRED_REPOSITORIES[0], digest: digest(13), tags: ['release-new'], lastUpdateTime: '2026-01-01T00:00:00Z' };
  input.manifests.push(published);
  input.activeDigests.push({ environment: 'dev', repository: published.repository, digest: published.digest });
  const report = planAcrRetention(input);
  assert.equal(report.decisions.find((item) => item.digest === published.digest).action, 'keep');
  assert.equal(report.deletionEnabled, false);
  assert.equal(report.status, 'PREVIEW_ONLY');
});
