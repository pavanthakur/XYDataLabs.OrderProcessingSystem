import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';

const root = new URL('../../', import.meta.url);
const read = relative => readFile(new URL(relative, root), 'utf8');
const requireAutomation = createRequire(new URL('../../automation/package.json', import.meta.url));

test('VS Code keeps Entra provisioning preview, directory writes, and no-payment isolation as separate tasks', async () => {
  const ts = requireAutomation('typescript');
  const parsed = ts.parseConfigFileTextToJson('.vscode/tasks.json', await read('.vscode/tasks.json'));
  assert.equal(parsed.error, undefined);
  const tasks = parsed.config.tasks;
  const byLabel = label => tasks.filter(task => task.label === label);
  const preview = byLabel('5 Run: Azure Dev 03 Entra Test-User Plan (Read-Only)');
  const apply = byLabel('5 Run: Azure Dev 04 Entra Test-User Apply (Invites Guests)');
  const browser = byLabel('5 Run: Azure Dev 05 Non-Admin Tenant Isolation (No Payments)');
  assert.equal(preview.length, 1);
  assert.equal(apply.length, 1);
  assert.equal(browser.length, 1);
  assert.ok(preview[0].args.includes('Plan'));
  assert.ok(apply[0].args.includes('Apply') && apply[0].args.includes('-Confirm'));
  assert.ok(browser[0].args.some(arg => arg.endsWith('/scripts/run-phase10-azure-dev-identity-isolation.ps1')));
  assert.ok(!browser[0].args.includes('ProviderMatrix'));
  assert.match(browser[0].detail, /no payments/i);
});

test('non-admin sandbox payments use a separate supervised task without provider overrides', async () => {
  const ts = requireAutomation('typescript');
  const parsed = ts.parseConfigFileTextToJson('.vscode/tasks.json', await read('.vscode/tasks.json'));
  const tasks = parsed.config.tasks.filter(task => task.label === '5 Run: Azure Dev 06 Non-Admin Sandbox Payments (Submits Sandbox Payments)');
  assert.equal(tasks.length, 1);
  assert.ok(tasks[0].args.includes('NonAdminSandbox') && tasks[0].args.includes('-PromptForExpectedSubscriptionId'));
  const wrapper = await read('scripts/run-phase10-azure-dev-operator-matrix.ps1');
  const branch = wrapper.split("elseif ($Mode -eq 'NonAdminSandbox') {")[1].split('\nelse {')[0];
  assert.match(branch, /-Mode Verify/);
  assert.match(branch, /--non-admin-sandbox/);
  assert.doesNotMatch(branch, /'--provider'|'--all-active-tenants'/);
  assert.match(wrapper, /-cne 'RUN SANDBOX'/);
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
  assert.match(testSource, /extn\.applicationTenantCode/);
  assert.match(testSource, /paymentsAttempted: false/);
  assert.doesNotMatch(testSource, /cardNumber|cardholderName|cvv|passwordInput/i);
  assert.match(wrapper, /-Mode Verify/);
  assert.match(wrapper, /Get-DeploymentFingerprint/);
  assert.match(wrapper, /test:azure:regular-user-isolation/);
  assert.doesNotMatch(wrapper, /ProviderMatrix|run-payment-acceptance/);
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
