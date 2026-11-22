import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const permissionKinds = new Set(['certificates', 'keys', 'secrets', 'storage']);

/**
 * Convert the Key Vault GET representation into a valid ARM AccessPolicyEntry
 * payload. Azure CLI serializes absent optional fields as null, but the vault
 * PUT API rejects those nulls (for example permissions.certificates: null).
 * Non-null grants are preserved exactly; malformed/unrecognized grants fail closed.
 */
export function normalizeKeyVaultAccessPolicies(value) {
  if (!Array.isArray(value)) throw new TypeError('Key Vault access-policy snapshot must be an array.');

  return value.map((policy, index) => {
    if (!policy || typeof policy !== 'object' || Array.isArray(policy)) {
      throw new TypeError(`Key Vault access-policy entry ${index} is malformed.`);
    }
    if (typeof policy.tenantId !== 'string' || !policy.tenantId.trim()
      || typeof policy.objectId !== 'string' || !policy.objectId.trim()) {
      throw new TypeError(`Key Vault access-policy entry ${index} is missing a required identity field.`);
    }
    if (!policy.permissions || typeof policy.permissions !== 'object' || Array.isArray(policy.permissions)) {
      throw new TypeError(`Key Vault access-policy entry ${index} has malformed permissions.`);
    }

    const entry = { ...policy };
    // applicationId is optional in the ARM schema; omit the null returned by GET.
    if (entry.applicationId === null) delete entry.applicationId;

    const permissions = { ...entry.permissions };
    for (const key of Object.keys(permissions)) {
      if (!permissionKinds.has(key)) {
        throw new TypeError(`Key Vault access-policy entry ${index} contains an unknown permission category.`);
      }
      if (permissions[key] === null) {
        delete permissions[key];
      } else if (!Array.isArray(permissions[key]) || permissions[key].some((permission) => typeof permission !== 'string')) {
        throw new TypeError(`Key Vault access-policy entry ${index} contains a malformed permission list.`);
      }
    }
    entry.permissions = permissions;
    return entry;
  });
}

async function main() {
  const [inputPath, outputPath] = process.argv.slice(2);
  if (!inputPath || !outputPath || process.argv.length !== 4) {
    throw new Error('Usage: node normalize-phase10-keyvault-access-policies.mjs <input.json> <output.json>');
  }
  const snapshot = JSON.parse(await readFile(inputPath, 'utf8'));
  const normalized = normalizeKeyVaultAccessPolicies(snapshot);
  await writeFile(outputPath, `${JSON.stringify(normalized, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
}

if (process.argv[1] && path.resolve(fileURLToPath(import.meta.url)) === path.resolve(process.argv[1])) {
  main().catch((error) => {
    console.error(`Key Vault policy snapshot rejected: ${error.message}`);
    process.exitCode = 1;
  });
}
