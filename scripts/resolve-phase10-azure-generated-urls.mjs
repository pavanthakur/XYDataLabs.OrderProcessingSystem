import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const targets = JSON.parse(readFileSync(new URL('../automation/config/runtime-targets.json', import.meta.url), 'utf8')).targets;

function domain(value) {
  if (!/^[a-z0-9-]+(?:\.[a-z0-9-]+)*\.azurecontainerapps\.io$/.test(value ?? '')) {
    throw new Error('Azure Container Apps environment domain is missing or invalid.');
  }
  return value;
}

export function resolveGeneratedDevUrls({ targetKey, defaultDomain, gatewayFqdn, uiFqdn, expectedUiOrigin, requireLiveApps = false }) {
  const target = targets.find((item) => item.key === targetKey);
  if (targetKey !== 'azure-dev' || target?.publicUrlMode !== 'generated' || target?.allowGeneratedAzureUrlFallback !== true) {
    throw new Error('Generated origins are enabled only for the explicit Azure-dev target.');
  }
  if (!target.azureGatewayContainerAppName || !target.azureUiContainerAppName) {
    throw new Error('Azure-dev target is missing its Gateway or UI Container App name.');
  }
  const suffix = domain(defaultDomain);
  const expectedGateway = `${target.azureGatewayContainerAppName}.${suffix}`;
  const expectedUi = `${target.azureUiContainerAppName}.${suffix}`;
  if (requireLiveApps && (!gatewayFqdn || !uiFqdn)) throw new Error('Both live Azure-dev Gateway and UI FQDNs are required.');
  if (gatewayFqdn && gatewayFqdn !== expectedGateway) throw new Error('Live Gateway FQDN does not match the selected Azure-dev environment.');
  if (uiFqdn && uiFqdn !== expectedUi) throw new Error('Live UI FQDN does not match the selected Azure-dev environment.');
  const apiOrigin = `https://${expectedGateway}`;
  const uiOrigin = `https://${expectedUi}`;
  if (expectedUiOrigin !== undefined && expectedUiOrigin !== uiOrigin) {
    throw new Error('IDENTITY_PUBLIC_WEB_ORIGIN must equal the exact live Azure-dev UI origin.');
  }
  return { apiOrigin, uiOrigin, defaultDomain: suffix, gatewayFqdn: expectedGateway, uiFqdn: expectedUi };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const value = (flag) => process.argv.includes(flag) ? process.argv[process.argv.indexOf(flag) + 1] : undefined;
    const resolved = resolveGeneratedDevUrls({
      targetKey: value('--target'), defaultDomain: value('--default-domain'),
      gatewayFqdn: value('--gateway-fqdn'), uiFqdn: value('--ui-fqdn'),
      expectedUiOrigin: value('--expected-ui-origin'),
      requireLiveApps: process.argv.includes('--require-live-apps'),
    });
    process.stdout.write(`${JSON.stringify(resolved)}\n`);
  } catch (error) {
    console.error(error instanceof Error ? error.message : 'Generated Azure-dev URL resolution failed.');
    process.exitCode = 1;
  }
}
