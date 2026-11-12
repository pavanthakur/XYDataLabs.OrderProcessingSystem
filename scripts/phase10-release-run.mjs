import path from 'node:path';
import { fileURLToPath } from 'node:url';

const API_VERSION = '2022-11-28';

export function expectedBranch(environment) {
  const branch = { dev: 'dev', staging: 'staging', prod: 'main' }[environment];
  if (!branch) throw new Error('Unsupported deployment environment.');
  return branch;
}

export function allowedReleaseBranches(environment) {
  const branches = {
    dev: ['dev'],
    staging: ['dev', 'staging'],
    prod: ['dev', 'staging', 'main'],
  }[environment];
  if (!branches) throw new Error('Unsupported deployment environment.');
  return branches;
}

export function validateReleaseRun(run, artifact, { repository, sourceSha, runId, artifactName, environment }) {
  if (run?.id !== Number(runId) || run?.status !== 'completed' || run?.conclusion !== 'success') throw new Error('Release producer run is not completed successfully.');
  if (String(run?.path ?? '').split('@')[0] !== '.github/workflows/build-phase10-images.yml') throw new Error('Release producer is not the approved image/package workflow.');
  if (run?.head_repository?.full_name !== repository || run?.repository?.full_name !== repository) throw new Error('Release producer repository mismatch.');
  if (run?.head_sha !== sourceSha || !/^[0-9a-f]{40}$/i.test(sourceSha ?? '')) throw new Error('Release producer source SHA mismatch.');
  if (!allowedReleaseBranches(environment).includes(run?.head_branch)) throw new Error('Release producer branch is not permitted for the target environment.');
  if (artifact?.name !== artifactName || artifact?.expired !== false || !Number.isSafeInteger(artifact?.id) || !/^sha256:[0-9a-f]{64}$/i.test(artifact?.digest ?? '')) throw new Error('Named release artifact is missing, expired, or has no valid artifact digest.');
  if (artifact?.workflow_run?.id !== Number(runId)) throw new Error('Release artifact is not owned by the selected producer run.');
  return true;
}

export function validatePromotionAncestry(comparison, { sourceSha, deploymentWorkflowSha }) {
  if (!/^[0-9a-f]{40}$/i.test(sourceSha ?? '') || !/^[0-9a-f]{40}$/i.test(deploymentWorkflowSha ?? '')) {
    throw new Error('Release source and deployment workflow revisions must be full commit SHAs.');
  }
  if (comparison?.status === 'identical') {
    if (sourceSha !== deploymentWorkflowSha) throw new Error('GitHub ancestry comparison is inconsistent with the selected revisions.');
    return true;
  }
  if (comparison?.status !== 'ahead' || comparison?.base_commit?.sha !== sourceSha || comparison?.merge_base_commit?.sha !== sourceSha) {
    throw new Error('Release source revision is not an ancestor of the deployment workflow revision.');
  }
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

export function selectPromotionHostedCiRuns(sourceRuns, deploymentRuns, { sourceSha, sourceBranch, deploymentWorkflowSha, deploymentBranch }) {
  const sourceRun = selectHostedCiRun(sourceRuns, { sourceSha, branch: sourceBranch });
  const deploymentRun = deploymentWorkflowSha === sourceSha
    ? sourceRun
    : selectHostedCiRun(deploymentRuns, { sourceSha: deploymentWorkflowSha, branch: deploymentBranch });
  return { sourceRun, deploymentRun };
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

export function classifyHostedWorkflows(paths, { adrValidationEnabled = false } = {}) {
  const changed = paths ?? [];
  const any = (regex) => changed.some((file) => regex.test(file));
  const adrPathsChanged = any(/^(\.github\/workflows\/|scripts\/|Resources\/Azure-Deployment\/|infra\/|docs\/architecture\/decisions\/|XYDataLabs\.OrderProcessingSystem\.sln|\.markdownlint\.json$)/i);
  const docsPathsChanged = any(/^(docs\/|scripts\/validate-doc-links\.js$|\.github\/workflows\/validate-doc-links\.yml$)/i);
  const aiCustomizationPathsChanged = any(/^(AGENTS\.md$|memories\/repo\/|scripts\/tests\/test-ai-customization(?:-exit)?\.ps1$|\.github\/(copilot-instructions\.md|completion-check-rubric\.md|instructions\/|prompts\/|agents\/|skills\/|workflows\/validate-ai-customization\.yml|workflows\/README\.md)|docs\/(AI-OPERATING-MODEL\.md|DEVELOPER-OPERATING-MODEL\.md|README\.md|internal\/DEFERRED-WORK-LOG\.md|internal\/README\.md)|scripts\/(validate-ai-customization\.ps1|README\.md))/i);
  const promptPathsChanged = any(/^((\.github\/prompts\/)|ai-runtime\/|scripts\/)/i);
  return [
    { workflow: 'ci.yml', required: true, reason: 'Required for every release candidate.' },
    { workflow: 'drift-check.yml', required: true, reason: 'Required for every release candidate.' },
    {
      workflow: 'validate-adrs.yml',
      required: adrValidationEnabled && adrPathsChanged,
      reason: adrValidationEnabled
        ? adrPathsChanged ? 'Required: ADR-sensitive files changed.' : 'Not applicable: no ADR-sensitive files changed.'
        : 'Not applicable: ADR validation is not enabled in the target GitHub Environment.',
    },
    {
      workflow: 'validate-doc-links.yml',
      required: docsPathsChanged,
      reason: docsPathsChanged ? 'Required: documentation or link-validator files changed.' : 'Not applicable: no documentation/link-validator files changed.',
    },
    {
      workflow: 'validate-ai-customization.yml',
      required: aiCustomizationPathsChanged,
      reason: aiCustomizationPathsChanged ? 'Required: AI guidance or customization-validator files changed.' : 'Not applicable: no AI guidance/customization-validator files changed.',
    },
    {
      workflow: 'validate-prompts.yml',
      required: promptPathsChanged,
      reason: promptPathsChanged ? 'Required: prompt, AI runtime, or scripts files changed.' : 'Not applicable: no prompt/AI-runtime/scripts files changed.',
    },
  ];
}

export function applicableHostedWorkflows(paths, options = {}) {
  return classifyHostedWorkflows(paths, options).filter((entry) => entry.required).map((entry) => entry.workflow).sort();
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

export async function verifyReleaseEvidence({ repository, sourceSha, deploymentWorkflowSha, deploymentBranch, runId, artifactName, environment, token }) {
  if (!token) throw new Error('GitHub read token is required to verify release provenance.');
  if (deploymentBranch !== expectedBranch(environment)) throw new Error('Deployment workflow branch does not match the target environment policy.');
  if (!/^[0-9a-f]{40}$/i.test(deploymentWorkflowSha ?? '')) throw new Error('Deployment workflow SHA must be full length.');
  const root = `https://api.github.com/repos/${repository}`;
  const run = await getJson(`${root}/actions/runs/${runId}`, token);
  const artifactsResponse = await getJson(`${root}/actions/runs/${runId}/artifacts?per_page=100`, token);
  const artifact = artifactsResponse.artifacts?.find((item) => item.name === artifactName);
  validateReleaseRun(run, artifact, { repository, sourceSha, runId, artifactName, environment });
  const promotion = await getJson(`${root}/compare/${sourceSha}...${deploymentWorkflowSha}`, token);
  validatePromotionAncestry(promotion, { sourceSha, deploymentWorkflowSha });

  const workflowIndex = await getJson(`${root}/actions/workflows?per_page=100`, token);
  const sourceFiles = await getCommitChangedPaths(repository, sourceSha, token);
  const deploymentFiles = deploymentWorkflowSha === sourceSha ? [] : await getCommitChangedPaths(repository, deploymentWorkflowSha, token);
  const workflowApplicability = classifyHostedWorkflows([...sourceFiles, ...deploymentFiles], { adrValidationEnabled: process.env.ADR_VALIDATION_ENABLED === 'true' });
  const requiredPaths = workflowApplicability.filter((entry) => entry.required).map((entry) => entry.workflow).sort();
  let hostedCiEvidence;
  for (const workflowPath of requiredPaths) {
    const workflow = workflowIndex.workflows?.find((candidate) => candidate.path === `.github/workflows/${workflowPath}`);
    if (!workflow) throw new Error(`Required hosted workflow is missing from repository inventory: ${workflowPath}.`);
    const sourceRuns = await getJson(`${root}/actions/workflows/${workflow.id}/runs?head_sha=${sourceSha}&per_page=100`, token);
    const deploymentRuns = deploymentWorkflowSha === sourceSha
      ? sourceRuns
      : await getJson(`${root}/actions/workflows/${workflow.id}/runs?head_sha=${deploymentWorkflowSha}&per_page=100`, token);
    const { sourceRun, deploymentRun } = selectPromotionHostedCiRuns(sourceRuns.workflow_runs, deploymentRuns.workflow_runs, {
      sourceSha, sourceBranch: run.head_branch, deploymentWorkflowSha, deploymentBranch,
    });
    if (workflowPath === 'ci.yml') {
      const [sourceArtifacts, deploymentArtifacts] = await Promise.all([
        getJson(`${root}/actions/runs/${sourceRun.id}/artifacts?per_page=100`, token),
        deploymentWorkflowSha === sourceSha ? Promise.resolve(null) : getJson(`${root}/actions/runs/${deploymentRun.id}/artifacts?per_page=100`, token),
      ]);
      validateHostedCiArtifact(sourceArtifacts.artifacts, sourceRun);
      const evidence = deploymentWorkflowSha === sourceSha
        ? validateHostedCiArtifact(sourceArtifacts.artifacts, sourceRun)
        : validateHostedCiArtifact(deploymentArtifacts.artifacts, deploymentRun);
      hostedCiEvidence = { ...evidence, headSha: deploymentRun.head_sha, sourceRunId: String(sourceRun.id), sourceRunAttempt: String(sourceRun.run_attempt), sourceHeadSha: sourceRun.head_sha };
    }
  }
  if (!hostedCiEvidence) throw new Error('Required hosted CI workflow did not produce evidence for the selected candidate.');
  return { releaseRunId: String(runId), releaseRunAttempt: String(run.run_attempt), releaseSourceBranch: run.head_branch, sourceSha, deploymentWorkflowSha, deploymentBranch, releaseArtifactId: artifact.id, releaseArtifactName: artifact.name, requiredWorkflows: requiredPaths, workflowApplicability, hostedCiEvidence };
}

async function main() {
  const [command] = process.argv.slice(2);
  if (command !== 'verify') throw new Error('Usage: phase10-release-run.mjs verify');
  const result = await verifyReleaseEvidence({
    repository: process.env.GITHUB_REPOSITORY,
    sourceSha: process.env.CANDIDATE_SHA,
    deploymentWorkflowSha: process.env.DEPLOYMENT_WORKFLOW_SHA,
    deploymentBranch: process.env.DEPLOYMENT_BRANCH,
    runId: process.env.RELEASE_RUN_ID,
    artifactName: process.env.RELEASE_ARTIFACT_NAME,
    environment: process.env.TARGET_ENVIRONMENT,
    token: process.env.GITHUB_TOKEN,
  });
  if (process.env.GITHUB_OUTPUT) {
    const { appendFile } = await import('node:fs/promises');
    await appendFile(process.env.GITHUB_OUTPUT, `release_run_attempt=${result.releaseRunAttempt}\nrelease_source_branch=${result.releaseSourceBranch}\nrelease_artifact_id=${result.releaseArtifactId}\nhosted_ci_run_id=${result.hostedCiEvidence.runId}\nhosted_ci_run_attempt=${result.hostedCiEvidence.runAttempt}\nhosted_ci_artifact_name=${result.hostedCiEvidence.name}\nsource_hosted_ci_run_id=${result.hostedCiEvidence.sourceRunId}\nsource_hosted_ci_run_attempt=${result.hostedCiEvidence.sourceRunAttempt}\nsource_hosted_ci_artifact_name=hosted-ci-${result.hostedCiEvidence.sourceRunId}-${result.hostedCiEvidence.sourceRunAttempt}\ndeployment_workflow_sha=${result.deploymentWorkflowSha}\nworkflow_applicability=${JSON.stringify(result.workflowApplicability)}\n`);
  }
  if (process.env.GITHUB_STEP_SUMMARY) {
    const { appendFile } = await import('node:fs/promises');
    const rows = result.workflowApplicability.map(({ workflow, required, reason }) => `| ${workflow} | ${required ? 'REQUIRED' : 'NOT APPLICABLE'} | ${reason.replace(/[|\r\n]/g, ' ')} |`).join('\n');
    await appendFile(process.env.GITHUB_STEP_SUMMARY, `\n### Hosted workflow applicability\n\n| Workflow | Status | Reason |\n|---|---|---|\n${rows}\n`);
  }
  console.log(JSON.stringify(result));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => { console.error(`Phase 10 release evidence rejected: ${error.message}`); process.exitCode = 1; });
}
