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
3. Create an administrator-managed user directory extension `applicationTenantCode`; populate it with the application tenant code for each regular user. Add it as an optional **access-token claim on the API resource registration**, not only on the SPA. Configure the actual emitted JWT claim name `extension_<API-app-client-ID-without-hyphens>_applicationTenantCode` as `IdentityProvider:TenantClaimType`; derive it from the API resource client ID, not a shorthand alias. Missing assignments fail closed. Do not give the SPA directory-write permissions.
   For tenant-isolation test identities, use organizational Microsoft Entra accounts. Personal Microsoft accounts (MSA), including Gmail-address accounts registered as Microsoft accounts, do not receive custom extension claims in tokens; the application must continue to deny access when the claim is absent. See Microsoft's [optional-claims limitations](https://learn.microsoft.com/en-us/entra/identity-platform/optional-claims#configure-directory-extension-optional-claims).
4. Obtain the actual public UI origin from approved deployment outputs or a verified custom-domain configuration. Do not fabricate a hostname, assume localhost, or put generated resource suffixes into the runtime-target catalog. Register `<origin>/auth/callback` and `<origin>/signed-out` on the SPA.
5. Fill a private/environment-specific copy of `Resources/Identity/entra-provisioning.example.json`. Empty IDs intentionally fail validation. Verify the declared redirect/logout URLs against the real directory registration; local contract validation alone is not proof of that registration.
6. Set the following GitHub **environment variables**, not application secrets: `ENTRA_DIRECTORY_ID`, `ENTRA_API_CLIENT_ID`, `ENTRA_SPA_CLIENT_ID`, `IDENTITY_PUBLIC_WEB_ORIGIN`, `ENTRA_REGISTERED_REDIRECT_URIS`, `ENTRA_REGISTERED_LOGOUT_URIS`, and `IDENTITY_TENANT_SELECTOR_ENABLED`. The tenant-claim type is derived from `ENTRA_API_CLIENT_ID`; do not configure a separate alias. URI-list values are JSON arrays; selector is enabled only by literal `true` and defaults off.
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

## Azure dev regular-user isolation test accounts

The Azure dev regular-user isolation gate uses a distinct non-admin account for every active application tenant. Do not reuse the platform administrator: it would not prove regular-user restrictions. Never assign these test accounts `platform-admin` or `phase10-operator`.

For the current dev test, keep the email-to-tenant mapping in `%LOCALAPPDATA%\XYDataLabs\phase10-entra-test-users.dev.json`, copied from `Resources/Identity/entra-test-users.dev.example.json`:

```powershell
$manifestDir = Join-Path $env:LOCALAPPDATA 'XYDataLabs'
New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null
Copy-Item Resources/Identity/entra-test-users.dev.example.json (Join-Path $manifestDir 'phase10-entra-test-users.dev.json')
```

Fill `directoryId` and the API app's client ID from the reviewed Entra registrations, plus the approved email/object-ID mappings; the script validates the directory and runtime tenant set. This file contains personal data and must stay outside Git. `scripts/phase10-entra-test-users.ps1 -Mode Plan -PromptForExpectedSubscriptionId` performs a read-only plan. Plan/Verify need read access to the runtime resources and Graph application, extension, user, and API role-assignment data. `-Mode Apply -Confirm -PromptForExpectedSubscriptionId` is a separate external directory write: it may send B2B guest invitation email and set the API app's existing `applicationTenantCode` extension. For Apply, the operator's delegated Graph access must additionally permit guest invitation and updating the user extension; the documented least-privileged permissions include `User.Invite.All` for invitations and `User.ReadWrite.All` for updating user extension data. Supported Entra directory roles are also required. Subscription Owner alone is insufficient. Do not grant new Graph consent or directory roles as part of this run; stop and request separate review if the preflight lacks access. The script also refuses to proceed if a privileged app role is assigned to a group, because it cannot prove group membership safely. It never changes app registrations, grants roles, resets guest redemption or deletes users. `Verify` must pass after invited users redeem their invitations.

In VS Code, choose **Tasks: Run Task → 5 Run: Azure Dev 05 Optional B2B Guest Isolation (No Payments)**. Confirm the approved subscription GUID in the terminal. The task runs guest `Verify` before opening the browser. Sign in once per guest when prompted and let the runner handle sign-out. It checks the full allow/deny matrix, token claims, selector filtering, deep-link denial and sign-out without creating orders or payments. Signed expired-token rejection is a separate check. See the Microsoft Graph [invitation API](https://learn.microsoft.com/en-us/graph/api/invitation-post?view=graph-rest-1.0) and [API-resource optional-claim guidance](https://learn.microsoft.com/en-us/entra/identity-platform/optional-claims).

### Organizational member test accounts (preferred for API extension-claim testing)

For a guided operator flow, the GitHub Actions workflow **04a-04b Phase 10 Entra Member Setup Guide** prints sanitized local instructions only. It has no Azure permissions and cannot create accounts. See the [Entra Member Test Users operator guide](../../runbooks/phase10-entra-member-test-users.md). The local Apply task remains the only provisioning path and requires separate explicit confirmation.

The guest flow above is retained for B2B testing. For the regular-user isolation gate, use three distinct Entra **Member** accounts when testing API directory-extension claims. A Gmail-address MSA cannot be converted into a Member; create new sign-in identities under a verified domain in this directory (the tenant's default `*.onmicrosoft.com` domain is suitable if verified). Keep the Gmail accounts/guest objects untouched. The new UPNs are separate sign-ins, even if the same person operates all three.

1. Copy `Resources/Identity/entra-member-test-users.dev.example.json` to `%LOCALAPPDATA%\XYDataLabs\phase10-entra-member-test-users\phase10-entra-member-test-users.dev.json`. Fill the directory ID, API app client ID, verified sign-in domain, and one unique UPN/display name for each active tenant. Leave object IDs blank initially. Never place this file in Git.
2. Run **5 Run: Azure Dev 04a Organizational Member Plan (Read Only)**. It confirms the selected subscription/directory, live active-tenant set, verified domain, API extension/claim/scope and existing account/role state. The plan is read-only.
3. Review the mapping and ensure the operator has the delegated Graph read/create/update access and supported directory role required by the exact Graph operations. Microsoft Graph's create-user API supports delegated `User.Create`; this workflow also reads directory/app metadata and updates the user extension, so the effective least-privilege permission set may include additional read and user-write scopes. Subscription Owner is not sufficient. The tool does not add Graph consent, directory roles, or user licenses; stop for separate admin review if permissions are missing. Existing accounts are never password-reset; confirm you can sign in to them before using them for the browser gate.
4. Run **5 Run: Azure Dev 04b Organizational Member Apply (Directory Writes)** only after reviewing the plan. It requires `-Confirm`, a typed phrase, and one secure temporary-password prompt per account it creates. Use a unique strong temporary password per user and retain it in your approved password manager until first sign-in. The password is sent only in the Graph HTTPS request body, is not printed or saved by the script, and must be changed at first sign-in. Normal MFA/Conditional Access still applies. The flow creates/updates only mapped users and `applicationTenantCode`; it sends no invitation email, never converts/deletes users, never changes app roles, and pins object IDs only in the private manifest.
5. Run member `Verify` (also performed by the browser task), then choose **5 Run: Azure Dev 05b Organizational Member Isolation (No Payments)**. Sign in as each displayed UPN, change its temporary password, and complete normal MFA. The browser gate checks each identity's own-tenant allow, cross-tenant denial, forged header, deep link, selector, sign-out and API token claim. It creates no orders/payments.
6. If sandbox checkout acceptance is separately approved, choose **5 Run: Azure Dev 06b Organizational Member Sandbox Payments (Submits Sandbox Payments)**. The task re-verifies the member manifest, asks you to confirm the approved subscription and type `RUN SANDBOX`, then runs serially: TenantA/Razorpay, TenantB/Razorpay and TenantC/OpenPay. It creates a fresh order and submits one sandbox payment per tenant; it does not change routes or retry ambiguous outcomes. Complete normal sign-in/MFA for each member when prompted. Its sanitized report records the identity type and per-tenant hashes, not UPNs/object IDs. This is a payment-mutating task, separate from 05b; it must not run in CI or be treated as covered by the no-payment isolation PASS. The **06 Optional B2B Guest Sandbox Payments** task is retained only for external-guest testing.

Direct commands, if you prefer PowerShell over VS Code tasks:

```powershell
pwsh -NoProfile -File scripts/phase10-entra-member-test-users.ps1 -Mode Plan -PromptForExpectedSubscriptionId
pwsh -NoProfile -File scripts/phase10-entra-member-test-users.ps1 -Mode Apply -PromptForExpectedSubscriptionId -Confirm
pwsh -NoProfile -File scripts/phase10-entra-member-test-users.ps1 -Mode Verify -ExpectedSubscriptionId '<approved-dev-subscription-guid>'
pwsh -NoProfile -File scripts/run-phase10-azure-dev-identity-isolation.ps1 -IdentityType member -PromptForExpectedSubscriptionId
```

`Apply` is an actual Entra directory write, not a local-only test. This implementation does not execute it. Review its sanitized plan and permissions before running it; there is no automatic rollback/deletion of created identities.
