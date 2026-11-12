import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const REQUIRED_CHECKS = [
  'checkout',
  'provenance',
  'generated-artifacts',
  'docker-safety',
  'environment-contract',
  'setup-dotnet',
  'setup-node',
  'frontend-deps',
  'automation-deps',
  'ci-contract-tests',
  'release-contract-tests',
  'trx-sanitizer-tests',
  'callback-tests',
  'frontend-typecheck',
  'frontend-tests',
  'identity-tests',
  'frontend-build',
  'dotnet-restore',
  'dotnet-build',
  'domain-tests',
  'application-tests',
  'api-tests',
  'gateway-tests',
  'architecture-tests',
  'sanitize-trx',
];

const VALID_OUTCOMES = new Set(['success', 'failure', 'cancelled', 'skipped']);
const EXPECTED_TRX_FILES = [
  'trx/domain/domain.trx',
  'trx/application/application.trx',
  'trx/api/api.trx',
  'trx/gateway/gateway.trx',
  'trx/architecture/architecture.trx',
];

export function summarizeChecks(checkOutcomes, jobStatus = 'success') {
  const checks = Object.fromEntries(REQUIRED_CHECKS.map((id) => {
    const raw = checkOutcomes?.[id];
    return [id, VALID_OUTCOMES.has(raw) ? raw : 'missing'];
  }));

  let status = 'PASS';
  if (jobStatus === 'failure' || Object.values(checks).includes('failure')) {
    status = 'FAIL';
  } else if (jobStatus !== 'success' || Object.values(checks).some((outcome) => outcome !== 'success')) {
    status = 'INCOMPLETE';
  }

  return { status, checks };
}

function revisionBindingIssue(record) {
  if (!/^[0-9a-f]{40}$/i.test(record.eventSha) || !/^[0-9a-f]{40}$/i.test(record.checkoutSha)) return 'missing';
  return record.eventSha.toLowerCase() === record.checkoutSha.toLowerCase() ? null : 'mismatch';
}

function markdownInline(value) {
  return String(value).replaceAll('`', '\\`').replace(/[\r\n|]/g, ' ');
}

export async function writeEvidence({ outputDirectory, ...context }) {
  let { status, checks } = summarizeChecks(context.checkOutcomes, context.jobStatus);
  await fs.mkdir(outputDirectory, { recursive: true });
  const trxFiles = [];
  for (const relativePath of EXPECTED_TRX_FILES) {
    try {
      await fs.access(path.join(outputDirectory, relativePath));
      trxFiles.push(relativePath);
    } catch {
      // Missing required TRX remains explicit and prevents a complete PASS.
    }
  }
  if (trxFiles.length !== EXPECTED_TRX_FILES.length) {
    checks.evidenceFiles = 'missing';
    if (status !== 'FAIL') status = 'INCOMPLETE';
  } else {
    checks.evidenceFiles = 'success';
  }

  const record = {
    schemaVersion: 1,
    workflowFile: '.github/workflows/ci.yml',
    runId: context.runId || 'UNKNOWN',
    runAttempt: Number(context.runAttempt) || 1,
    event: context.event || 'UNKNOWN',
    ref: context.ref || 'UNKNOWN',
    eventSha: context.eventSha || 'UNKNOWN',
    checkoutSha: context.checkoutSha || 'UNKNOWN',
    pullRequestHeadSha: context.pullRequestHeadSha || null,
    profile: 'hosted-foundation',
    status,
    checks,
    artifacts: {
      trxDirectory: 'trx/',
      trxFiles,
    },
  };
  const bindingIssue = revisionBindingIssue(record);
  if (bindingIssue) {
    if (bindingIssue === 'mismatch') record.status = 'FAIL';
    else if (record.status !== 'FAIL') record.status = 'INCOMPLETE';
    record.checks.provenance = bindingIssue === 'mismatch' ? 'failure' : 'missing';
  }

  await fs.writeFile(path.join(outputDirectory, 'hosted-ci-evidence.json'), `${JSON.stringify(record, null, 2)}\n`, 'utf8');

  const lines = [
    `## Hosted foundation CI: ${record.status}`,
    '',
    `- Event: \`${markdownInline(record.event)}\` on \`${markdownInline(record.ref)}\``,
    `- Event SHA: \`${markdownInline(record.eventSha)}\``,
    `- Checked-out SHA: \`${markdownInline(record.checkoutSha)}\``,
    `- PR head SHA: \`${markdownInline(record.pullRequestHeadSha ?? 'N/A')}\``,
    `- Run: \`${markdownInline(record.runId)}\` attempt \`${record.runAttempt}\``,
    '- Scope: build and contract validation only; no Docker daemon, database, provider transaction, image publication, or Azure deployment.',
    '- This result is not Docker E2E, L5-R, or Azure acceptance.',
    '- The workflow run must also conclude successfully and the evidence artifact must be present; an upload failure blocks evidence-dependent acceptance.',
    '- Event SHA and checked-out SHA must match; for PRs, the separate head SHA is reported but not substituted for the tested merge candidate.',
    '',
    '| Required check | Outcome |',
    '|---|---|',
    ...Object.entries(record.checks).map(([id, outcome]) => `| \`${id}\` | ${outcome} |`),
    '',
    'See the workflow run for detailed step logs. The uploaded artifact contains only this sanitized evidence record and named TRX files.',
    '',
  ];
  if (process.env.GITHUB_STEP_SUMMARY) {
    await fs.appendFile(process.env.GITHUB_STEP_SUMMARY, lines.join('\n'), 'utf8');
  } else {
    process.stdout.write(lines.join('\n'));
  }

  return record;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const outcomes = JSON.parse(process.env.CI_CHECK_OUTCOMES_JSON || '{}');
  const record = await writeEvidence({
    outputDirectory: process.env.CI_EVIDENCE_DIRECTORY || 'TestResults/HostedCI/local',
    checkOutcomes: outcomes,
    jobStatus: process.env.CI_JOB_STATUS || 'success',
    runId: process.env.GITHUB_RUN_ID,
    runAttempt: process.env.GITHUB_RUN_ATTEMPT,
    event: process.env.GITHUB_EVENT_NAME,
    ref: process.env.GITHUB_REF,
    eventSha: process.env.GITHUB_SHA,
    checkoutSha: process.env.CI_CHECKOUT_SHA,
    pullRequestHeadSha: process.env.CI_PR_HEAD_SHA,
  });
  if (record.status !== 'PASS') process.exitCode = 1;
}
