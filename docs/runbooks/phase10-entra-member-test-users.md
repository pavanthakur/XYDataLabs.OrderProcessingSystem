# Phase 10 Entra Member Test Users — Operator Guide

This guide provisions three non-privileged Entra **Member** identities for no-payment tenant-isolation testing. Personal Microsoft accounts (including Gmail addresses registered as MSAs) cannot be converted into organizational Members. Use new UPNs under a verified domain in the target Entra directory. Keep existing guest/MSA objects unchanged.

These TenantA/B/C accounts are exclusively regular-user isolation/payment-test identities. Do not grant them the `phase10-operator` API application role or replay-runner Service Bus roles; replay approval and execution use separate principals documented in the [Azure smoke runbook](phase10-azure-smoke.md#phase-10-replay-identities-and-automation).

## What the GitHub guide workflow does

Run **04a-04b Phase 10 Entra Member Setup Guide** from branch `dev` and select either `plan` or `apply-guidance-only`. It only prints instructions and a link to this page. It has no Azure permissions, does not query Entra, and never provisions accounts. The `apply-guidance-only` choice is not an approval and does not execute Apply.

## Prepare the private manifest

Copy `Resources/Identity/entra-member-test-users.dev.example.json` to:

```text
%LOCALAPPDATA%\XYDataLabs\phase10-entra-member-test-users\phase10-entra-member-test-users.dev.json
```

Create the parent directory if needed. Fill in:

- the target Entra directory ID;
- the API application **client ID** (not the SPA client ID and not an object ID);
- a verified sign-in domain, such as the directory's verified `onmicrosoft.com` domain;
- one unique Member UPN and display name for each active application tenant: TenantA, TenantB, and TenantC.

Leave `objectId` empty for accounts not yet created. Keep the manifest outside the repository. Never put UPNs, object IDs, passwords, access tokens, or other directory data in workflow inputs, source control, run logs, or artifacts.

## 04a — Preview only

In VS Code, run **5 Run: Azure Dev 04a Organizational Member Plan (Read Only)**, or run:

```powershell
pwsh -NoProfile -File scripts/phase10-entra-member-test-users.ps1 -Mode Plan -PromptForExpectedSubscriptionId
```

Confirm the active subscription ID when prompted. Review the sanitized plan: it should map each active tenant to exactly one ordinary Member account and only propose missing accounts or the intended tenant claim. Stop if the manifest, verified domain, app claim setup, or permissions do not agree. Planning is read-only; it does not create accounts.

## 04b — Separate, explicit directory write

Only after reviewing 04a, run **5 Run: Azure Dev 04b Organizational Member Apply (Directory Writes)**, or:

```powershell
pwsh -NoProfile -File scripts/phase10-entra-member-test-users.ps1 -Mode Apply -PromptForExpectedSubscriptionId -Confirm
```

This is a real Entra directory mutation. The local script has additional typed confirmation and prompts securely for a unique temporary password for each account it creates. Passwords are not written to reports or the manifest; first sign-in requires a password change and normal MFA/Conditional Access. No invitation email is sent, and the script does not assign privileged roles, delete users, or convert guests. Review its sanitized report and inspect Entra state before retrying after any partial failure.

The operator needs the Graph permissions and supported Entra directory role required by the specific create/read/update operations. Subscription Owner alone is not sufficient. Do not grant Graph consent or directory roles ad hoc; get a separate permissions review if the read-only plan or Apply reports access denied.

## Sign in and verify isolation

Run **5 Run: Azure Dev 05b Organizational Member Isolation (No Payments)**. Sign in as each displayed UPN, change its temporary password if prompted, and complete normal MFA. The test checks each identity's own-tenant access and cross-tenant denial, tenant-header/deep-link protections, selector visibility, and sign-out. It must not create orders or payments.

Each distinct identity must authenticate separately at least once. This is required evidence for regular-user isolation; an administrator session or a single account reused across tenants is not a substitute.

## Optional supervised sandbox payment matrix

Payment acceptance is a separate, payment-mutating gate; the no-payment isolation PASS does not cover it. After member `Verify` succeeds and only with separate approval for sandbox transactions, run **5 Run: Azure Dev 06b Organizational Member Sandbox Payments (Submits Sandbox Payments)**. The task re-verifies the member manifest and deployment identity, requires confirmation of the approved dev subscription and the typed phrase `RUN SANDBOX`, then runs serially for TenantA/Razorpay, TenantB/Razorpay, and TenantC/OpenPay. Complete normal sign-in/MFA for each account when prompted.

The runner must preserve the server-assigned provider routes, create one fresh order per tenant, and submit no more than one payment per order. It does not change provider routes or automatically retry an uncertain transaction. If a result is ambiguous, stop and reconcile the existing order/payment status before any new attempt. The sanitized report identifies the identity type and records per-tenant hashes; it does not include UPNs or object IDs. This matrix is sandbox acceptance, not real-money or production certification.

If a multi-tenant run stops after a tenant has already passed, do not rerun the default all-tenant command. Reconcile the interrupted provider order first, then select only the remaining tenants, for example `-TenantCodes TenantB` or `-TenantCodes TenantC`. This creates a fresh order only for the selected tenant(s); the original ambiguous order is never retried. For no-payment preflight, select exactly one tenant; its default remains TenantA.

## Optional fresh-account provisioning check

This is a separate test of the account-provisioning tool, not a prerequisite for proving isolation when the existing three Member accounts are healthy. Do not delete or replace the established TenantA/B/C accounts to simulate a fresh start.

After the dev API/UI have been redeployed and runtime smoke has passed:

1. Copy the existing private manifest to a second file under `%LOCALAPPDATA%\XYDataLabs\phase10-entra-member-test-users\`. Keep the original baseline manifest unchanged.
2. In the copy, retain exactly one mapping for every active tenant. Leave TenantB and TenantC rows and pinned object IDs unchanged. Replace only TenantA's UPN/display name with a unique disposable UPN on the verified organizational sign-in domain, and leave its `objectId` empty. Do not use a Gmail personal Microsoft account as an organizational Member.
3. Run `Plan` with `-ManifestPath <private-copy>`. Proceed only if the result is exactly one `create-member-and-assign-tenant` for TenantA and `no-change` for TenantB and TenantC. Stop on any other proposed action.
4. After separate approval, run `Apply` against that same copy with `-Confirm`; use the secure unique temporary-password prompt. The script pins the created object ID in the copy. Run `Verify` against the same file before browser sign-in.
5. Run the no-payment isolation script with `-IdentityType member -ManifestPath <private-copy>`. Complete normal password change/MFA and confirm the disposable account is allowed only for TenantA, denied TenantB/C, and signs out successfully. This tests account provisioning and authorization, not payment acceptance.
6. Preserve the sanitized report and exact object ID in the operator's private evidence record. Retire the disposable identity only through a separately reviewed and explicitly approved directory operation. Never infer deletion targets from UPN patterns or remove the baseline test accounts.

Example command shape (replace `<private-copy>` with the full private path; do not put identity values in repository files or workflow inputs):

```powershell
$manifest = '<private-copy>'
pwsh -NoProfile -File scripts/phase10-entra-member-test-users.ps1 -Mode Plan -ManifestPath $manifest -PromptForExpectedSubscriptionId
pwsh -NoProfile -File scripts/phase10-entra-member-test-users.ps1 -Mode Apply -ManifestPath $manifest -PromptForExpectedSubscriptionId -Confirm
pwsh -NoProfile -File scripts/phase10-entra-member-test-users.ps1 -Mode Verify -ManifestPath $manifest -PromptForExpectedSubscriptionId
pwsh -NoProfile -File scripts/run-phase10-azure-dev-identity-isolation.ps1 -IdentityType member -ManifestPath $manifest -PromptForExpectedSubscriptionId
```

Do not automate deletion for this one-off check. If disposable-account cleanup becomes a recurring requirement, design a separate Plan/Apply lifecycle tool whose deletion allowlist comes only from a run-owned manifest of exact object IDs created by that run, with independent confirmation and post-action verification. Keep that tool and all Entra directory permissions separate from Azure resource-group cleanup.

## Preserve Entra applications and identities during Azure cleanup

Azure resource-group cleanup is not Entra directory cleanup. Keep the baseline Member test users, the separate replay approver/operator identities, and any existing guest accounts unless they are explicitly reviewed for retirement. Do not add user deletion, app deletion, or directory-wide cleanup options to workflows `00`/`01` or resource-group teardown.

Retain the existing `GitHub-Actions-OIDC`, dev API, and dev SPA app registrations. They are directory-level authentication configuration, not disposable resource-group resources. After a fresh deployment, verify the OIDC federation, API scopes/tenant-claim extension/roles and service principal assignments; resolve the generated dev UI origin and confirm the SPA callback and logout URLs match that exact origin. Update only a demonstrated mismatch through a separately reviewed directory change. Do not create duplicate registrations for each deployment or delete/recreate these registrations as a cleanup shortcut.

## Safety boundary

The GitHub guide workflow is informational only. 04a is read-only. 04b performs directory writes only from the operator's trusted local workstation after explicit confirmation. 05b is a headed, no-payment browser test. 06b is a separate supervised sandbox payment test and requires its own approval. None of these steps deploys Azure resources or changes application registrations.
