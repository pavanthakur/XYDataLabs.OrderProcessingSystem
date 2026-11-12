import test from 'node:test';
import assert from 'node:assert/strict';
import { allowedReleaseBranches, applicableHostedWorkflows, expectedBranch, selectHostedCiRun, selectPromotionHostedCiRuns, validateHostedCiArtifact, validateHostedCiRuns, validatePromotionAncestry, validateReleaseRun } from '../phase10-release-run.mjs';

const sha = 'a'.repeat(40);
const repository = 'pavanthakur/XYDataLabs.OrderProcessingSystem';
const run = { id: 123, status: 'completed', conclusion: 'success', path: '.github/workflows/build-phase10-images.yml', head_repository: { full_name: repository }, repository: { full_name: repository }, head_sha: sha, head_branch: 'dev' };
const artifact = { id: 456, name: `phase10-release-${sha}`, expired: false, digest: `sha256:${'b'.repeat(64)}`, workflow_run: { id: 123 } };

test('maps deployment environments to their release source branch', () => {
  assert.equal(expectedBranch('dev'), 'dev');
  assert.equal(expectedBranch('staging'), 'staging');
  assert.equal(expectedBranch('prod'), 'main');
  assert.throws(() => expectedBranch('test'), /Unsupported/);
});

test('allows immutable source artifacts to move only along the configured environment promotion chain', () => {
  assert.deepEqual(allowedReleaseBranches('dev'), ['dev']);
  assert.deepEqual(allowedReleaseBranches('staging'), ['dev', 'staging']);
  assert.deepEqual(allowedReleaseBranches('prod'), ['dev', 'staging', 'main']);
  assert.equal(validateReleaseRun(run, artifact, { repository, sourceSha: sha, runId: '123', artifactName: artifact.name, environment: 'staging' }), true);
  assert.equal(validateReleaseRun(run, artifact, { repository, sourceSha: sha, runId: '123', artifactName: artifact.name, environment: 'prod' }), true);
  assert.throws(() => validateReleaseRun({ ...run, head_branch: 'feature/payments' }, artifact, { repository, sourceSha: sha, runId: '123', artifactName: artifact.name, environment: 'staging' }), /not permitted/);
});

test('promotion requires the immutable release source to be an ancestor of the deployment workflow revision', () => {
  const deploymentSha = 'c'.repeat(40);
  assert.equal(validatePromotionAncestry({ status: 'ahead', base_commit: { sha }, merge_base_commit: { sha } }, { sourceSha: sha, deploymentWorkflowSha: deploymentSha }), true);
  assert.equal(validatePromotionAncestry({ status: 'identical' }, { sourceSha: sha, deploymentWorkflowSha: sha }), true);
  assert.throws(() => validatePromotionAncestry({ status: 'diverged', base_commit: { sha }, merge_base_commit: { sha: 'b'.repeat(40) } }, { sourceSha: sha, deploymentWorkflowSha: deploymentSha }), /not an ancestor/);
  assert.throws(() => validatePromotionAncestry({ status: 'ahead', base_commit: { sha: 'b'.repeat(40) }, merge_base_commit: { sha: 'b'.repeat(40) } }, { sourceSha: sha, deploymentWorkflowSha: deploymentSha }), /not an ancestor/);
  assert.throws(() => validatePromotionAncestry({ status: 'ahead' }, { sourceSha: 'short', deploymentWorkflowSha: deploymentSha }), /full commit SHAs/);
});

test('accepts only a successful release and owned artifact from the matching source', () => {
  assert.equal(validateReleaseRun(run, artifact, { repository, sourceSha: sha, runId: '123', artifactName: artifact.name, environment: 'dev' }), true);
  for (const [badRun, badArtifact, options] of [
    [{ ...run, conclusion: 'failure' }, artifact, {}],
    [{ ...run, head_sha: 'b'.repeat(40) }, artifact, {}],
    [{ ...run, path: 'other.yml' }, artifact, {}],
    [run, { ...artifact, workflow_run: { id: 999 } }, {}],
    [run, { ...artifact, expired: true }, {}],
    [{ ...run, head_branch: 'staging' }, artifact, { environment: 'dev' }],
  ]) {
    assert.throws(() => validateReleaseRun(badRun, badArtifact, { repository, sourceSha: sha, runId: '123', artifactName: artifact.name, environment: 'dev', ...options }));
  }
});

test('accepts workflow-run path metadata with its ref suffix while pinning the workflow file', () => {
  assert.equal(validateReleaseRun({ ...run, path: '.github/workflows/build-phase10-images.yml@refs/heads/dev' }, artifact, { repository, sourceSha: sha, runId: '123', artifactName: artifact.name, environment: 'dev' }), true);
  assert.throws(() => validateReleaseRun({ ...run, path: '.github/workflows/other.yml@refs/heads/dev' }, artifact, { repository, sourceSha: sha, runId: '123', artifactName: artifact.name, environment: 'dev' }), /approved image\/package workflow/);
});

test('latest hosted CI run for the exact candidate SHA must succeed', () => {
  assert.equal(validateHostedCiRuns([{ head_sha: sha, status: 'completed', conclusion: 'success' }], { sourceSha: sha }), true);
  assert.throws(() => validateHostedCiRuns([], { sourceSha: sha }), /not completed successfully/);
  assert.throws(() => validateHostedCiRuns([{ head_sha: sha, status: 'completed', conclusion: 'failure' }], { sourceSha: sha }), /not completed successfully/);
  assert.throws(() => validateHostedCiRuns([
    { head_sha: sha, status: 'completed', conclusion: 'success', created_at: '2026-11-11T10:00:00Z' },
    { head_sha: sha, status: 'completed', conclusion: 'failure', created_at: '2026-11-11T10:01:00Z' },
  ], { sourceSha: sha }), /not completed successfully/);
  assert.throws(() => validateHostedCiRuns([{ head_sha: 'b'.repeat(40), status: 'completed', conclusion: 'success' }], { sourceSha: sha }), /not completed successfully/);
  assert.equal(validateHostedCiRuns([
    { head_sha: sha, status: 'completed', conclusion: 'failure', created_at: '2026-11-11T10:00:00Z' },
    { head_sha: sha, status: 'completed', conclusion: 'success', created_at: '2026-11-11T10:01:00Z' },
  ], { sourceSha: sha }), true);
  assert.throws(() => validateHostedCiRuns([
    { head_sha: sha, status: 'completed', conclusion: 'success', created_at: '2026-11-11T10:00:00Z' },
    { head_sha: sha, status: 'in_progress', conclusion: null, created_at: '2026-11-11T10:01:00Z' },
  ], { sourceSha: sha }), /not completed successfully/);
});

test('selects the exact target-branch hosted run and requires its named evidence artifact', () => {
  const matching = { id: 55, run_attempt: 2, head_sha: sha, head_branch: 'dev', status: 'completed', conclusion: 'success', created_at: '2026-11-12T10:00:00Z' };
  assert.equal(selectHostedCiRun([matching, { ...matching, head_branch: 'staging', created_at: '2026-11-12T10:01:00Z' }], { sourceSha: sha, branch: 'dev' }).id, 55);
  assert.deepEqual(validateHostedCiArtifact([{ id: 66, name: 'hosted-ci-55-2', expired: false, workflow_run: { id: 55 } }], matching), { name: 'hosted-ci-55-2', runId: '55', runAttempt: '2' });
  assert.throws(() => validateHostedCiArtifact([], matching), /missing its unexpired/);
});

test('promotion requires successful exact-SHA CI on both artifact source and deployment workflow revisions', () => {
  const deploymentSha = 'c'.repeat(40);
  const sourceRun = { id: 55, head_sha: sha, head_branch: 'dev', status: 'completed', conclusion: 'success' };
  const deploymentRun = { id: 56, head_sha: deploymentSha, head_branch: 'staging', status: 'completed', conclusion: 'success' };
  assert.deepEqual(selectPromotionHostedCiRuns([sourceRun], [deploymentRun], {
    sourceSha: sha, sourceBranch: 'dev', deploymentWorkflowSha: deploymentSha, deploymentBranch: 'staging',
  }), { sourceRun, deploymentRun });
  assert.throws(() => selectPromotionHostedCiRuns([], [deploymentRun], {
    sourceSha: sha, sourceBranch: 'dev', deploymentWorkflowSha: deploymentSha, deploymentBranch: 'staging',
  }), /not completed successfully/);
  assert.throws(() => selectPromotionHostedCiRuns([sourceRun], [{ ...deploymentRun, conclusion: 'failure' }], {
    sourceSha: sha, sourceBranch: 'dev', deploymentWorkflowSha: deploymentSha, deploymentBranch: 'staging',
  }), /not completed successfully/);
  assert.throws(() => selectPromotionHostedCiRuns([sourceRun], [deploymentRun], {
    sourceSha: sha, sourceBranch: 'dev', deploymentWorkflowSha: deploymentSha, deploymentBranch: 'main',
  }), /not completed successfully/);
});

test('hosted workflow applicability requires unconditional and affected specialist checks', () => {
  assert.deepEqual(applicableHostedWorkflows(['docs/internal/phase10.md', '.github/workflows/ci.yml', 'scripts/release-check.mjs']), [
    'ci.yml', 'drift-check.yml', 'validate-doc-links.yml', 'validate-prompts.yml',
  ]);
  assert.deepEqual(applicableHostedWorkflows(['Resources/Azure-Deployment/example.ps1']), [
    'ci.yml', 'drift-check.yml',
  ]);
  assert.deepEqual(applicableHostedWorkflows(['Resources/Azure-Deployment/example.ps1'], { adrValidationEnabled: true }), [
    'ci.yml', 'drift-check.yml', 'validate-adrs.yml',
  ]);
  assert.deepEqual(applicableHostedWorkflows(['docs/architecture/decisions/ADR-999-example.md']), [
    'ci.yml', 'drift-check.yml', 'validate-doc-links.yml',
  ]);
  assert.ok(applicableHostedWorkflows(['docs/architecture/decisions/ADR-999-example.md'], { adrValidationEnabled: true }).includes('validate-adrs.yml'));
  assert.ok(applicableHostedWorkflows(['memories/repo/active-work.md']).includes('validate-ai-customization.yml'));
});
