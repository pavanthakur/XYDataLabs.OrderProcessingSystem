import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { REQUIRED_CHECKS } from './hosted-ci-evidence.mjs';

export const REQUIRED_TRX_FILES = Object.freeze([
  'trx/domain/domain.trx',
  'trx/application/application.trx',
  'trx/api/api.trx',
  'trx/gateway/gateway.trx',
  'trx/architecture/architecture.trx',
]);

export async function verifyHostedCiEvidenceDirectory(directory, expected) {
  const record = JSON.parse(await readFile(path.join(directory, 'hosted-ci-evidence.json'), 'utf8'));
  if (record.schemaVersion !== 1 || record.workflowFile !== '.github/workflows/ci.yml' || record.profile !== 'hosted-foundation') {
    throw new Error('Hosted CI evidence has an unsupported schema, workflow, or profile.');
  }
  if (record.status !== 'PASS' || String(record.runId) !== String(expected.runId) || Number(record.runAttempt) !== Number(expected.runAttempt)) {
    throw new Error('Hosted CI evidence is not a PASS for the selected workflow run and attempt.');
  }
  if (record.eventSha !== expected.sourceSha || record.checkoutSha !== expected.sourceSha || record.ref !== `refs/heads/${expected.branch}`) {
    throw new Error('Hosted CI evidence is not bound to the selected candidate SHA and source branch.');
  }
  if (!record.checks || REQUIRED_CHECKS.some((check) => record.checks[check] !== 'success') || record.checks.evidenceFiles !== 'success') {
    throw new Error('Hosted CI evidence contains missing or unsuccessful required checks.');
  }
  const listed = record.artifacts?.trxFiles;
  if (!Array.isArray(listed) || listed.length !== REQUIRED_TRX_FILES.length || REQUIRED_TRX_FILES.some((file, index) => listed[index] !== file)) {
    throw new Error('Hosted CI evidence does not declare the complete expected TRX inventory.');
  }
  for (const relative of REQUIRED_TRX_FILES) {
    const file = path.join(directory, ...relative.split('/'));
    let details;
    try {
      details = await stat(file);
    } catch {
      throw new Error(`Hosted CI evidence is missing a required test result: ${relative}.`);
    }
    if (!details.isFile() || details.size === 0) throw new Error(`Hosted CI evidence is missing a non-empty required test result: ${relative}.`);
  }
  return { status: 'PASS', runId: String(record.runId), runAttempt: Number(record.runAttempt), sourceSha: record.eventSha, testResultFiles: REQUIRED_TRX_FILES.length };
}

async function main() {
  const result = await verifyHostedCiEvidenceDirectory(process.env.EVIDENCE_DIRECTORY ?? 'hosted-ci-evidence', {
    runId: process.env.HOSTED_CI_RUN_ID,
    runAttempt: process.env.HOSTED_CI_RUN_ATTEMPT,
    sourceSha: process.env.CANDIDATE_SHA,
    branch: process.env.SOURCE_BRANCH,
  });
  console.log(`Verified hosted CI PASS for ${result.sourceSha}, run ${result.runId} attempt ${result.runAttempt}, with ${result.testResultFiles} required TRX results.`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => { console.error(`Hosted CI evidence rejected: ${error.message}`); process.exitCode = 1; });
}
