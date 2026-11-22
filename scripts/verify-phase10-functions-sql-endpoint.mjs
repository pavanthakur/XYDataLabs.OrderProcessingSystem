import path from 'node:path';
import { pathToFileURL } from 'node:url';

function normalizeSqlHost(value) {
  const host = String(value ?? '').trim().replace(/^tcp:/i, '').split(',')[0].trim().replace(/\.$/, '').toLowerCase();
  if (!host || host.includes('..') || !/^[a-z0-9.-]+$/.test(host)) return '';
  return host;
}

export function verifyFunctionsSqlEndpoint({ deploymentSqlFqdn, sqlResourceFqdn, functionsSqlConnection }) {
  const serverEntry = String(functionsSqlConnection ?? '').split(';').map((part) => part.trim())
    .find((part) => /^(server|data source|address|network address)\s*=/i.test(part));
  const connectionHost = serverEntry?.slice(serverEntry.indexOf('=') + 1).trim() ?? '';
  const expected = normalizeSqlHost(deploymentSqlFqdn);
  const actual = normalizeSqlHost(sqlResourceFqdn);
  const configured = normalizeSqlHost(connectionHost);

  if (!expected || !actual || !configured || expected !== actual || expected !== configured) {
    return {
      ok: false,
      message: 'Functions SQL endpoint does not match the deployed Azure SQL server; refusing migrations/trigger activation.',
    };
  }

  return {
    ok: true,
    message: 'Functions SQL endpoint matches the deployed Azure SQL server (credential values not emitted).',
  };
}

async function runCli() {
  let input = '';
  process.stdin.setEncoding('utf8');
  for await (const chunk of process.stdin) input += chunk;
  const firstLine = input.indexOf('\n');
  const secondLine = firstLine < 0 ? -1 : input.indexOf('\n', firstLine + 1);
  if (firstLine < 0 || secondLine < 0) {
    console.error('SQL endpoint verification input is incomplete; refusing migrations/trigger activation.');
    process.exitCode = 1;
    return;
  }

  const result = verifyFunctionsSqlEndpoint({
    deploymentSqlFqdn: input.slice(0, firstLine),
    sqlResourceFqdn: input.slice(firstLine + 1, secondLine),
    functionsSqlConnection: input.slice(secondLine + 1),
  });
  (result.ok ? console.log : console.error)(result.message);
  if (!result.ok) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  await runCli();
}
