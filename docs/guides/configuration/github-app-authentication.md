# GitHub App Authentication - Eliminating PAT Expiration

## Problem with PAT Tokens

Personal Access Tokens (PATs) have several limitations:
- ❌ **Expire regularly** (max 1 year for fine-grained PATs)
- ❌ **Manual renewal required** - someone must remember to update them
- ❌ **Tied to individual users** - issues when users leave the organization
- ❌ **Broad permissions** - `repo` scope grants access to everything
- ❌ **No audit trail** - hard to track what actions were performed
- ❌ **Manual secret updates** - must update GH_PAT secret in every repository

## Solution: GitHub App Authentication

GitHub Apps provide **automatic token generation** with no expiration issues:
- ✅ **Tokens auto-generated** - workflow creates them on-demand
- ✅ **Short-lived tokens** (1 hour) - better security
- ✅ **Automatic rotation** - no manual maintenance
- ✅ **Granular permissions** - only grant what's needed
- ✅ **Organization-level** - not tied to individual users
- ✅ **Full audit trail** - all actions tracked in GitHub audit log
- ✅ **Install once, use everywhere** - no per-repo configuration

## How It Works

```mermaid
sequenceDiagram
    participant Workflow
    participant GitHubApp
    participant GitHubAPI
    
    Workflow->>GitHubApp: Request token (using App ID + Private Key)
    GitHubApp->>Workflow: Returns installation token (expires in 1 hour)
    Workflow->>GitHubAPI: Set secrets using installation token
    Note over Workflow,GitHubAPI: Token auto-refreshed for each run
```

## Setup Instructions

### Step 1: Create GitHub App

1. **Navigate to GitHub App creation**:
   - For personal account: https://github.com/settings/apps/new
   - For organization: https://github.com/organizations/[ORG-NAME]/settings/apps/new

2. **Configure the App**:
   ```
   GitHub App name: OrderProcessingSystem-SecretManager
   Description: Manages repository and environment secrets for CI/CD
   Homepage URL: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem
   Webhook: Uncheck "Active" (we don't need webhooks)
   ```

3. **Set Permissions**:
   ```
   Repository permissions:
   - Secrets: Read and write
   
   Organization permissions (if org-level):
   - Secrets: Read and write
   ```

4. **Where can this GitHub App be installed?**:
   - Select: **Only on this account**

5. **Click "Create GitHub App"**

### Step 2: Generate Private Key

1. After creation, scroll to **Private keys** section
2. Click **Generate a private key**
3. A `.pem` file will download automatically
4. **KEEP THIS FILE SECURE** - it's like a password

### Step 3: Install the App

1. Click **Install App** in left sidebar
2. Select your account/organization
3. Choose:
   - **Only select repositories**: Select `XYDataLabs.OrderProcessingSystem`
   - Or **All repositories** if you want to use it everywhere
4. Click **Install**
5. **Note the Installation ID** from the URL: 
   - URL will be: `https://github.com/settings/installations/[INSTALLATION_ID]`
   - Example: `https://github.com/settings/installations/12345678` → Installation ID is `12345678`

### Step 4: Add Secrets to Repository

Add these three secrets at: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions

1. **APP_ID**:
   - Value: Your App ID (found on app settings page)
   - Example: `123456`

2. **APP_INSTALLATION_ID**:
   - Value: Installation ID from Step 3
   - Example: `12345678`

3. **APP_PRIVATE_KEY**:
   - Value: Contents of the `.pem` file you downloaded
   - Open the `.pem` file in a text editor and copy **entire contents** including:
     ```
     -----BEGIN RSA PRIVATE KEY-----
     [key content]
     -----END RSA PRIVATE KEY-----
     ```
   - Paste the entire key as the secret value

### Step 5: Update Workflow (Done Automatically)

The workflow will now:
1. Check for GitHub App credentials (`APP_ID`, `APP_INSTALLATION_ID`, `APP_PRIVATE_KEY`)
2. If found, generate a short-lived token automatically
3. Use that token to set secrets
4. Token expires after 1 hour (auto-refreshed on next run)

## Migration from PAT to GitHub App

### Option 1: New Installation (Recommended)

1. Follow **Setup Instructions** above
2. Add the three `GH_APP_*` secrets
3. Delete the old `GH_PAT` secret (optional - workflow will prefer App if both exist)
4. Run the bootstrap workflow - it will use GitHub App automatically

### Option 2: Keep Both (Fallback)

1. Add GitHub App secrets (as above)
2. Keep existing `GH_PAT` secret
3. Workflow will prefer GitHub App but fall back to PAT if App auth fails

## Verification

After setup, run the bootstrap workflow and check logs:

**With GitHub App**:
```
✅ GitHub App authentication available (App ID: 123456)
🔑 Generated installation token (expires: 2024-01-20 23:30:00 UTC)
Using GitHub App token for secret configuration
```

**With PAT (legacy)**:
```
⚠️  GitHub App not configured, using PAT
Using GH_PAT for authentication (PAT token with repo scope)
```

**Without either**:
```
⚠️  Neither GitHub App nor GH_PAT configured
📋 REQUIRED ACTION: Manually configure repository secrets
```

## Security Comparison

| Feature | PAT | GitHub App |
|---------|-----|------------|
| **Expiration** | 1-365 days | 1 hour (auto-renewed) |
| **Manual maintenance** | Yes, every expiration | None |
| **User dependency** | Tied to user account | Organization-level |
| **Permission scope** | Broad (entire repo) | Granular (only secrets) |
| **Audit trail** | Limited | Full GitHub audit log |
| **Token storage** | In repository secrets | Generated on-demand |
| **Revocation impact** | Breaks all workflows | None (auto-regenerated) |
| **Best for** | Personal projects | Team/Enterprise |

## Troubleshooting

### Error: "Failed to generate installation token"

**Causes**:
1. App ID is incorrect
2. Installation ID is incorrect  
3. Private key is malformed

**Solution**:
```powershell
# Verify App ID
gh api /app --jq .id

# Verify Installation ID (requires gh CLI authenticated)
gh api /app/installations --jq '.[0].id'

# Check private key format
Get-Content path\to\key.pem | Select-Object -First 1
# Should output: -----BEGIN RSA PRIVATE KEY-----
```

### Error: "Insufficient permissions"

**Cause**: App doesn't have Secrets permission

**Solution**:
1. Go to: https://github.com/settings/apps/[APP-NAME]/permissions
2. Update **Repository permissions** → **Secrets** → **Read and write**
3. Click **Save changes**
4. Approve the permission change when prompted

### Error: "App not installed on repository"

**Cause**: App is not installed on the target repository

**Solution**:
1. Go to: https://github.com/settings/installations
2. Click **Configure** next to your app
3. Add the repository to the installation

### App token works but still seeing "403 Forbidden"

**Cause**: Rate limiting or repository visibility issues

**Solution**:
```powershell
# Check rate limit
gh api /rate_limit

# Verify app has access to repo
gh api /repos/pavanthakur/XYDataLabs.OrderProcessingSystem/installation
```

## Advanced: Multi-Repository Setup

For organizations with multiple repositories:

1. **Create one GitHub App** for the entire organization
2. **Install it organization-wide** or on multiple repositories
3. **Each repository can use the same app** (same App ID and Private Key)
4. **Different Installation IDs** if installed per-repo, or same ID if org-wide

### Organization-wide Installation

```powershell
# Organization-level installation (one-time setup)
# Benefits:
# - Single installation for all repos
# - New repos automatically get access
# - Centralized permission management

# Setup:
# 1. Create app at org level: https://github.com/organizations/[ORG]/settings/apps
# 2. Install on "All repositories"
# 3. All repos share same GH_APP_* secrets (can use org secrets)
```

### Organization Secrets (Recommended)

Instead of adding secrets to each repository:

1. Go to: https://github.com/organizations/[ORG-NAME]/settings/secrets/actions
2. Create organization secrets:
   - `APP_ID`
   - `APP_INSTALLATION_ID`
   - `APP_PRIVATE_KEY`
3. Set **Repository access** to "Selected repositories" or "All repositories"
4. All repos automatically inherit these secrets

## Alternative: Fine-Grained PAT (Temporary Solution)

If you can't use GitHub App immediately, use fine-grained PATs with longer expiration:

1. Go to: https://github.com/settings/tokens?type=beta
2. Click **Generate new token** (fine-grained)
3. Set:
   - **Expiration**: Custom (max 1 year)
   - **Repository access**: Only select repositories
   - **Permissions**: Secrets (Read and write)
4. Set a calendar reminder to renew before expiration

**Still requires manual renewal**, but:
- ✅ Longer expiration (up to 1 year)
- ✅ More granular permissions
- ✅ Can be scoped to specific repos

## Recommendation

**For Production/Enterprise**: Use **GitHub App** (zero maintenance)  
**For Personal Projects**: Use **Fine-grained PAT** (set 1-year expiration with reminder)  
**For Quick Testing**: Use **Manual secret configuration** (no automation)

## References

- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [Creating GitHub Apps](https://docs.github.com/en/apps/creating-github-apps)
- [Authenticating with GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app)
- [GitHub App Permissions](https://docs.github.com/en/rest/overview/permissions-required-for-github-apps)
- [Fine-grained PATs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token#creating-a-fine-grained-personal-access-token)
