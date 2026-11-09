import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createPublicRuntimeConfig } from "../frontend/apps/web/public-runtime-config.mjs";
import { validateEntraDeployment } from "./prepare-entra-deployment.mjs";
const origin = "https://test-app.example.test";
const settings = { directoryId:"11111111-1111-1111-1111-111111111111", apiClientId:"22222222-2222-2222-2222-222222222222",
  spaClientId:"33333333-3333-3333-3333-333333333333", webOrigin:origin, tenantClaimType:"extn.applicationTenantCode",
  registeredRedirectUris:[`${origin}/auth/callback`], registeredLogoutUris:[`${origin}/signed-out`], selectorEnabled:false };
test("validates Entra contract for every cloud environment with production selector off", () => {
  for (const env of ["dev", "staging", "prod"]) assert.equal(validateEntraDeployment(settings, env).selectorEnabled, false);
});
test("rejects incomplete provisioning, insecure origins, missing registration and directory tenant as application tenant", () => {
  for (const change of [{directoryId:""}, {apiClientId:""}, {spaClientId:""}, {tenantClaimType:"tid"},
    {webOrigin:"http://localhost:5022"}, {registeredRedirectUris:[]}, {registeredLogoutUris:[]}])
    assert.throws(() => validateEntraDeployment({...settings,...change}, "dev"));
});
test("public runtime is allowlisted, same-origin and does not contain credentials", () => {
  const result = createPublicRuntimeConfig({ IDENTITY_MODE:"KeycloakLocal", APP_ENVIRONMENT:"local", PUBLIC_WEB_ORIGIN:"http://localhost:5173",
    PUBLIC_IDENTITY_AUTHORITY:"http://localhost:8081/realms/xy-phase9", PUBLIC_IDENTITY_CLIENT_ID:"local-web", BACKEND_CLIENT_SECRET:"must-not-appear" });
  assert.equal(result.apiBaseUrl, "");
  assert.ok(!JSON.stringify(result).includes("must-not-appear"));
});
test("cloud never falls back to disabled identity or local Keycloak", () => {
  for (const mode of [undefined,"Disabled","KeycloakLocal"]) assert.throws(() => createPublicRuntimeConfig({IDENTITY_MODE:mode,APP_ENVIRONMENT:"prod",PUBLIC_WEB_ORIGIN:origin}));
});
test("only the explicit local administrator is seeded with cross-tenant access", () => {
  const seed = JSON.parse(readFileSync(new URL("../Resources/Keycloak/realm-export.json", import.meta.url), "utf8"));
  assert.ok(seed.roles.realm.some(role => role.name === "platform-admin"));
  assert.deepEqual(seed.users.filter(user => user.realmRoles.includes("platform-admin")).map(user => user.username), ["tenant-admin"]);
  assert.ok(seed.users.some(user => user.username === "tenant-user"));
  for (const tenant of ["a","b","c"]) assert.ok(seed.users.some(user => user.username === `tenant-${tenant}-user`));
});
