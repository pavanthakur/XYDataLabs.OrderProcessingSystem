import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';

const root = new URL('../../', import.meta.url);
const read = relative => readFile(new URL(relative, root), 'utf8');
const requireAutomation = createRequire(new URL('../../automation/package.json', import.meta.url));

test('VS Code labels optional B2B guest tasks and keeps provisioning separate from no-payment isolation', async () => {
  const ts = requireAutomation('typescript');
  const parsed = ts.parseConfigFileTextToJson('.vscode/tasks.json', await read('.vscode/tasks.json'));
  assert.equal(parsed.error, undefined);
  const tasks = parsed.config.tasks;
  const byLabel = label => tasks.filter(task => task.label === label);
  const preview = byLabel('5 Run: Azure Dev 03 Optional B2B Guest Plan (Read-Only)');
  const apply = byLabel('5 Run: Azure Dev 04 Optional B2B Guest Apply (Directory Writes)');
  const browser = byLabel('5 Run: Azure Dev 05 Optional B2B Guest Isolation (No Payments)');
  assert.equal(preview.length, 1);
  assert.equal(apply.length, 1);
  assert.equal(browser.length, 1);
  assert.ok(preview[0].args.includes('Plan'));
  assert.ok(apply[0].args.includes('Apply') && apply[0].args.includes('-Confirm'));
  assert.ok(browser[0].args.some(arg => arg.endsWith('/scripts/run-phase10-azure-dev-identity-isolation.ps1')));
  assert.ok(!browser[0].args.includes('ProviderMatrix'));
  assert.match(browser[0].detail, /no payments/i);
  assert.match(preview[0].detail, /optional external B2B guest/i);
  assert.match(apply[0].detail, /optional external B2B guest/i);
});

test('guest and member sandbox payment tasks are separate, supervised, identity-aware and never override provider routes', async () => {
  const ts = requireAutomation('typescript');
  const parsed = ts.parseConfigFileTextToJson('.vscode/tasks.json', await read('.vscode/tasks.json'));
  const tasks = parsed.config.tasks;
  const guest = tasks.filter(task => task.label === '5 Run: Azure Dev 06 Optional B2B Guest Sandbox Payments (Submits Sandbox Payments)');
  const member = tasks.filter(task => task.label === '5 Run: Azure Dev 06b Organizational Member Sandbox Payments (Submits Sandbox Payments)');
  assert.equal(guest.length, 1);
  assert.equal(member.length, 1);
  assert.ok(guest[0].args.includes('NonAdminSandbox') && guest[0].args.includes('-PromptForExpectedSubscriptionId'));
  assert.ok(guest[0].args.includes('guest'));
  assert.ok(member[0].args.includes('NonAdminSandbox') && member[0].args.includes('-PromptForExpectedSubscriptionId'));
  assert.ok(member[0].args.includes('member'));
  assert.match(guest[0].detail, /optional external B2B guest/i);
  assert.match(member[0].detail, /assigned route/i);
  const wrapper = await read('scripts/run-phase10-azure-dev-operator-matrix.ps1');
  const branch = wrapper.split("elseif ($Mode -eq 'NonAdminSandbox') {")[1].split('\nelse {')[0];
  assert.match(wrapper, /ValidateSet\('guest','member'\).*\$IdentityType/);
  assert.match(wrapper, /phase10-entra-member-test-users\.ps1/);
  assert.match(branch, /\$IdentityType -eq 'member'/);
  assert.match(branch, /-Mode Verify/);
  assert.match(branch, /--non-admin-sandbox/);
  assert.doesNotMatch(branch, /'--provider'|'--all-active-tenants'/);
  assert.match(wrapper, /XYDATALABS_NONADMIN_IDENTITY_TYPE/);
  assert.match(wrapper, /-cne 'RUN SANDBOX'/);
  const cli = await read('automation/src/cli/run-azure-matrix.ts');
  const executor = await read('automation/src/orchestrator/payment-automation-executor.ts');
  assert.match(cli, /mapNonAdminSandboxIdentities\(manifest, identityType\)/);
  assert.match(cli, /identityType: nonAdminSandboxIdentities\.TenantA\.identityType/);
  assert.match(cli, /identitySha256: createHash\("sha256"\)/);
  assert.doesNotMatch(cli, /userPrincipalName.*summary\.json|email.*summary\.json/i);
  assert.match(executor, /one verified session per mapped tenant/);
  assert.doesNotMatch(executor, /verified guest mapping|three separate guest sessions|Guest sign-out was not verified/);
  assert.match(executor, /Non-admin identity sign-out was not verified/);
});

test('Entra provisioner is dry-run by default and protects external guest writes', async () => {
  const script = await read('scripts/phase10-entra-test-users.ps1');
  const module = await read('scripts/phase10-entra-test-users.module.psm1');
  assert.match(script, /\[string\]\$Mode\s*=\s*'Plan'/);
  assert.match(script, /\[guid\]\$ExpectedDirectoryId\s*=\s*\[guid\]::Empty/);
  assert.match(script, /after three read-only attempts/);
  assert.match(script, /Get-Phase10ActiveTenantCodesFromRuntimeResponse/);
  assert.match(script, /SupportsShouldProcess\s*=\s*\$true/);
  assert.match(script, /ContainsKey\('Confirm'\)/);
  assert.match(script, /APPLY DEV TENANT TEST USERS/);
  assert.match(script, /RESEND DEV TENANT INVITATIONS/);
  assert.match(script, /CreateRedemptionLink/);
  assert.match(script, /CREATE DEV REDEMPTION LINK/);
  assert.match(script, /resetRedemption\s*=\s*\$true/);
  assert.match(script, /sendInvitationMessage\s*=\s*\$false/);
  assert.match(script, /Set-CurrentUserProtectedFileAcl/);
  assert.match(script, /reportContainsRedemptionUrl\s*=\s*\$false/);
  assert.match(script, /deliveryVerified\s*=\s*\$false/);
  assert.match(script, /claimsChanged\s*=\s*0/);
  assert.match(script, /externalUserState\s*-cne\s*'PendingAcceptance'/);
  assert.match(script, /Select-Object -First 1/);
  assert.match(script, /Set-Content -LiteralPath \$reportPath -Encoding utf8NoBOM -Confirm:\$false/);
  assert.equal((script.match(/Verify the ID above against your approved Azure-dev subscription GUID/g) ?? []).length, 1);
  assert.match(script, /sendInvitationMessage\s*=\s*\$true/);
  assert.match(script, /appRoleAssignedTo/);
  assert.match(script, /externalUserState/);
  assert.match(script, /await-invitation-redemption/);
  assert.match(script, /privileged API role is assigned to a group/);
  assert.match(script, /must be stored outside the repository/);
  assert.match(script, /rolesAssigned\s*=\s*0/);
  assert.match(script, /failedStage = \$currentStage/);
  assert.match(script, /\$invitationsSent\+\+/);
  assert.match(script, /\$directoryUser = \$directoryUsers \| Where-Object .*Select-Object -First 1/);
  assert.match(script, /\$directoryUser = \[pscustomobject\]@\{ id = \$userId; email = \[string\]\$mapping\.email/);
  assert.match(module, /Assert-Phase10EntraApiIdentityConfiguration/);
  assert.match(module, /conflicting tenant assignment/);
  assert.match(module, /privileged API role/);
  assert.doesNotMatch(script, /Remove-MgUser|DELETE.*\/users/i);
});

test('Azure regular-user browser gate is headed, payment-free, tenant-complete, and emits sanitized evidence', async () => {
  const testSource = await read('automation/src/browser/entra-regular-user-isolation.browser.test.ts');
  const wrapper = await read('scripts/run-phase10-azure-dev-identity-isolation.ps1');
  assert.match(testSource, /chromium\.launch\(\{ headless: false \}\)/);
  assert.match(testSource, /activeTenantCodes\.length \* activeTenantCodes\.length/);
  assert.match(testSource, /applicationTenantClaimType\(manifest\.apiClientId\)/);
  assert.doesNotMatch(testSource, /extn\.applicationTenantCode/);
  assert.match(testSource, /paymentsAttempted: false/);
  assert.doesNotMatch(testSource, /cardNumber|cardholderName|cvv|passwordInput/i);
  assert.match(wrapper, /-Mode Verify/);
  assert.match(wrapper, /Get-DeploymentFingerprint/);
  assert.match(wrapper, /test:azure:regular-user-isolation/);
  assert.doesNotMatch(wrapper, /ProviderMatrix|run-payment-acceptance/);
});

test('Azure deployment derives the API tenant-claim name instead of accepting a stale alias', async () => {
  const prepare = await read('scripts/prepare-entra-deployment.mjs');
  const orchestrator = await read('.github/workflows/phase10-deploy-orchestrator.yml');
  const infra = await read('.github/workflows/infra-deploy.yml');
  const bicep = await read('infra/modules/containerapps.bicep');
  assert.match(prepare, /getApplicationTenantClaimType\(settings\.apiClientId\)/);
  assert.match(prepare, /tenantClaimType\s*,/);
  assert.match(bicep, /identity\.tenantClaimType/);
  assert.doesNotMatch(orchestrator, /ENTRA_TENANT_CLAIM_TYPE/);
  assert.doesNotMatch(infra, /ENTRA_TENANT_CLAIM_TYPE/);
  assert.doesNotMatch(prepare, /process\.env\.ENTRA_TENANT_CLAIM_TYPE/);
});

test('tracked identity example has only placeholders, not supplied test-account PII', async () => {
  const example = JSON.parse(await read('Resources/Identity/entra-test-users.dev.example.json'));
  assert.equal(example.environment, 'dev');
  assert.ok(example.users.length >= 1);
  assert.ok(example.users.every(user => user.email === '' && user.objectId === ''));
  const guide = await read('docs/guides/configuration/tenant-identity-access.md');
  assert.match(guide, /LOCALAPPDATA/);
  assert.match(guide, /regular-user isolation/i);
});

test('organizational member provisioning is isolated from guest flow and defaults to no writes', async () => {
  const script = await read('scripts/phase10-entra-member-test-users.ps1');
  const module = await read('scripts/phase10-entra-member-test-users.module.psm1');
  const wrapper = await read('scripts/run-phase10-azure-dev-identity-isolation.ps1');
  const example = JSON.parse(await read('Resources/Identity/entra-member-test-users.dev.example.json'));
  const ts = requireAutomation('typescript');
  const tasksResult = ts.parseConfigFileTextToJson('.vscode/tasks.json', await read('.vscode/tasks.json'));
  assert.equal(tasksResult.error, undefined);
  const tasks = tasksResult.config.tasks;
  assert.match(script, /ValidateSet\('Plan','Apply','Verify'\)\]\[string\]\$Mode = 'Plan'/);
  assert.match(script, /PromptForExpectedSubscriptionId/);
  assert.match(script, /SupportsShouldProcess\s*=\s*\$true/);
  assert.match(script, /APPLY DEV MEMBER TEST USERS/);
  assert.match(script, /Read-Host .*AsSecureString/);
  assert.match(script, /forceChangePasswordNextSignIn=\$true/);
  assert.match(script, /emailsSent=0/);
  assert.match(script, /passwordsStored=\$false/);
  assert.match(script, /UserPrincipalName.*outside the repository|must be outside the repository/);
  assert.match(module, /identityType -cne 'member'/);
  assert.match(module, /organizational domain/);
  assert.match(module, /Guest.*not accepted|not an organizational Member/);
  assert.match(module, /conflicting tenant claim/);
  assert.match(wrapper, /ValidateSet\('guest','member'\).*\$IdentityType/);
  assert.match(wrapper, /phase10-entra-member-test-users\.ps1/);
  assert.equal(example.identityType, 'member');
  assert.ok(example.users.every(user => user.userPrincipalName === '' && user.objectId === ''));
  for (const label of [
    '5 Run: Azure Dev 04a Organizational Member Plan (Read Only)',
    '5 Run: Azure Dev 04b Organizational Member Apply (Directory Writes)',
    '5 Run: Azure Dev 05b Organizational Member Isolation (No Payments)'
  ]) assert.equal(tasks.filter(task => task.label === label).length, 1, `${label} exists exactly once`);
  assert.doesNotMatch(script, /sendInvitationMessage|\/invitations|DELETE.*\/users/i);
});

test('GitHub Entra member guide is informational and grants no cloud permissions', async () => {
  const workflow = await read('.github/workflows/phase10-azure-entra-member-setup-guide.yml');
  const runbook = await read('docs/runbooks/phase10-entra-member-test-users.md');
  assert.match(workflow, /workflow_dispatch/);
  assert.match(workflow, /apply-guidance-only/);
  assert.match(workflow, /permissions:\s*\{\}/);
  assert.match(workflow, /refs\/heads\/dev/);
  assert.match(workflow, /did not query Azure\/Entra, create accounts, send email, change claims, or run browser\/payment tests/);
  assert.match(workflow, /This workflow did not approve or execute the directory write/);
  assert.doesNotMatch(workflow, /azure\/login|id-token:\s*write|AZUREAPPSERVICE_|ENTRA_API_CLIENT_ID|subscription-id:/i);
  assert.match(runbook, /04a — Preview only/);
  assert.match(runbook, /04b — Separate, explicit directory write/);
  assert.match(runbook, /outside the repository/);
  assert.match(runbook, /No invitation email is sent/);
});
