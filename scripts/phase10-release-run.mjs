import path from 'node:path';
import { fileURLToPath } from 'node:url';

const API_VERSION = '2022-11-28';

export function expectedBranch(environment) {
  const branch = { dev: 'dev', staging: 'staging', prod: 'main' }[environment];
  if (!branch) throw new Error('Unsupported deployment environment.');
  return branch;
}

export function validateReleaseRun(run, artifact, { repository, sourceSha, runId, artifactName, environment }) {
  if (run?.id !== Number(runId) || run?.status !== 'completed' || run?.conclusion !== 'success') throw new Error('Release producer run is not completed successfully.');
  if (String(run?.path ?? '').split('@')[0] !== '.github/workflows/build-phase10-images.yml') throw new Error('Release producer is not the approved image/package workflow.');
  if (run?.head_repository?.full_name !== repository || run?.repository?.full_name !== repository) throw new Error('Release producer repository mismatch.');
  if (run?.head_sha !== sourceSha || !/^[0-9a-f]{40}$/i.test(sourceSha ?? '')) throw new Error('Release producer source SHA mismatch.');
  if (run?.head_branch !== expectedBranch(environment)) throw new Error('Release producer branch does not match target environment policy.');
  if (artifact?.name !== artifactName || artifact?.expired !== false || !Number.isSafeInteger(artifact?.id) || !/^sha256:[0-9a-f]{64}$/i.test(artifact?.digest ?? '')) throw new Error('Named release artifact is missing, expired, or has no valid artifact digest.');
  if (artifact?.workflow_run?.id !== Number(runId)) throw new Error('Release artifact is not owned by the selected producer run.');
  return true;
}

export function validateHostedCiRuns(runs, { sourceSha }) {
  return Boolean(selectHostedCiRun(runs, { sourceSha }));
}

export function selectHostedCiRun(runs, { sourceSha, branch }) {
  if (!/^[0-9a-f]{40}$/i.test(sourceSha ?? '')) throw new Error('Candidate source SHA must be full length.');
  const matching = (runs ?? []).filter((run) => run?.head_sha === sourceSha && (!branch || run?.head_branch === branch));
  matching.sort((left, right) => String(right.created_at ?? '').localeCompare(String(left.created_at ?? '')));
  if (matching.length === 0 || matching[0].status !== 'completed' || matching[0].conclusion !== 'success') throw new Error('The latest hosted workflow run for the exact candidate SHA and required branch is not completed successfully.');
  return matching[0];
}

export function validateHostedCiArtifact(artifacts, run) {
  const expectedName = `hosted-ci-${run.id}-${run.run_attempt}`;
  const artifact = (artifacts ?? []).find((candidate) => candidate.name === expectedName);
  if (!artifact || artifact.expired !== false || artifact.workflow_run?.id !== run.id) {
    throw new Error('The successful hosted CI run is missing its unexpired, run-owned evidence artifact.');
  }
  return { name: expectedName, runId: String(run.id), runAttempt: String(run.run_attempt) };
}

async function getJson(url, token) {
  const response = await fetch(url, {
    headers: { authorization: `Bearer ${token}`, accept: 'application/vnd.github+json', 'x-github-api-version': API_VERSION },
  });
  if (!response.ok) throw new Error(`GitHub release evidence API returned HTTP ${response.status}.`);
  return response.json();
}

export function applicableHostedWorkflows(paths) {
  const changed = paths ?? [];
  const any = (regex) => changed.some((file) => regex.test(file));
  const required = new Set(['ci.yml', 'drift-check.yml']);
  if (any(/^(\.github\/workflows\/|scripts\/|Resources\/Azure-Deployment\/|infra\/|docs\/architecture\/decisions\/|XYDataLabs\.OrderProcessingSystem\.sln)/i)) required.add('validate-adrs.yml');
  if (any(/^(docs\/|scripts\/validate-doc-links\.js$|\.github\/workflows\/validate-doc-links\.yml$)/i)) required.add('validate-doc-links.yml');
  if (any(/^(AGENTS\.md$|memories\/repo\/|scripts\/tests\/test-ai-customization(?:-exit)?\.ps1$|\.github\/(copilot-instructions\.md|completion-check-rubric\.md|instructions\/|prompts\/|agents\/|skills\/|workflows\/validate-ai-customization\.yml|workflows\/README\.md)|docs\/(AI-OPERATING-MODEL\.md|DEVELOPER-OPERATING-MODEL\.md|README\.md|internal\/DEFERRED-WORK-LOG\.md|internal\/README\.md)|scripts\/(validate-ai-customization\.ps1|README\.md))/i)) required.add('validate-ai-customization.yml');
  if (any(/^((\.github\/prompts\/)|ai-runtime\/|scripts\/)/i)) required.add('validate-prompts.yml');
  return [...required].sort();
}

async function getCommitChangedPaths(repository, sourceSha, token) {
  const root = `https://api.github.com/repos/${repository}`;
  const commit = await getJson(`${root}/commits/${sourceSha}`, token);
  const baseSha = commit.parents?.[0]?.sha;
  if (!baseSha) return [];
  const paths = [];
  for (let page = 1; page <= 10; page += 1) {
    const comparison = await getJson(`${root}/compare/${baseSha}...${sourceSha}?per_page=100&page=${page}`, token);
    for (const file of comparison.files ?? []) paths.push(file.filename);
    if ((comparison.files ?? []).length < 100) return paths;
  }
  throw new Error('Candidate change list exceeded the supported review boundary.');
}

export async function verifyReleaseEvidence({ repository, sourceSha, runId, artifactName, environment, token }) {
  if (!token) throw new Error('GitHub read token is required to verify release provenance.');
  const root = `https://api.github.com/repos/${repository}`;
  const run = await getJson(`${root}/actions/runs/${runId}`, token);
  const artifactsResponse = await getJson(`${root}/actions/runs/${runId}/artifacts?per_page=100`, token);
  const artifact = artifactsResponse.artifacts?.find((item) => item.name === artifactName);
  validateReleaseRun(run, artifact, { repository, sourceSha, runId, artifactName, environment });

  const workflowIndex = await getJson(`${root}/actions/workflows?per_page=100`, token);
  const files = await getCommitChangedPaths(repository, sourceSha, token);
  const requiredPaths = applicableHostedWorkflows(files);
  let hostedCiEvidence;
  for (const workflowPath of requiredPaths) {
    const workflow = workflowIndex.workflows?.find((candidate) => candidate.path === `.github/workflows/${workflowPath}`);
    if (!workflow) throw new Error(`Required hosted workflow is missing from repository inventory: ${workflowPath}.`);
    const workflowRuns = await getJson(`${root}/actions/workflows/${workflow.id}/runs?head_sha=${sourceSha}&per_page=100`, token);
    const selectedRun = selectHostedCiRun(workflowRuns.workflow_runs, { sourceSha, branch: expectedBranch(environment) });
    if (workflowPath === 'ci.yml') {
      const ciArtifacts = await getJson(`${root}/actions/runs/${selectedRun.id}/artifacts?per_page=100`, token);
      hostedCiEvidence = { ...validateHostedCiArtifact(ciArtifacts.artifacts, selectedRun), headSha: selectedRun.head_sha };
    }
  }
  if (!hostedCiEvidence) throw new Error('Required hosted CI workflow did not produce evidence for the selected candidate.');
  return { releaseRunId: String(runId), releaseRunAttempt: String(run.run_attempt), releaseArtifactId: artifact.id, releaseArtifactName: artifact.name, requiredWorkflows: requiredPaths, hostedCiEvidence };
}

async function main() {
  const [command] = process.argv.slice(2);
  if (command !== 'verify') throw new Error('Usage: phase10-release-run.mjs verify');
  const result = await verifyReleaseEvidence({
    repository: process.env.GITHUB_REPOSITORY,
    sourceSha: process.env.CANDIDATE_SHA,
    runId: process.env.RELEASE_RUN_ID,
    artifactName: process.env.RELEASE_ARTIFACT_NAME,
    environment: process.env.TARGET_ENVIRONMENT,
    token: process.env.GITHUB_TOKEN,
  });
  if (process.env.GITHUB_OUTPUT) {
    const { appendFile } = await import('node:fs/promises');
    await appendFile(process.env.GITHUB_OUTPUT, `release_run_attempt=${result.releaseRunAttempt}\nrelease_artifact_id=${result.releaseArtifactId}\nhosted_ci_run_id=${result.hostedCiEvidence.runId}\nhosted_ci_run_attempt=${result.hostedCiEvidence.runAttempt}\nhosted_ci_artifact_name=${result.hostedCiEvidence.name}\n`);
  }
  console.log(JSON.stringify(result));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => { console.error(`Phase 10 release evidence rejected: ${error.message}`); process.exitCode = 1; });
}
