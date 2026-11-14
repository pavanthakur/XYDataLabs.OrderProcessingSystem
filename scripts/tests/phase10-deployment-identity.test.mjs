import test from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { calculateDeploymentIdentity } from '../phase10-deployment-identity.mjs';

test('deployment identity is deterministic and binds environment parameters and operator inputs', async () => {
  const repo = path.resolve('.');
  const first = await calculateDeploymentIdentity({ repositoryRoot: repo, environment: 'dev', location: 'centralindia' });
  const repeated = await calculateDeploymentIdentity({ repositoryRoot: repo, environment: 'dev', location: 'centralindia' });
  const changedOrigin = await calculateDeploymentIdentity({ repositoryRoot: repo, environment: 'dev', location: 'centralindia', publicDomain: 'dev.example.test', bindAliases: true });
  const sqlAdmin = await calculateDeploymentIdentity({
    repositoryRoot: repo,
    environment: 'dev',
    location: 'centralindia',
    deploySql: true,
    sqlEntraAdminObjectId: '99fce3f5-b801-4aa1-b2df-122900204d65',
    sqlEntraAdminLogin: 'pavan.thakur@example.test',
  });
  const changedSqlAdmin = await calculateDeploymentIdentity({
    repositoryRoot: repo,
    environment: 'dev',
    location: 'centralindia',
    deploySql: true,
    sqlEntraAdminObjectId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    sqlEntraAdminLogin: 'sql-admin@example.test',
  });
  const redisSelected = await calculateDeploymentIdentity({ repositoryRoot: repo, environment: 'dev', location: 'centralindia', deployRedis: true });
  assert.equal(first.identitySha256, repeated.identitySha256);
  assert.notEqual(first.identitySha256, changedOrigin.identitySha256);
  assert.notEqual(sqlAdmin.identitySha256, changedSqlAdmin.identitySha256);
  assert.notEqual(first.identitySha256, redisSelected.identitySha256);
  assert.equal(JSON.stringify(sqlAdmin).includes('pavan.thakur@example.test'), false);
  assert.equal(first.parameterFile, 'infra/parameters/phase10-dev.json');
  assert.deepEqual(
    first.infrastructureInputs.map((input) => input.path),
    [...first.infrastructureInputs.map((input) => input.path)].sort(),
  );
});

test('deployment identity is stable across Windows and Linux line endings', async () => {
  const repositoryRoot = path.resolve('.');
  const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), 'phase10-deployment-identity-'));
  try {
    await cp(path.join(repositoryRoot, 'infra'), path.join(temporaryRoot, 'infra'), { recursive: true });
    const policyDirectory = path.join(temporaryRoot, 'Resources', 'Azure-Deployment');
    await mkdir(policyDirectory, { recursive: true });
    await cp(path.join(repositoryRoot, 'Resources', 'Azure-Deployment', 'branch-policy.json'), path.join(policyDirectory, 'branch-policy.json'));

    async function convertToLf(directory) {
      for (const entry of await readdir(directory, { withFileTypes: true })) {
        const entryPath = path.join(directory, entry.name);
        if (entry.isDirectory()) {
          await convertToLf(entryPath);
        } else if (entry.isFile() && /\.(?:bicep|json)$/.test(entry.name)) {
          const text = await readFile(entryPath, 'utf8');
          await writeFile(entryPath, text.replace(/\r\n?/g, '\n'));
        }
      }
    }

    await convertToLf(path.join(temporaryRoot, 'infra'));
    const parameterFile = path.join(temporaryRoot, 'infra', 'parameters', 'phase10-dev.json');
    const parameters = await readFile(parameterFile, 'utf8');
    await writeFile(parameterFile, parameters.replace(/\r\n?/g, '\n'));
    const branchPolicy = path.join(policyDirectory, 'branch-policy.json');
    const policy = await readFile(branchPolicy, 'utf8');
    await writeFile(branchPolicy, policy.replace(/\r\n?/g, '\n'));

    const windowsStyle = await calculateDeploymentIdentity({ repositoryRoot, environment: 'dev', location: 'centralindia' });
    const linuxStyle = await calculateDeploymentIdentity({ repositoryRoot: temporaryRoot, environment: 'dev', location: 'centralindia' });
    assert.equal(linuxStyle.identitySha256, windowsStyle.identitySha256);
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
});

test('deployment identity rejects invalid environment, region, alias mode, or domain', async () => {
  const repositoryRoot = path.resolve('.');
  await assert.rejects(calculateDeploymentIdentity({ repositoryRoot, environment: 'local', location: 'centralindia' }), /environment/);
  await assert.rejects(calculateDeploymentIdentity({ repositoryRoot, environment: 'dev', location: '../secret' }), /region/);
  await assert.rejects(calculateDeploymentIdentity({ repositoryRoot, environment: 'dev', location: 'centralindia', aliasMode: 'unsafe' }), /Alias mode/);
  await assert.rejects(calculateDeploymentIdentity({ repositoryRoot, environment: 'dev', location: 'centralindia', publicDomain: 'https://localhost' }), /domain/);
  await assert.rejects(calculateDeploymentIdentity({ repositoryRoot, environment: 'dev', location: 'centralindia', deploySql: true }), /explicit Entra administrator/);
});
