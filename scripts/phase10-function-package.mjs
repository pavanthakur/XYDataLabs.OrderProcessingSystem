import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export async function validateFunctionPublishDirectory(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = new Set(entries.filter((entry) => entry.isFile()).map((entry) => entry.name));
  if (!files.has('host.json')) throw new Error('Functions publish output must contain host.json at its root.');
  if (!files.has('functions.metadata')) throw new Error('Functions publish output is missing generated functions.metadata.');
  if (files.has('local.settings.json')) throw new Error('Functions package must not contain local.settings.json.');
  const host = JSON.parse(await readFile(path.join(directory, 'host.json'), 'utf8'));
  if (!host || typeof host !== 'object') throw new Error('Functions host.json is invalid.');
  const metadata = JSON.parse(await readFile(path.join(directory, 'functions.metadata'), 'utf8'));
  if (!Array.isArray(metadata) || metadata.length === 0) throw new Error('Functions package metadata must include at least one indexed function.');
  return { functionCount: metadata.length, rootFiles: [...files].sort() };
}

export function validateFunctionArchiveEntries(entries) {
  const names = entries.map((entry) => entry.replaceAll('\\', '/').replace(/^\.\//, ''));
  if (!names.includes('host.json')) throw new Error('Functions archive must place host.json at its root.');
  if (!names.includes('functions.metadata')) throw new Error('Functions archive must contain root functions.metadata.');
  if (names.some((entry) => /(^|\/)local\.settings\.json$/i.test(entry))) throw new Error('Functions archive must not include local.settings.json.');
  if (!names.some((entry) => entry.endsWith('.deps.json')) || !names.some((entry) => entry.endsWith('.runtimeconfig.json'))) {
    throw new Error('Functions archive is missing .NET isolated worker runtime artifacts.');
  }
  return true;
}

async function main() {
  const [mode, target] = process.argv.slice(2);
  if (mode === 'directory') {
    const result = await validateFunctionPublishDirectory(target);
    console.log(`Validated .NET isolated Functions publish output (${result.functionCount} indexed function(s)).`);
  } else if (mode === 'entries') {
    const entries = (await readFile(target, 'utf8')).split(/\r?\n/).filter(Boolean);
    validateFunctionArchiveEntries(entries);
    console.log('Validated Functions ZIP entries.');
  } else {
    throw new Error('Usage: phase10-function-package.mjs directory <publish-dir> | entries <zip-entry-list>');
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => { console.error(`Phase 10 Functions package rejected: ${error.message}`); process.exitCode = 1; });
}
