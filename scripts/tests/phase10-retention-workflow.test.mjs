import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';

const workflow = await readFile(new URL('../../.github/workflows/phase10-retention-cleanup.yml', import.meta.url), 'utf8');
const requireAutomation = createRequire(new URL('../../automation/package.json', import.meta.url));
const yaml = requireAutomation('js-yaml');

test('retention workflow parses as YAML and keeps ACR read access scoped to manual preview', () => {
  const parsed = yaml.load(workflow);
  assert.ok(parsed.jobs.cleanup);
  assert.equal(parsed.jobs.cleanup_acr.permissions['id-token'], 'write');
  assert.match(parsed.jobs.cleanup_acr.if, /workflow_dispatch/);
  assert.equal(parsed.on.workflow_dispatch.inputs.cleanupAcr.default, false);
});

test('ACR workflow is manual opt-in inventory only and cannot delete manifests', () => {
  assert.match(workflow, /cleanupAcr:[\s\S]*?default: false/);
  assert.match(workflow, /Preview ACR Image Inventory \(Platform, Read Only\)/);
  assert.match(workflow, /orderprocessing-payments/);
  assert.match(workflow, /set -euo pipefail/);
  assert.match(workflow, /az acr manifest list-metadata/);
  assert.match(workflow, /az containerapp revision list/);
  assert.match(workflow, /ACR_RG=.*resourceGroup/);
  assert.match(workflow, /expected \$\{RG_NAME\}/);
  assert.match(workflow, /type == "array" and all\(\.\[\]; .*\.properties\.active/);
  assert.match(workflow, /not digest-qualified; complete protected-digest inventory cannot be proven/);
  assert.match(workflow, /jq -e/);
  assert.doesNotMatch(workflow, /\|\| true/);
  assert.doesNotMatch(workflow, /az acr repository delete/);
  assert.doesNotMatch(workflow, /az acr import .*--force/);
});
