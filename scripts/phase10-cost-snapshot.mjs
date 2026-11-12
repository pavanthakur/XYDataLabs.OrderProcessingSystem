import { spawnSync } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

function runAz(args) {
  const result = process.platform === 'win32'
    ? spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', '$azArgs = ConvertFrom-Json -AsHashtable $env:PHASE10_AZ_ARGS; & az @azArgs; exit $LASTEXITCODE'], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, windowsHide: true, env: { ...process.env, PHASE10_AZ_ARGS: JSON.stringify(args) } })
    : spawnSync('az', args, { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, windowsHide: true });
  if (result.error || result.status !== 0) throw new Error(`Read-only Azure query failed: az ${args.slice(0, 3).join(' ')} (exit ${result.status ?? 'unavailable'}).`);
  try { return JSON.parse(result.stdout); } catch { throw new Error(`Read-only Azure query returned invalid JSON: az ${args.slice(0, 3).join(' ')}.`); }
}

function rowsFromCostQuery(result) {
  const properties = result?.properties ?? result;
  const columns = (properties?.columns ?? []).map((item) => item.name);
  if (properties?.nextLink) throw new Error('Cost Management response is paginated; refusing to report a partial subscription total.');
  if (!columns.includes('ServiceName') || !columns.includes('ResourceId') || !columns.some((name) => ['totalCost', 'PreTaxCost', 'Cost'].includes(name)) || !Array.isArray(properties?.rows)) {
    throw new Error('Cost Management response is missing service/cost columns or rows.');
  }
  return properties.rows.map((row) => Object.fromEntries(columns.map((name, index) => [name, row[index]])))
    .map((row) => {
      const cost = Number(row.totalCost ?? row.PreTaxCost ?? row.Cost);
      if (!Number.isFinite(cost)) throw new Error('Cost Management returned a non-numeric cost value.');
      return { service: String(row.ServiceName), resourceId: String(row.ResourceId ?? 'unattributed'), cost, currency: String(row.Currency ?? 'unknown'), date: row.UsageDate ?? null };
    });
}

export function buildCostSnapshot({ capturedAt = new Date().toISOString(), subscriptionId, resourceGroup, costQuery, resources, containerApps, acrUsage, logAnalyticsByTable, sqlStorage, functionsStorage }) {
  if (!subscriptionId || !resourceGroup || !Array.isArray(resources) || !Array.isArray(containerApps) || !Array.isArray(acrUsage)
    || !Array.isArray(sqlStorage) || !Array.isArray(functionsStorage) || !Array.isArray(logAnalyticsByTable?.columns) || !Array.isArray(logAnalyticsByTable?.rows)) {
    throw new Error('Subscription, resource group, resource, Container Apps, ACR, Log Analytics, SQL and Functions observations are required.');
  }
  const logColumns = logAnalyticsByTable.columns.map((column) => column.name);
  if (!logColumns.includes('DataType') || !logColumns.includes('ingestionMB')) throw new Error('Log Analytics response is missing DataType or ingestionMB columns.');
  return {
    schemaVersion: 1,
    readOnly: true,
    capturedAt,
    subscriptionId,
    resourceGroup,
    costMonthToDateByService: rowsFromCostQuery(costQuery),
    resources: resources.map(({ name, type, location, sku, id }) => ({ name, type, location, sku: sku?.name ?? sku ?? null, id })),
    containerApps: containerApps.map((app) => ({
      name: app.name,
      runningStatus: app.properties?.runningStatus ?? null,
      activeRevisionCount: app.activeRevisionCount ?? null,
      liveReplicaCount: app.liveReplicaCount ?? null,
      minReplicas: app.properties?.template?.scale?.minReplicas ?? null,
      maxReplicas: app.properties?.template?.scale?.maxReplicas ?? null,
      configuredReplicas: (app.properties?.template?.scale?.rules ?? []).length ? 'event-driven' : 'min/max only',
    })),
    acrUsage: acrUsage.map(({ name, currentValue, limit, unit }) => ({ name, currentValue, limit, unit })),
    logAnalyticsByTable,
    sqlStorage,
    functionsStorage,
    limitations: [
      'Cost Management data can lag; this is an observation, not a real-time bill or spending cap.',
      'Replica counts are point-in-time observations and may change immediately after capture, especially under scale-to-zero.',
      'Storage and SQL values are emitted only when their Azure metrics are available.',
    ],
  };
}

function requireComparableSnapshot(snapshot, label) {
  if (snapshot?.schemaVersion !== 1 || snapshot.readOnly !== true || !snapshot.subscriptionId || !snapshot.resourceGroup
    || !Array.isArray(snapshot.costMonthToDateByService) || !Array.isArray(snapshot.acrUsage)
    || !Array.isArray(snapshot.containerApps) || !Array.isArray(snapshot.sqlStorage)
    || !Array.isArray(snapshot.functionsStorage) || !Array.isArray(snapshot.logAnalyticsByTable?.columns)
    || !Array.isArray(snapshot.logAnalyticsByTable?.rows)) {
    throw new Error(`${label} snapshot is missing required schemaVersion 1 observations.`);
  }
}

function indexBy(items, keySelector) {
  const result = new Map();
  for (const item of items) result.set(keySelector(item), item);
  return result;
}

export function compareCostSnapshots(before, after) {
  requireComparableSnapshot(before, 'Before');
  requireComparableSnapshot(after, 'After');
  if (before.subscriptionId.toLowerCase() !== after.subscriptionId.toLowerCase()
    || before.resourceGroup.toLowerCase() !== after.resourceGroup.toLowerCase()) {
    throw new Error('Snapshots must use the same subscription and resource group.');
  }

  const oldCosts = new Map();
  const newCosts = new Map();
  const sumCosts = (rows, destination) => {
    for (const row of rows) {
      if (!Number.isFinite(row.cost)) continue;
      const key = [row.service, row.resourceId, row.currency].join('|');
      destination.set(key, (destination.get(key) ?? 0) + row.cost);
    }
  };
  sumCosts(before.costMonthToDateByService, oldCosts);
  sumCosts(after.costMonthToDateByService, newCosts);
  const costsByResource = [...new Set([...oldCosts.keys(), ...newCosts.keys()])].sort().map((key) => {
    const [service, resourceId, currency] = key.split('|');
    const prior = oldCosts.get(key);
    const current = newCosts.get(key);
    return { service, resourceId, currency, beforeMonthToDate: prior ?? null, afterMonthToDate: current ?? null, delta: prior === undefined || current === undefined ? null : current - prior };
  });

  const metricDelta = (beforeValue, afterValue) => Number.isFinite(beforeValue) && Number.isFinite(afterValue)
    ? { before: beforeValue, after: afterValue, delta: afterValue - beforeValue }
    : { before: Number.isFinite(beforeValue) ? beforeValue : null, after: Number.isFinite(afterValue) ? afterValue : null, delta: null };

  const acrBefore = indexBy(before.acrUsage, (item) => item.name);
  const acrAfter = indexBy(after.acrUsage, (item) => item.name);
  const acrUsage = [...new Set([...acrBefore.keys(), ...acrAfter.keys()])].sort().map((name) => ({
    name,
    currentValue: metricDelta(acrBefore.get(name)?.currentValue, acrAfter.get(name)?.currentValue),
    unit: acrAfter.get(name)?.unit ?? acrBefore.get(name)?.unit ?? null,
  }));

  const tableUsage = (snapshot) => {
    const columns = snapshot.logAnalyticsByTable.columns.map((column) => column.name);
    const tableIndex = columns.indexOf('DataType');
    const amountIndex = columns.indexOf('ingestionMB');
    if (tableIndex < 0 || amountIndex < 0) return new Map();
    return new Map(snapshot.logAnalyticsByTable.rows.map((row) => [String(row[tableIndex]), Number(row[amountIndex])]));
  };
  const logBefore = tableUsage(before);
  const logAfter = tableUsage(after);
  const logAnalyticsByTable = [...new Set([...logBefore.keys(), ...logAfter.keys()])].sort().map((table) => ({
    table,
    lastSevenDaysIngestionMB: metricDelta(logBefore.get(table), logAfter.get(table)),
    interpretation: 'Rolling seven-day window; delta is not cumulative ingestion since the earlier snapshot.',
  }));

  const oldSql = indexBy(before.sqlStorage, (item) => item.name);
  const newSql = indexBy(after.sqlStorage, (item) => item.name);
  const sqlStorage = [...new Set([...oldSql.keys(), ...newSql.keys()])].sort().map((name) => ({
    name,
    storagePercent: metricDelta(oldSql.get(name)?.storagePercent, newSql.get(name)?.storagePercent),
    maxSizeBytes: newSql.get(name)?.maxSizeBytes ?? oldSql.get(name)?.maxSizeBytes ?? null,
  }));

  const oldFunctions = indexBy(before.functionsStorage, (item) => item.functionApp);
  const newFunctions = indexBy(after.functionsStorage, (item) => item.functionApp);
  const functionsStorage = [...new Set([...oldFunctions.keys(), ...newFunctions.keys()])].sort().map((functionApp) => ({
    functionApp,
    storageAccount: newFunctions.get(functionApp)?.storageAccount ?? oldFunctions.get(functionApp)?.storageAccount ?? null,
    usedCapacityBytes: metricDelta(oldFunctions.get(functionApp)?.usedCapacityBytes, newFunctions.get(functionApp)?.usedCapacityBytes),
  }));

  const oldApps = indexBy(before.containerApps, (item) => item.name);
  const newApps = indexBy(after.containerApps, (item) => item.name);
  const containerApps = [...new Set([...oldApps.keys(), ...newApps.keys()])].sort().map((name) => ({
    name,
    activeRevisionCount: metricDelta(oldApps.get(name)?.activeRevisionCount, newApps.get(name)?.activeRevisionCount),
    liveReplicaCount: metricDelta(oldApps.get(name)?.liveReplicaCount, newApps.get(name)?.liveReplicaCount),
  }));

  const incomplete = [];
  for (const [category, rows, fields] of [
    ['ACR usage', acrUsage, ['currentValue']],
    ['Log Analytics ingestion', logAnalyticsByTable, ['lastSevenDaysIngestionMB']],
    ['SQL storage', sqlStorage, ['storagePercent']],
    ['Functions storage', functionsStorage, ['usedCapacityBytes']],
    ['Container App replicas', containerApps, ['activeRevisionCount', 'liveReplicaCount']],
  ]) {
    if (rows.some((row) => fields.some((field) => {
      const value = row[field];
      return field === 'lastSevenDaysIngestionMB' ? value.delta === null : value.delta === null;
    }))) incomplete.push(category);
  }
  if (before.costMonthToDateByService.length === 0 || after.costMonthToDateByService.length === 0
    || costsByResource.some((row) => row.delta === null)) incomplete.push('Cost Management by resource');

  return {
    schemaVersion: 1,
    comparisonStatus: incomplete.length === 0 ? 'COMPARABLE' : 'INCOMPLETE',
    before: { capturedAt: before.capturedAt ?? null, subscriptionId: before.subscriptionId, resourceGroup: before.resourceGroup },
    after: { capturedAt: after.capturedAt ?? null, subscriptionId: after.subscriptionId, resourceGroup: after.resourceGroup },
    costByResource: costsByResource,
    acrUsage,
    containerApps,
    logAnalyticsByTable,
    sqlStorage,
    functionsStorage,
    incompleteCategories: incomplete,
    caveats: ['Cost Management values are month-to-date and may lag; delta is between reported snapshots, not a final invoice.', 'Log Analytics values are rolling seven-day ingestion.', 'Null values mean unavailable evidence, never zero.'],
  };
}

async function main(args) {
  const value = (name) => { const index = args.indexOf(name); return index < 0 ? undefined : args[index + 1]; };
  const comparePath = value('--compare');
  const afterPath = value('--to');
  const output = value('--output');
  if (comparePath || afterPath) {
    if (!comparePath || !afterPath || !output) throw new Error('Usage: node scripts/phase10-cost-snapshot.mjs --compare <before.json> --to <after.json> --output <new-delta.json>');
    const before = JSON.parse(await readFile(comparePath, 'utf8'));
    const after = JSON.parse(await readFile(afterPath, 'utf8'));
    const comparison = compareCostSnapshots(before, after);
    await mkdir(path.dirname(output), { recursive: true });
    await writeFile(output, `${JSON.stringify(comparison, null, 2)}\n`, { flag: 'wx' });
    process.stdout.write(`Read-only cost comparison written: ${output} (${comparison.comparisonStatus})\n`);
    return;
  }
  const resourceGroup = value('--resource-group');
  const expectedSubscriptionId = value('--subscription-id');
  const acrName = value('--acr-name');
  const workspaceName = value('--workspace-name');
  if (!resourceGroup || !expectedSubscriptionId || !acrName || !workspaceName || !output) throw new Error('Usage: node scripts/phase10-cost-snapshot.mjs --subscription-id <expected-subscription-id> --resource-group <dev-rg> --acr-name <platform-acr> --workspace-name <workspace> --output <new-report.json>');
  const account = runAz(['account', 'show', '--output', 'json']);
  if (!account.id || account.id.toLowerCase() !== expectedSubscriptionId.toLowerCase()) throw new Error('Azure CLI is not authenticated to the explicitly selected subscription.');
  const resources = runAz(['resource', 'list', '--resource-group', resourceGroup, '--output', 'json']);
  const containerApps = runAz(['containerapp', 'list', '--resource-group', resourceGroup, '--output', 'json']);
  for (const app of containerApps) {
    const revisions = runAz(['containerapp', 'revision', 'list', '--name', app.name, '--resource-group', resourceGroup, '--output', 'json']);
    if (!Array.isArray(revisions) || revisions.some((revision) => typeof revision.properties?.active !== 'boolean')) {
      throw new Error(`Azure returned an incomplete active-revision inventory for ${app.name}.`);
    }
    const activeRevisions = revisions.filter((revision) => revision.properties?.active === true);
    app.activeRevisionCount = activeRevisions.length;
    app.liveReplicaCount = 0;
    for (const revision of activeRevisions) {
      const replicas = runAz(['containerapp', 'replica', 'list', '--name', app.name, '--resource-group', resourceGroup, '--revision', revision.name, '--output', 'json']);
      if (!Array.isArray(replicas)) throw new Error(`Azure returned an invalid replica inventory for ${app.name}.`);
      app.liveReplicaCount += replicas.length;
    }
  }
  const acrUsage = runAz(['acr', 'show-usage', '--name', acrName, '--output', 'json']);
  const costQuery = runAz(['rest', '--method', 'post', '--url', `https://management.azure.com/subscriptions/${account.id}/providers/Microsoft.CostManagement/query?api-version=2025-03-01`, '--headers', 'Content-Type=application/json', '--body', JSON.stringify({ type: 'ActualCost', timeframe: 'MonthToDate', dataset: { granularity: 'None', aggregation: { totalCost: { name: 'PreTaxCost', function: 'Sum' } }, grouping: [{ type: 'Dimension', name: 'ServiceName' }, { type: 'Dimension', name: 'ResourceId' }] } }), '--output', 'json']);
  const workspace = runAz(['monitor', 'log-analytics', 'workspace', 'show', '--resource-group', resourceGroup, '--workspace-name', workspaceName, '--query', 'customerId', '--output', 'json']);
  const logAnalyticsByTable = runAz(['monitor', 'log-analytics', 'query', '--workspace', String(workspace), '--analytics-query', 'Usage | where TimeGenerated > ago(7d) | summarize ingestionMB=sum(Quantity) by DataType | order by ingestionMB desc', '--output', 'json']);

  const dbs = resources.filter((item) => item.type?.toLowerCase() === 'microsoft.sql/servers/databases');
  const sqlStorage = dbs.map((db) => {
    const metrics = runAz(['monitor', 'metrics', 'list', '--resource', db.id, '--metric', 'storage_percent', '--interval', 'PT1H', '--aggregation', 'Average', '--output', 'json']);
    const data = metrics?.value?.[0]?.timeseries?.flatMap((series) => series.data ?? []) ?? [];
    const latest = data.filter((item) => Number.isFinite(item.average)).at(-1);
    return { name: db.name, maxSizeBytes: db.properties?.maxSizeBytes ?? null, storagePercent: latest?.average ?? null, currentServiceObjectiveName: db.sku?.name ?? null };
  });
  const storageAccounts = resources.filter((item) => item.type?.toLowerCase() === 'microsoft.storage/storageaccounts');
  const functions = resources.filter((item) => item.type?.toLowerCase() === 'microsoft.web/sites' && item.kind?.toLowerCase().includes('functionapp'));
  const functionsStorage = [];
  for (const app of functions) {
    const setting = runAz(['functionapp', 'config', 'appsettings', 'list', '--name', app.name, '--resource-group', resourceGroup, '--query', "[?name=='AzureWebJobsStorage__accountName'].value | [0]", '--output', 'json']);
    const storage = storageAccounts.find((item) => item.name.toLowerCase() === String(setting ?? '').toLowerCase());
    let usedCapacityBytes = null;
    if (storage) {
      const metrics = runAz(['monitor', 'metrics', 'list', '--resource', storage.id, '--metric', 'UsedCapacity', '--interval', 'PT1H', '--aggregation', 'Average', '--output', 'json']);
      const data = metrics?.value?.[0]?.timeseries?.flatMap((series) => series.data ?? []) ?? [];
      usedCapacityBytes = data.filter((item) => Number.isFinite(item.average)).at(-1)?.average ?? null;
    }
    functionsStorage.push({ functionApp: app.name, storageAccount: storage?.name ?? null, usedCapacityBytes });
  }
  const logTable = logAnalyticsByTable?.tables?.[0];
  const snapshot = buildCostSnapshot({ subscriptionId: account.id, resourceGroup, costQuery, resources, containerApps, acrUsage, logAnalyticsByTable: { columns: logTable?.columns ?? [], rows: logTable?.rows ?? [] }, sqlStorage, functionsStorage });
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(output, `${JSON.stringify(snapshot, null, 2)}\n`, { flag: 'wx' });
  process.stdout.write(`Read-only cost snapshot written: ${output}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(`Cost snapshot failed: ${error.message}`);
    process.exitCode = 1;
  });
}
