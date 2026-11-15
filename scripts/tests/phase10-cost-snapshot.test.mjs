import test from 'node:test';
import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';
import path from 'node:path';
import { buildCostSnapshot, compareCostSnapshots, normalizeLogAnalyticsUsage, queryCostManagement } from '../phase10-cost-snapshot.mjs';

test('cost request uses a complete JSON file and cleans its owned file/directory after success', async () => {
  let requestPath;
  const response = await queryCostManagement('11111111-1111-4111-8111-111111111111', async (args) => {
    assert.deepEqual(args.slice(0, 3), ['rest', '--method', 'post']);
    const body = args[args.indexOf('--body') + 1];
    assert.ok(body.startsWith('@')); requestPath = body.slice(1);
    const json = JSON.parse(await readFile(requestPath, 'utf8'));
    assert.equal(json.dataset.aggregation.totalCost.name, 'PreTaxCost');
    assert.deepEqual(json.dataset.grouping.map((item) => item.name), ['ServiceName', 'ResourceId']);
    return { properties: { rows: [] } };
  });
  assert.deepEqual(response, { properties: { rows: [] } });
  await assert.rejects(access(requestPath));
  await assert.rejects(access(path.dirname(requestPath)));
});

test('cost request cleans up after transport failure and rejects invalid subscription before invocation', async () => {
  let requestPath;
  await assert.rejects(queryCostManagement('11111111-1111-4111-8111-111111111111', (args) => {
    requestPath = args[args.indexOf('--body') + 1].slice(1);
    throw new Error('controlled read-only transport failure');
  }), /controlled/);
  await assert.rejects(access(path.dirname(requestPath)));
  await assert.rejects(queryCostManagement('../other-scope', () => assert.fail('must not invoke Azure')), /subscription/);
});

test('Log Analytics accepts CLI rows and REST tables without copying arbitrary payload fields', () => {
  const cli = normalizeLogAnalyticsUsage([{ DataType: 'AppTraces', ingestionMB: '1.25', TableName: 'PrimaryResult', secret: 'must-not-copy' }]);
  const rest = normalizeLogAnalyticsUsage({ tables: [{ columns: [{ name: 'ingestionMB' }, { name: 'DataType' }], rows: [[1.25, 'AppTraces']] }] });
  assert.deepEqual(cli, rest);
  assert.equal(JSON.stringify(cli).includes('must-not-copy'), false);
  for (const value of [{}, [{ DataType: 'AppTraces' }], [{ DataType: 'AppTraces', ingestionMB: '' }], [{ DataType: 'AppTraces', ingestionMB: 'not-a-number' }], [{ DataType: 'invalid label', ingestionMB: 1 }]]) {
    assert.throws(() => normalizeLogAnalyticsUsage(value), /observations/);
  }
});

test('missing Log Analytics amounts remain unknown in snapshot comparisons, never zero', () => {
  const before = comparisonFixture(3.25, 2, 1, null, 10, 1000);
  const after = comparisonFixture(7.5, 2, 1, 31, 10, 1000);
  const diff = compareCostSnapshots(before, after);
  assert.equal(diff.logAnalyticsByTable[0].lastSevenDaysIngestionMB.before, null);
  assert.equal(diff.logAnalyticsByTable[0].lastSevenDaysIngestionMB.delta, null);
  assert.equal(diff.comparisonStatus, 'INCOMPLETE');
});

function comparisonFixture(cost, acr, replicas, logMb, sqlPercent, storageBytes, subscriptionId = 'sub-id') {
  return buildCostSnapshot({
    capturedAt: `2026-11-${cost === 3.25 ? '11' : '12'}T00:00:00Z`, subscriptionId, resourceGroup: 'rg-dev',
    costQuery: { columns: [{ name: 'ServiceName' }, { name: 'ResourceId' }, { name: 'PreTaxCost' }, { name: 'Currency' }], rows: [['Container Apps', '/resource/app', cost, 'USD']] },
    resources: [], containerApps: [{ name: 'app', activeRevisionCount: 1, liveReplicaCount: replicas, properties: { template: { scale: { minReplicas: 1, maxReplicas: 10, rules: [] } } } }],
    acrUsage: [{ name: 'Storage', currentValue: acr, limit: 10, unit: 'GiB' }],
    logAnalyticsByTable: { columns: [{ name: 'DataType' }, { name: 'ingestionMB' }], rows: [['ContainerAppConsoleLogs_CL', logMb]] },
    sqlStorage: [{ name: 'sql-db', storagePercent: sqlPercent, maxSizeBytes: 2147483648 }],
    functionsStorage: [{ functionApp: 'fn', storageAccount: 'storage', usedCapacityBytes: storageBytes }],
  });
}

test('cost snapshot accepts the ACR CLI value envelope and refuses missing usage', () => {
  const base = comparisonFixture(3.25, 2, 1, 22, 10, 1000);
  const input = { ...base, costQuery: { columns: [{ name: 'ServiceName' }, { name: 'ResourceId' }, { name: 'PreTaxCost' }], rows: [['Registry', '/resource/acr', 1]] } };
  assert.deepEqual(buildCostSnapshot({ ...input, acrUsage: { value: base.acrUsage } }).acrUsage, base.acrUsage);
  assert.throws(() => buildCostSnapshot({ ...input, acrUsage: {} }), /required/);
});

test('cost snapshot normalizes cost, container configuration, ACR and resource inventory without passing through raw payloads', () => {
  const snapshot = buildCostSnapshot({
    capturedAt: '2026-11-12T00:00:00Z', subscriptionId: 'sub-id', resourceGroup: 'rg-dev',
    costQuery: { columns: [{ name: 'ServiceName' }, { name: 'ResourceId' }, { name: 'PreTaxCost' }, { name: 'Currency' }], rows: [['Container Apps', '/subscriptions/sub-id/resourceGroups/rg-dev/providers/Microsoft.App/containerApps/app', 3.25, 'USD']] },
    resources: [{ name: 'app', type: 'Microsoft.App/containerApps', location: 'centralindia', sku: { name: 'Consumption' }, password: 'must-not-copy' }],
    containerApps: [{ name: 'app', activeRevisionCount: 1, liveReplicaCount: 2, properties: { runningStatus: 'Running', template: { scale: { minReplicas: 1, maxReplicas: 10, rules: [] } } } }],
    acrUsage: [{ name: 'Storage', currentValue: 2, limit: 10, unit: 'GiB', secret: 'must-not-copy' }],
    logAnalyticsByTable: { columns: [{ name: 'DataType' }, { name: 'ingestionMB' }], rows: [['ContainerAppConsoleLogs_CL', 22]] }, sqlStorage: [{ name: 'db', maxSizeBytes: 2147483648 }], functionsStorage: [{ functionApp: 'fn', storageAccount: 'storage' }],
  });
  assert.equal(snapshot.costMonthToDateByService[0].cost, 3.25);
  assert.match(snapshot.costMonthToDateByService[0].resourceId, /containerApps\/app/);
  assert.equal(snapshot.containerApps[0].minReplicas, 1);
  assert.equal(snapshot.containerApps[0].liveReplicaCount, 2);
  assert.equal(snapshot.acrUsage[0].currentValue, 2);
  assert.equal(JSON.stringify(snapshot).includes('must-not-copy'), false);
  assert.equal(snapshot.readOnly, true);
});

test('cost snapshot refuses missing subscription or inventory instead of presenting an empty success', () => {
  assert.throws(() => buildCostSnapshot({ resourceGroup: 'rg-dev', resources: [], containerApps: [] }), /required/);
});

test('cost snapshot accepts the Cost Management REST envelope and rejects truncated paginated results', () => {
  const base = comparisonFixture(3.25, 2, 1, 22, 10, 1000);
  const nested = buildCostSnapshot({
    ...base,
    costQuery: { properties: { columns: [{ name: 'ServiceName' }, { name: 'ResourceId' }, { name: 'PreTaxCost' }], rows: [['SQL Database', '/resource/sql', 2.5]] } },
  });
  assert.equal(nested.costMonthToDateByService[0].cost, 2.5);
  assert.throws(() => buildCostSnapshot({ ...base, costQuery: { properties: { columns: [], rows: [], nextLink: 'https://management.azure.com/next' } } }), /paginated/);
});

test('snapshot comparison reports resource cost and storage/replica deltas across the same scope', () => {
  const before = comparisonFixture(3.25, 2, 1, 22, 10, 1000);
  const after = comparisonFixture(7.5, 3, 2, 31, 12, 1250);
  const diff = compareCostSnapshots(before, after);
  assert.equal(diff.comparisonStatus, 'COMPARABLE');
  assert.equal(diff.costByResource[0].delta, 4.25);
  assert.equal(diff.acrUsage[0].currentValue.delta, 1);
  assert.equal(diff.containerApps[0].liveReplicaCount.delta, 1);
  assert.equal(diff.sqlStorage[0].storagePercent.delta, 2);
  assert.equal(diff.functionsStorage[0].usedCapacityBytes.delta, 250);
  assert.equal(diff.logAnalyticsByTable[0].lastSevenDaysIngestionMB.delta, 9);
});

test('snapshot comparison rejects cross-subscription comparisons and keeps missing metrics unknown', () => {
  const before = comparisonFixture(3.25, null, null, null, null, null);
  const after = comparisonFixture(7.5, 3, 2, 31, 12, 1250);
  const diff = compareCostSnapshots(before, after);
  assert.equal(diff.comparisonStatus, 'INCOMPLETE');
  assert.equal(diff.acrUsage[0].currentValue.delta, null);
  assert.throws(() => compareCostSnapshots(before, comparisonFixture(7.5, 3, 2, 31, 12, 1250, 'other-sub')), /same subscription/);
});
