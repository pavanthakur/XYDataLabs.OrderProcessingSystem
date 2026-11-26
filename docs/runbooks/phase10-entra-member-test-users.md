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

## Safety boundary

The GitHub guide workflow is informational only. 04a is read-only. 04b performs directory writes only from the operator's trusted local workstation after explicit confirmation. 05b is a headed, no-payment browser test. 06b is a separate supervised sandbox payment test and requires its own approval. None of these steps deploys Azure resources or changes application registrations.
