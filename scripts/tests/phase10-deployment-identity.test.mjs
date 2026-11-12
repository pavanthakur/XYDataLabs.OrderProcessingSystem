import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { calculateDeploymentIdentity } from '../phase10-deployment-identity.mjs';

test('deployment identity is deterministic and binds environment parameters and operator inputs', async () => {
  const repo = path.resolve('.');
  const first = await calculateDeploymentIdentity({ repositoryRoot: repo, environment: 'dev', location: 'centralindia' });
  const repeated = await calculateDeploymentIdentity({ repositoryRoot: repo, environment: 'dev', location: 'centralindia' });
  const changedOrigin = await calculateDeploymentIdentity({ repositoryRoot: repo, environment: 'dev', location: 'centralindia', publicDomain: 'dev.example.test', bindAliases: true });
  assert.equal(first.identitySha256, repeated.identitySha256);
  assert.notEqual(first.identitySha256, changedOrigin.identitySha256);
  assert.equal(first.parameterFile, 'infra/parameters/phase10-dev.json');
});

test('deployment identity rejects invalid environment, region, alias mode, or domain', async () => {
  const repositoryRoot = path.resolve('.');
  await assert.rejects(calculateDeploymentIdentity({ repositoryRoot, environment: 'local', location: 'centralindia' }), /environment/);
  await assert.rejects(calculateDeploymentIdentity({ repositoryRoot, environment: 'dev', location: '../secret' }), /region/);
  await assert.rejects(calculateDeploymentIdentity({ repositoryRoot, environment: 'dev', location: 'centralindia', aliasMode: 'unsafe' }), /Alias mode/);
  await assert.rejects(calculateDeploymentIdentity({ repositoryRoot, environment: 'dev', location: 'centralindia', publicDomain: 'https://localhost' }), /domain/);
});
