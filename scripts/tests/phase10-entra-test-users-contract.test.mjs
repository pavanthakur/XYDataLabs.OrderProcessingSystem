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
  const browser = byLabel('5 Run: Azure Dev 05 Regular-User Isolation (No Payments)');
  assert.equal(preview.length, 1);
  assert.equal(apply.length, 1);
  assert.equal(browser.length, 1);
  assert.ok(preview[0].args.includes('Plan'));
  assert.ok(apply[0].args.includes('Apply') && apply[0].args.includes('-Confirm'));
  assert.ok(browser[0].args.some(arg => arg.endsWith('/scripts/run-phase10-azure-dev-identity-isolation.ps1')));
  assert.ok(!browser[0].args.includes('ProviderMatrix'));
  assert.match(browser[0].detail, /no payments/i);
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
