import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const hash = (content) => createHash('sha256')
  .update(Buffer.isBuffer(content) ? content.toString('utf8').replace(/\r\n?/g, '\n') : content)
  .digest('hex');

export async function calculateDeploymentIdentity({ repositoryRoot, environment, location, publicDomain = '', bindAliases = false, aliasMode = 'direct', cleanupInfra = false, deploySql = false, deployRedis = false, sqlEntraAdminObjectId = '', sqlEntraAdminLogin = '' }) {
  if (!['dev', 'staging', 'prod'].includes(environment)) throw new Error('Unsupported deployment environment.');
  if (!/^[a-z0-9]+$/.test(location)) throw new Error('Azure region is invalid.');
  if (!['direct', 'frontdoor'].includes(aliasMode)) throw new Error('Alias mode is invalid.');
  if (publicDomain && !/^(?:[a-z0-9-]+\.)*[a-z0-9-]+\.[a-z]{2,}$/i.test(publicDomain)) throw new Error('Public domain is invalid.');
  const sqlEntraAdminConfigurationSha256 = deploySql
    ? (() => {
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(sqlEntraAdminObjectId) || !sqlEntraAdminLogin.trim()) {
        throw new Error('Deploying SQL requires a valid explicit Entra administrator object ID and login.');
      }
      return hash(JSON.stringify({ objectId: sqlEntraAdminObjectId.toLowerCase(), login: sqlEntraAdminLogin.trim().toLowerCase() }));
    })()
    : '';
  const parameterFile = path.join(repositoryRoot, 'infra', 'parameters', `phase10-${environment}.json`);
  const parameterBytes = await readFile(parameterFile);
  const parameterFileSha256 = hash(parameterBytes);
  const infrastructureInputs = [];
  async function collectBicep(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const entryPath = path.join(directory, entry.name);
      if (entry.isDirectory()) await collectBicep(entryPath);
      else if (entry.isFile() && entry.name.endsWith('.bicep')) {
        infrastructureInputs.push({ path: path.relative(repositoryRoot, entryPath).replaceAll('\\', '/'), sha256: hash(await readFile(entryPath)) });
      }
    }
  }
  await collectBicep(path.join(repositoryRoot, 'infra'));
  // Do not use localeCompare here: deployment identity must hash identically
  // on Windows operator machines and Linux GitHub runners, independent of ICU
  // version or process locale.
  infrastructureInputs.sort((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0);
  const branchPolicyPath = path.join(repositoryRoot, 'Resources', 'Azure-Deployment', 'branch-policy.json');
  const branchPolicySha256 = hash(await readFile(branchPolicyPath));
  const identity = {
    schemaVersion: 1,
    environment,
    location,
    publicDomain: publicDomain.toLowerCase(),
    bindAliases: Boolean(bindAliases),
    aliasMode,
    cleanupInfra: Boolean(cleanupInfra),
    deploySql: Boolean(deploySql),
    deployRedis: Boolean(deployRedis),
    sqlEntraAdminConfigurationSha256,
    parameterFile: `infra/parameters/phase10-${environment}.json`,
    parameterFileSha256,
    infrastructureInputs,
    branchPolicySha256,
  };
  return { ...identity, identitySha256: hash(JSON.stringify(identity)) };
}

async function main() {
  const args = process.argv.slice(2);
  const read = (name) => { const index = args.indexOf(`--${name}`); return index < 0 ? undefined : args[index + 1]; };
  const identity = await calculateDeploymentIdentity({
    repositoryRoot: read('repoRoot') ?? process.cwd(),
    environment: read('environment'),
    location: read('location'),
    publicDomain: read('publicDomain') ?? '',
    bindAliases: read('bindAliases') === 'true',
    aliasMode: read('aliasMode') ?? 'direct',
    cleanupInfra: read('cleanupInfra') === 'true',
    deploySql: read('deploySql') === 'true',
    deployRedis: read('deployRedis') === 'true',
    sqlEntraAdminObjectId: read('sqlEntraAdminObjectId') ?? process.env.SQL_ENTRA_ADMIN_OBJECT_ID ?? '',
    sqlEntraAdminLogin: read('sqlEntraAdminLogin') ?? process.env.SQL_ENTRA_ADMIN_LOGIN ?? '',
  });
  if (process.env.GITHUB_OUTPUT) {
    const { appendFile } = await import('node:fs/promises');
    await appendFile(process.env.GITHUB_OUTPUT, `identity_sha256=${identity.identitySha256}\nparameter_file_sha256=${identity.parameterFileSha256}\n`);
  }
  console.log(JSON.stringify(identity));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => { console.error(`Phase 10 deployment parameter identity rejected: ${error.message}`); process.exitCode = 1; });
}
