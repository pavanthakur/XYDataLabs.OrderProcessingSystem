import { writeFileSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { createPublicRuntimeConfig } from "../frontend/apps/web/public-runtime-config.mjs";

export function validateEntraDeployment(settings, environment) {
  if (!settings || typeof settings !== "object") throw new Error("Entra provisioning manifest must be an object.");
  if (!["dev", "staging", "prod"].includes(environment)) throw new Error("Select dev, staging or prod.");
  for (const key of ["directoryId", "apiClientId", "spaClientId"]) {
    if (!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(settings[key] ?? "") || /^0+-0+-0+-0+-0+$/.test(settings[key]))
      throw new Error(`Configure the real environment-specific ${key}; provisioning has not been completed.`);
  }
  if (!settings.tenantClaimType?.startsWith("extn.") || settings.tenantClaimType === "extn.tid") throw new Error("Configure an application-tenant directory extension claim (extn.*), never tid.");
  const authority = `https://login.microsoftonline.com/${settings.directoryId}/v2.0`;
  const config = createPublicRuntimeConfig({ IDENTITY_MODE: "Entra", APP_ENVIRONMENT: environment,
    PUBLIC_WEB_ORIGIN: settings.webOrigin, PUBLIC_IDENTITY_AUTHORITY: authority,
    PUBLIC_IDENTITY_CLIENT_ID: settings.spaClientId, PUBLIC_IDENTITY_SCOPES: `api://${settings.apiClientId}/access_as_user` });
  if (!settings.registeredRedirectUris?.includes(config.redirectUri) || !settings.registeredLogoutUris?.includes(config.postLogoutRedirectUri))
    throw new Error("The provisioning manifest must include the exact callback and signed-out URLs registered for this environment.");
  return { authority, audience: settings.apiClientId, spaClientId: settings.spaClientId,
    requiredScope: "access_as_user", apiScope: config.scopes[0], tenantClaimType: settings.tenantClaimType,
    webOrigin: settings.webOrigin, selectorEnabled: settings.selectorEnabled === true };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const value = flag => process.argv[process.argv.indexOf(flag) + 1];
    const environment = process.env.IDENTITY_ENVIRONMENT;
    const settings = process.argv.includes("--manifest") ? JSON.parse(readFileSync(value("--manifest"), "utf8")) : {
      directoryId: process.env.ENTRA_DIRECTORY_ID, apiClientId: process.env.ENTRA_API_CLIENT_ID,
      spaClientId: process.env.ENTRA_SPA_CLIENT_ID, webOrigin: process.env.IDENTITY_PUBLIC_WEB_ORIGIN,
      tenantClaimType: process.env.ENTRA_TENANT_CLAIM_TYPE,
      registeredRedirectUris: JSON.parse(process.env.ENTRA_REGISTERED_REDIRECT_URIS || "[]"),
      registeredLogoutUris: JSON.parse(process.env.ENTRA_REGISTERED_LOGOUT_URIS || "[]"),
      selectorEnabled: process.env.IDENTITY_TENANT_SELECTOR_ENABLED === "true"
    };
    const identity = validateEntraDeployment(settings, environment);
    if (!process.argv.includes("--output")) throw new Error("An explicit generated-parameters output path is required.");
    writeFileSync(value("--output"), JSON.stringify({ applicationIdentity: { value: identity } }, null, 2));
    console.log(`Entra configuration contract passed for ${environment}. Directory provisioning/live login verification remain separate gates.`);
  } catch (error) { console.error(error instanceof Error ? error.message : "Invalid Entra provisioning settings."); process.exitCode = 1; }
}
