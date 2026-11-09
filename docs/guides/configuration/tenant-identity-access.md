# Tenant identity and access

## Access model

Local non-Docker and Docker use Keycloak; Azure uses Entra API access tokens. Authentication supplies the identity; the shared server-side tenant policy supplies authorization.

- The local `tenant-admin` account is explicitly seeded with `platform-admin` and its existing operations permissions. One login can select any **active application tenant**, including newly registered tenants. It still accesses one tenant per request.
- The `tenant-admin` role alone, matching usernames/emails, directory administration and Azure subscription ownership do **not** confer global access. Other endpoint-specific roles remain required.
- `tenant-a-user` and legacy `tenant-user` belong to TenantA; `tenant-b-user` belongs to TenantB; `tenant-c-user` belongs to TenantC. Regular users see only their own tenant and cannot bypass authorization through a forged request header or URL.
- `tenant_code` is an application tenant assignment. Entra `tid` identifies an identity directory and must never be used as that assignment.
- The authenticated runtime configuration and registry are filtered consistently. Existing anonymous topology discovery remains available for automation compatibility; it does not authorize business requests.
- `configuredActiveTenantCode` is a deployment default, not the signed-in account's tenant. Regular users initialize to their authorized tenant. Global administrators can preserve an authorized selection across refresh.
- The production selector remains disabled unless explicitly enabled by environment policy. Authorization is independent of whether the selector is visible.

## Local startup and account switching

Both startup paths reconcile local identity seeds after Keycloak is ready. For an already running stack:

```powershell
# Inspection first; no role/user/client writes.
pwsh -NoProfile -File scripts/sync-local-identity.ps1 -WhatIf
# Applies only project-owned local seed identity settings; no database reset.
pwsh -NoProfile -File scripts/sync-local-identity.ps1
```

The command verifies local container ownership and port publication. Existing passwords and populated profile fields are preserved. Missing seed profile fields and tenant assignments are initialized. Conflicting tenant assignments or an unexpectedly global regular seed account stop reconciliation for operator review. The tenant attribute is administrator-managed, not user-editable. Administrator credentials come from private local settings; never paste them into chat or commit them.

Open `/customers`, sign in as `tenant-admin`, then select tenants directly. To become a tenant-specific user, click **Sign out**, wait for the signed-out page, then **Sign in** with the desired account. Closing private windows is no longer required. Application data is cleared across tabs; unrelated browser storage is retained. A provider-logout failure is shown explicitly and must not be treated as confirmed SSO logout.

The local non-Docker app can run with Docker-backed dependencies using `start-local-api-profile.ps1 -Phase10DockerBacking -DisableStartupDdl`. This is a host-process application test, not a dependency-free test. HTTP and HTTPS API profiles share port 5010; run those API profiles sequentially, not simultaneously. Never stop an unrelated port owner.

## Runtime public identity configuration

The UI loads `/runtime-config.json` before authentication. The server and Vite development server publish the same allowlisted contract. API calls use the same-origin proxy. No identity URLs or credentials need to be baked into the promoted image.

Required server environment variables:

| Variable | Meaning |
|---|---|
| `IDENTITY_MODE` | Explicit `KeycloakLocal`, `Entra`, or local-only `Disabled` |
| `APP_ENVIRONMENT` | `local`, `docker`, `dev`, `staging`, or `prod` |
| `PUBLIC_WEB_ORIGIN` | Actual externally reachable UI origin, without a trailing slash |
| `PUBLIC_IDENTITY_AUTHORITY` | Provider authority; Azure must use the directory-specific HTTPS v2 authority |
| `PUBLIC_IDENTITY_CLIENT_ID` | Public SPA client ID, never a client secret |
| `PUBLIC_IDENTITY_SCOPES` | Entra API delegated scope |
| `ORDERPROCESSING_API_BASE_URL` | Server-side proxy destination; not serialized into the public configuration |

The fixed callback paths are `/auth/callback` and `/signed-out`; register exact environment URLs. Azure rejects local/disabled identity, missing configuration and insecure/local web origins. Public configuration responses are not cached and never serialize the environment wholesale.

## Azure provisioning — separate approval required

No Azure directory writes or deployments are part of local implementation acceptance. Repeat these steps separately for dev, staging and prod, with directory permissions approved by the owner:

1. Register environment-specific API and SPA applications in the intended Entra directory. Require v2 API access tokens. Expose delegated scope `api://<API application ID>/access_as_user`, grant it to the SPA, and arrange consent.
2. Define API app role value `platform-admin` for user/group assignment. Assign it only to explicitly approved administrators. Do not assign it to workload service principals. Existing endpoint-specific roles such as `phase10-operator` need separate API app-role definitions/assignments if those operations are required.
3. Create an administrator-managed user directory extension `applicationTenantCode`; populate it with the application tenant code for each regular user. Add it as an optional **access-token claim on the API resource registration**, not only on the SPA. Configure the actual emitted JWT claim name, normally `extn.applicationTenantCode`, as `IdentityProvider:TenantClaimType`. Missing assignments fail closed. Do not give the SPA directory-write permissions.
4. Obtain the actual public UI origin from approved deployment outputs or a verified custom-domain configuration. Do not fabricate a hostname, assume localhost, or put generated resource suffixes into the runtime-target catalog. Register `<origin>/auth/callback` and `<origin>/signed-out` on the SPA.
5. Fill a private/environment-specific copy of `Resources/Identity/entra-provisioning.example.json`. Empty IDs intentionally fail validation. Verify the declared redirect/logout URLs against the real directory registration; local contract validation alone is not proof of that registration.
6. Set the following GitHub **environment variables**, not application secrets: `ENTRA_DIRECTORY_ID`, `ENTRA_API_CLIENT_ID`, `ENTRA_SPA_CLIENT_ID`, `IDENTITY_PUBLIC_WEB_ORIGIN`, `ENTRA_TENANT_CLAIM_TYPE`, `ENTRA_REGISTERED_REDIRECT_URIS`, `ENTRA_REGISTERED_LOGOUT_URIS`, and `IDENTITY_TENANT_SELECTOR_ENABLED`. URI-list values are JSON arrays; selector is enabled only by literal `true` and defaults off.
7. Validate before any approved deployment:

```powershell
$env:IDENTITY_ENVIRONMENT = 'dev'
node scripts/prepare-entra-deployment.mjs --manifest <configured-manifest.json> --output <generated-identity.parameters.json>
```

The workflow performs the same validation before cloud writes and passes the generated `applicationIdentity` parameter to subscription-scoped Bicep. All API hosts receive explicit Entra mode, authority, audience, delegated scope and claim mapping. The UI receives only public identity settings. This does **not** provision directory registrations, grant directory permissions or verify live user sign-in automatically.

See [Microsoft optional-claim guidance](https://learn.microsoft.com/en-us/entra/identity-platform/optional-claims) and [MSAL Browser](https://azuread.github.io/microsoft-authentication-library-for-js/ref/classes/_azure_msal_browser.PublicClientApplication.html). ID tokens are not API bearer tokens; Entra roles/tenant claims are normalized only after API token validation.

## Validation and acceptance

```powershell
npm --prefix frontend run typecheck
npm --prefix frontend run test:web
node --test scripts/identity-config.test.mjs
dotnet test tests/XYDataLabs.OrderProcessingSystem.API.Tests
# Docker local identity acceptance; no real-provider payment transaction.
npm --prefix automation run test:customer-directory:browser
# Optional visible local browser:
$env:PHASE10_BROWSER_HEADED = '1'
# Host-process UI overrides: http://localhost:5173 or https://localhost:5174
$env:PHASE10_CUSTOMER_BASE_URL = 'https://localhost:5174'
npm --prefix automation run test:customer-directory:browser
```

Remove those optional process variables after use. Evidence is written to `TestResults/DockerStorage/customer-directory-browser-*` or the parent E2E run directory. Acceptance covers one admin session switching tenants, refresh, same-browser sign-out/sign-in, cross-tab logout, restricted selectors and direct cross-tenant HTTP 403 responses.

Routing/persistence integration fixtures explicitly disable identity and must run against a verified disposable database; authenticated security is covered separately by bearer and browser tests. Offline Entra tests validate token signatures, issuer, audience, expiry, scopes and claim normalization using fixture signing keys. They are **not** live Azure E2E. Azure acceptance stays pending until approved provisioning/deployment and real Entra browser tests pass. Deterministic local payment tests are not proof of real provider sandbox acceptance.
