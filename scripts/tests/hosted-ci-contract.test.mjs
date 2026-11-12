import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { REQUIRED_CHECKS, summarizeChecks } from '../hosted-ci-evidence.mjs';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, '../..');
const requireFromAutomation = createRequire(path.join(repositoryRoot, 'automation', 'package.json'));
const yaml = requireFromAutomation('js-yaml');
const workflowPath = path.join(repositoryRoot, '.github', 'workflows', 'ci.yml');

function validateWorkflow(workflow) {
  const errors = [];
  const triggers = workflow.on;
  if (!triggers?.push?.branches?.includes('dev') || !triggers.push.branches.includes('staging') || !triggers.push.branches.includes('main')) {
    errors.push('push must validate dev, staging, and main');
  }
  if (!Object.hasOwn(triggers ?? {}, 'pull_request') || !Object.hasOwn(triggers ?? {}, 'workflow_dispatch')) errors.push('PR and manual triggers are required');
  if (triggers.push?.paths || triggers.push?.['paths-ignore'] || triggers.pull_request?.paths || triggers.pull_request?.['paths-ignore']) {
    errors.push('hosted foundation validation must not use path filters');
  }
  if (workflow.permissions?.contents !== 'read' || Object.keys(workflow.permissions ?? {}).some((permission) => permission !== 'contents')) {
    errors.push('workflow must have contents: read only');
  }
  if (workflow.env?.DOTNET_VERSION !== '8.0.4xx') errors.push('hosted SDK must stay within the global.json 8.0.4xx feature band');

  const job = workflow.jobs?.['build-and-test'];
  if (!job || job['runs-on'] !== 'windows-latest' || Object.keys(workflow.jobs ?? {}).length !== 1) errors.push('only the expected Windows build-and-test job is permitted');
  if (job?.defaults?.run?.shell !== 'pwsh') errors.push('run steps must use PowerShell Core failure propagation');
  for (const [jobName, candidate] of Object.entries(workflow.jobs ?? {})) {
    if (candidate.environment || candidate.uses) errors.push(`job-level environment secrets or reusable workflow are forbidden: ${jobName}`);
    if (candidate.permissions && (candidate.permissions.contents !== 'read' || Object.keys(candidate.permissions).some((permission) => permission !== 'contents'))) {
      errors.push(`job must not request additional permissions: ${jobName}`);
    }
  }
  const steps = job?.steps ?? [];
  const ids = new Set(steps.map((step) => step.id).filter(Boolean));
  for (const id of REQUIRED_CHECKS) if (!ids.has(id)) errors.push(`required check step is missing: ${id}`);
  if (!steps.some((step) => step.uses?.startsWith('actions/upload-artifact@') && step['if'] === 'always()')) {
    errors.push('sanitized evidence upload must run after success or failure');
  }

  const forbiddenAction = /azure\/|docker\/build-push/i;
  const forbiddenCommand = /(?:^|\n)\s*(?:az(?:ure)?\s+|docker\s+push\b|gh\s+workflow\s+run\b|\.\/infra-deploy(?:\.yml)?\b|pwsh\b[^\n]*\binfra-deploy\.ps1\b)/im;
  for (const [jobName, candidate] of Object.entries(workflow.jobs ?? {})) {
    for (const step of candidate.steps ?? []) {
      if (step['continue-on-error'] === true || (typeof step['continue-on-error'] === 'string' && step['continue-on-error'] !== 'false')) {
        errors.push(`required validation cannot ignore errors: ${jobName}/${step.id ?? step.name ?? 'unnamed step'}`);
      }
      if (step.uses && forbiddenAction.test(step.uses)) errors.push(`deployment-capable action is forbidden: ${jobName}/${step.id ?? step.name ?? 'unnamed step'}`);
      if (typeof step.run === 'string' && forbiddenCommand.test(step.run)) errors.push(`deployment command is forbidden: ${jobName}/${step.id ?? step.name ?? 'unnamed step'}`);
    }
  }
  return errors;
}

test('actual CI workflow parses as YAML and satisfies the no-deployment contract', async () => {
  const workflow = yaml.load(await fs.readFile(workflowPath, 'utf8'), { schema: yaml.JSON_SCHEMA, maxAliasCount: 0 });
  assert.deepEqual(validateWorkflow(workflow), []);
});

test('contract rejects missing push coverage, branch gaps, or path filters', async () => {
  const base = yaml.load(await fs.readFile(workflowPath, 'utf8'), { schema: yaml.JSON_SCHEMA, maxAliasCount: 0 });
  for (const mutate of [
    (wf) => { delete wf.on.push; },
    (wf) => { wf.on.push = { branches: ['dev', 'main'] }; },
    (wf) => { wf.on.push.paths = ['XYDataLabs.OrderProcessingSystem.API/**']; },
    (wf) => { delete wf.on.workflow_dispatch; },
    (wf) => { delete wf.on.pull_request; },
  ]) {
    const fixture = structuredClone(base);
    mutate(fixture);
    assert.notEqual(validateWorkflow(fixture).length, 0);
  }
});

test('contract rejects write permissions, deploy actions, and missing required tests', async () => {
  const base = yaml.load(await fs.readFile(workflowPath, 'utf8'), { schema: yaml.JSON_SCHEMA, maxAliasCount: 0 });
  for (const mutate of [
    (wf) => { wf.permissions['id-token'] = 'write'; },
    (wf) => { wf.permissions.contents = 'write'; },
    (wf) => { wf.jobs['build-and-test'].steps.push({ uses: 'azure/login@v3' }); },
    (wf) => { wf.jobs['build-and-test'].steps.push({ run: 'az deployment group create' }); },
    (wf) => { wf.jobs['build-and-test'].steps.push({ run: 'az acr build --registry example' }); },
    (wf) => { wf.jobs['build-and-test'].steps = wf.jobs['build-and-test'].steps.filter((step) => step.id !== 'architecture-tests'); },
    (wf) => { wf.jobs['build-and-test'].steps.push({ run: 'gh workflow run deploy.yml' }); },
    (wf) => { wf.jobs['build-and-test'].environment = 'dev'; },
    (wf) => { wf.jobs['build-and-test'].permissions = { 'id-token': 'write' }; },
    (wf) => { wf.jobs['build-and-test'].defaults.run.shell = 'bash'; },
    (wf) => { wf.jobs['build-and-test'].steps.find((step) => step.id === 'domain-tests')['continue-on-error'] = true; },
    (wf) => { wf.jobs['build-and-test'].steps = wf.jobs['build-and-test'].steps.filter((step) => !step.uses?.startsWith('actions/upload-artifact@')); },
  ]) {
    const fixture = structuredClone(base);
    mutate(fixture);
    assert.notEqual(validateWorkflow(fixture).length, 0);
  }
});

test('PowerShell workflow shell preserves a native command nonzero exit', () => {
  const nativeExitCode = 23;
  const command = [
    "$ErrorActionPreference = 'Stop'",
    `& '${process.execPath.replaceAll("'", "''")}' -e 'process.exit(${nativeExitCode})'`,
    'if ((Test-Path -LiteralPath variable:\\LASTEXITCODE)) { exit $LASTEXITCODE }',
  ].join('; ');
  const result = spawnSync('pwsh', ['-NoProfile', '-Command', command], { encoding: 'utf8' });
  assert.equal(result.error, undefined, result.error?.message);
  assert.equal(result.status, nativeExitCode, result.stderr);
});

test('summary fails closed for required failures, skips, missing outcomes, and cancellation', () => {
  const allPassed = Object.fromEntries(REQUIRED_CHECKS.map((id) => [id, 'success']));
  assert.equal(summarizeChecks(allPassed).status, 'PASS');
  assert.equal(summarizeChecks({ ...allPassed, 'domain-tests': 'failure' }).status, 'FAIL');
  assert.equal(summarizeChecks({ ...allPassed, 'domain-tests': 'skipped' }).status, 'INCOMPLETE');
  assert.equal(summarizeChecks({ ...allPassed, 'domain-tests': undefined }).status, 'INCOMPLETE');
  assert.equal(summarizeChecks(allPassed, 'cancelled').status, 'INCOMPLETE');
});

test('evidence fails when the event SHA and checkout SHA do not match', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'hosted-ci-sha-fixture-'));
  const previousSummary = process.env.GITHUB_STEP_SUMMARY;
  const summaryPath = path.join(directory, 'summary.md');
  try {
    process.env.GITHUB_STEP_SUMMARY = summaryPath;
    for (const [name, file] of [['domain', 'domain'], ['application', 'application'], ['api', 'api'], ['gateway', 'gateway'], ['architecture', 'architecture']]) {
      const trxDirectory = path.join(directory, 'trx', name);
      await fs.mkdir(trxDirectory, { recursive: true });
      await fs.writeFile(path.join(trxDirectory, `${file}.trx`), '<TestRun />');
    }
    const record = await (await import('../hosted-ci-evidence.mjs')).writeEvidence({
      outputDirectory: directory,
      checkOutcomes: Object.fromEntries(REQUIRED_CHECKS.map((id) => [id, 'success'])),
      jobStatus: 'success', runId: 'fixture', event: 'push', ref: 'refs/heads/dev',
      eventSha: '1'.repeat(40), checkoutSha: '2'.repeat(40),
    });
    assert.equal(record.status, 'FAIL');
    assert.equal(record.checks.provenance, 'failure');
    assert.match(await fs.readFile(summaryPath, 'utf8'), /^## Hosted foundation CI: FAIL/m);
  } finally {
    if (previousSummary === undefined) delete process.env.GITHUB_STEP_SUMMARY;
    else process.env.GITHUB_STEP_SUMMARY = previousSummary;
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test('evidence is incomplete when any required TRX file is missing', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'hosted-ci-missing-trx-'));
  const previousSummary = process.env.GITHUB_STEP_SUMMARY;
  const summaryPath = path.join(directory, 'summary.md');
  try {
    process.env.GITHUB_STEP_SUMMARY = summaryPath;
    const record = await (await import('../hosted-ci-evidence.mjs')).writeEvidence({
      outputDirectory: directory,
      checkOutcomes: Object.fromEntries(REQUIRED_CHECKS.map((id) => [id, 'success'])),
      jobStatus: 'success', runId: 'fixture', event: 'push', ref: 'refs/heads/dev',
      eventSha: '1'.repeat(40), checkoutSha: '1'.repeat(40),
    });
    assert.equal(record.status, 'INCOMPLETE');
    assert.equal(record.checks.evidenceFiles, 'missing');
    assert.equal(record.artifacts.trxFiles.length, 0);
  } finally {
    if (previousSummary === undefined) delete process.env.GITHUB_STEP_SUMMARY;
    else process.env.GITHUB_STEP_SUMMARY = previousSummary;
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test('PR evidence cannot conflate event merge SHA and checked-out candidate SHA', async () => {
  const evidenceModule = await import('../hosted-ci-evidence.mjs');
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'hosted-ci-fixture-'));
  const previousSummary = process.env.GITHUB_STEP_SUMMARY;
  const summaryPath = path.join(directory, 'summary.md');
  try {
    process.env.GITHUB_STEP_SUMMARY = summaryPath;
    for (const [name, file] of [['domain', 'domain'], ['application', 'application'], ['api', 'api'], ['gateway', 'gateway'], ['architecture', 'architecture']]) {
      const trxDirectory = path.join(directory, 'trx', name);
      await fs.mkdir(trxDirectory, { recursive: true });
      await fs.writeFile(path.join(trxDirectory, `${file}.trx`), '<TestRun />');
    }
    const record = await evidenceModule.writeEvidence({
      outputDirectory: directory,
      checkOutcomes: Object.fromEntries(REQUIRED_CHECKS.map((id) => [id, 'success'])),
      jobStatus: 'success', runId: 'fixture', event: 'pull_request', ref: 'refs/pull/7/merge',
      eventSha: '1'.repeat(40), checkoutSha: '1'.repeat(40), pullRequestHeadSha: '2'.repeat(40),
    });
    assert.equal(record.eventSha, '1'.repeat(40));
    assert.equal(record.checkoutSha, '1'.repeat(40));
    assert.equal(record.pullRequestHeadSha, '2'.repeat(40));
    assert.match(await fs.readFile(summaryPath, 'utf8'), /^## Hosted foundation CI: PASS/m);
    const saved = JSON.parse(await fs.readFile(path.join(directory, 'hosted-ci-evidence.json'), 'utf8'));
    assert.equal(saved.status, 'PASS');
    assert.equal(saved.artifacts.trxFiles.length, 5);
  } finally {
    if (previousSummary === undefined) delete process.env.GITHUB_STEP_SUMMARY;
    else process.env.GITHUB_STEP_SUMMARY = previousSummary;
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test('CLI returns nonzero for incomplete evidence and zero only for a fully bound passing packet', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'hosted-ci-cli-'));
  const evidenceScript = path.join(repositoryRoot, 'scripts', 'hosted-ci-evidence.mjs');
  const sha = 'a'.repeat(40);
  const completeOutcomes = Object.fromEntries(REQUIRED_CHECKS.map((id) => [id, 'success']));
  const baseEnvironment = {
    ...process.env,
    GITHUB_STEP_SUMMARY: path.join(directory, 'summary.md'),
    GITHUB_EVENT_NAME: 'push',
    GITHUB_REF: 'refs/heads/dev',
    GITHUB_SHA: sha,
    CI_CHECKOUT_SHA: sha,
    GITHUB_RUN_ID: 'test-run',
    GITHUB_RUN_ATTEMPT: '1',
    CI_JOB_STATUS: 'success',
    CI_EVIDENCE_DIRECTORY: directory,
  };
  try {
    const incomplete = spawnSync(process.execPath, [evidenceScript], {
      cwd: repositoryRoot,
      encoding: 'utf8',
      env: { ...baseEnvironment, CI_CHECK_OUTCOMES_JSON: '{}' },
    });
    assert.equal(incomplete.status, 1);
    assert.equal(JSON.parse(await fs.readFile(path.join(directory, 'hosted-ci-evidence.json'), 'utf8')).status, 'INCOMPLETE');

    for (const [name, file] of [['domain', 'domain'], ['application', 'application'], ['api', 'api'], ['gateway', 'gateway'], ['architecture', 'architecture']]) {
      const trxDirectory = path.join(directory, 'trx', name);
      await fs.mkdir(trxDirectory, { recursive: true });
      await fs.writeFile(path.join(trxDirectory, `${file}.trx`), '<TestRun />');
    }
    const complete = spawnSync(process.execPath, [evidenceScript], {
      cwd: repositoryRoot,
      encoding: 'utf8',
      env: { ...baseEnvironment, CI_CHECK_OUTCOMES_JSON: JSON.stringify(completeOutcomes) },
    });
    assert.equal(complete.status, 0, complete.stderr);
    assert.equal(JSON.parse(await fs.readFile(path.join(directory, 'hosted-ci-evidence.json'), 'utf8')).status, 'PASS');
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});
