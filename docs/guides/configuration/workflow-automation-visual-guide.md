# Visual Guide: Complete Workflow Automation

## 🎯 What You Get

```
┌──────────────────────────────────────────────────────┐
│  ONE-TIME SETUP (15 minutes)                         │
│  ↓                                                    │
│  ZERO MAINTENANCE FOREVER                            │
│  ↓                                                    │
│  FULL AUTOMATION                                     │
└──────────────────────────────────────────────────────┘
```

---

## 📊 Complete Automation Flow

### First-Time Setup

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: Azure OIDC Setup (Automated)                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Workflow Inputs:                                               │
│  ┌────────────────────────────────────────────────┐            │
│  │ Environment: all                               │            │
│  │ Setup Azure OIDC: ✅ TRUE                      │            │
│  │ Setup GitHub App: ☑️  TRUE (checks status)     │            │
│  │ Configure secrets: ❌ false                     │            │
│  │ Bootstrap infra: ❌ false                       │            │
│  └────────────────────────────────────────────────┘            │
│                                                                  │
│  Workflow Actions:                                              │
│  • Runs setup-github-oidc.ps1                                   │
│  • Creates Azure AD app "GitHub-Actions-OIDC"                   │
│  • Sets up federated credentials for:                           │
│    - dev branch                                                 │
│    - staging branch                                             │
│    - main branch                                                │
│    - dev environment                                            │
│    - staging environment                                        │
│    - prod environment                                           │
│                                                                  │
│  Outputs:                                                        │
│  ✅ AZUREAPPSERVICE_CLIENTID                                     │
│  ✅ AZUREAPPSERVICE_TENANTID                                     │
│  ✅ AZUREAPPSERVICE_SUBSCRIPTIONID                               │
│                                                                  │
│  Time: 3 minutes                                                │
└─────────────────────────────────────────────────────────────────┘

                            ↓

┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: GitHub App Status Check (Automated)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Workflow Checks:                                               │
│  • APP_ID secret exists?                                      │
│  • APP_INSTALLATION_ID secret exists?                         │
│  • APP_PRIVATE_KEY secret exists?                             │
│                                                                  │
│  IF ALL EXIST:                                                  │
│  ✅ "GitHub App already configured"                              │
│  ✅ Skip to Step 3                                               │
│                                                                  │
│  IF MISSING:                                                    │
│  ⚠️  "GitHub App not configured"                                 │
│  📋 Display setup instructions in workflow log                   │
│  🔗 Link to quick-setup-github-app.md                            │
│                                                                  │
│  Time: 10 seconds                                               │
└─────────────────────────────────────────────────────────────────┘

                            ↓

┌─────────────────────────────────────────────────────────────────┐
│ STEP 2.5: GitHub App Manual Setup (IF NEEDED)                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ⏱️  One-Time Manual Step (5 minutes)                            │
│                                                                  │
│  Actions to take:                                               │
│  ┌────────────────────────────────────────────────┐            │
│  │ 1. Create App:                                 │            │
│  │    https://github.com/settings/apps/new        │            │
│  │    • Name: OrderProcessingSystem-SecretManager │            │
│  │    • Permissions: Secrets (read/write)         │            │
│  │                                                 │            │
│  │ 2. Generate Private Key                        │            │
│  │    • Click "Generate a private key"            │            │
│  │    • Save .pem file                            │            │
│  │                                                 │            │
│  │ 3. Install App                                 │            │
│  │    • Install on repository                     │            │
│  │    • Copy Installation ID from URL             │            │
│  │                                                 │            │
│  │ 4. Add Secrets                                 │            │
│  │    • APP_ID                                 │            │
│  │    • APP_INSTALLATION_ID                    │            │
│  │    • APP_PRIVATE_KEY                        │            │
│  └────────────────────────────────────────────────┘            │
│                                                                  │
│  ✨ After this: NEVER NEEDED AGAIN                               │
│                                                                  │
│  Time: 5 minutes (one-time)                                     │
└─────────────────────────────────────────────────────────────────┘

                            ↓

┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: Configure Secrets (Automated)                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Workflow Inputs:                                               │
│  ┌────────────────────────────────────────────────┐            │
│  │ Configure secrets: ✅ TRUE                      │            │
│  └────────────────────────────────────────────────┘            │
│                                                                  │
│  Workflow Actions:                                              │
│  1. Check GitHub App credentials ✅                              │
│  2. Generate installation token                                 │
│     • Token valid for 1 hour                                    │
│     • Auto-generated on every run                               │
│     • No expiration maintenance!                                │
│  3. Set repository secrets:                                     │
│     • AZUREAPPSERVICE_CLIENTID ✅                                │
│     • AZUREAPPSERVICE_TENANTID ✅                                │
│     • AZUREAPPSERVICE_SUBSCRIPTIONID ✅                          │
│  4. Set environment secrets (dev/staging/prod) ✅                │
│                                                                  │
│  Authentication:                                                │
│  🔐 GitHub App (preferred) or PAT (fallback)                     │
│                                                                  │
│  Time: 1 minute                                                 │
└─────────────────────────────────────────────────────────────────┘

                            ↓

┌─────────────────────────────────────────────────────────────────┐
│ STEP 4: Bootstrap Infrastructure (Automated)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Workflow Inputs:                                               │
│  ┌────────────────────────────────────────────────┐            │
│  │ Bootstrap infrastructure: ✅ TRUE               │            │
│  │ Enable validation: ✅ TRUE                      │            │
│  └────────────────────────────────────────────────┘            │
│                                                                  │
│  Workflow Actions:                                              │
│  • Creates resource groups (dev/staging/prod)                   │
│  • Deploys App Services                                         │
│  • Configures App Service settings                             │
│  • Sets up Application Insights                                │
│  • Configures deployment slots                                 │
│  • Enables pre-deployment validation                            │
│                                                                  │
│  Time: 5-10 minutes                                             │
└─────────────────────────────────────────────────────────────────┘

                            ↓

┌─────────────────────────────────────────────────────────────────┐
│ ✅ SETUP COMPLETE - FULLY AUTOMATED FOREVER                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Ongoing Usage (100% Automated)

```
┌──────────────────────┐
│  CODE CHANGES        │
│  • Edit code         │
│  • Git commit        │
│  • Git push          │
└──────────┬───────────┘
           │
           ↓
┌─────────────────────────────────────────────────────────────┐
│  AUTOMATIC WORKFLOW TRIGGER                                 │
│                                                             │
│  Branch → Environment Mapping:                              │
│  ┌───────────────────────────────────────────────┐         │
│  │ dev branch     → dev environment              │         │
│  │ staging branch → staging environment          │         │
│  │ main branch    → prod environment             │         │
│  └───────────────────────────────────────────────┘         │
│                                                             │
│  Workflow Steps (Automated):                               │
│  1. ✅ Build application                                     │
│  2. ✅ Run unit tests                                        │
│  3. ✅ Authenticate to Azure (OIDC)                          │
│  4. ✅ Deploy to App Service                                 │
│  5. ✅ Health check                                          │
│  6. ✅ Smoke tests                                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
           │
           ↓
┌──────────────────────┐
│  DEPLOYED ✨         │
│  • Live in Azure     │
│  • Automatically     │
│  • No manual steps   │
└──────────────────────┘
```

---

## 🔐 Token Management: Before vs After

### Before (PAT Approach)

```
Day 1:
┌─────────────────────────────────┐
│ Create PAT                      │
│ • Set expiration (max 1 year)   │
│ • Grant repo scope              │
│ • Add as GH_PAT secret          │
└─────────────────────────────────┘

Day 30-365: (calendar reminder)
┌─────────────────────────────────┐
│ ⚠️ PAT EXPIRING SOON             │
│ • Create new PAT                │
│ • Update GH_PAT secret          │
│ • Update calendar reminder      │
│ • Hope you don't forget         │
└─────────────────────────────────┘

If forgotten:
┌─────────────────────────────────┐
│ ❌ ALL WORKFLOWS BREAK           │
│ • Deployments fail              │
│ • Emergency fix needed          │
│ • Production impact possible    │
└─────────────────────────────────┘
```

### After (GitHub App Approach)

```
Day 1: (one-time setup)
┌─────────────────────────────────┐
│ Create GitHub App               │
│ • Add GH_APP_* secrets          │
│ • Done forever                  │
└─────────────────────────────────┘

Every workflow run:
┌─────────────────────────────────┐
│ ✅ AUTO-GENERATE TOKEN           │
│ • Token generated on-demand     │
│ • Valid for 1 hour              │
│ • Auto-refreshed next run       │
│ • No expiration to track        │
└─────────────────────────────────┘

Forever:
┌─────────────────────────────────┐
│ ✨ ZERO MAINTENANCE              │
│ • No reminders needed           │
│ • No manual renewals            │
│ • Never breaks                  │
└─────────────────────────────────┘
```

---

## 📈 Workflow Decision Matrix

```
┌────────────────────────────────────────────────────────────┐
│ WHICH WORKFLOW INPUT TO USE?                               │
├────────────────────────────────────────────────────────────┤
│                                                            │
│ First-Time Setup:                                          │
│ ┌────────────────────────────────────────────┐            │
│ │ Environment: all                           │            │
│ │ Setup Azure OIDC: ✅                        │            │
│ │ Setup GitHub App: ✅                        │            │
│ │ Configure secrets: ✅                       │            │
│ │ Bootstrap infrastructure: ✅                │            │
│ │ Enable validation: ✅                       │            │
│ └────────────────────────────────────────────┘            │
│                                                            │
│ Add New Environment:                                       │
│ ┌────────────────────────────────────────────┐            │
│ │ Environment: [new-env]                     │            │
│ │ Setup Azure OIDC: ❌                        │            │
│ │ Setup GitHub App: ❌                        │            │
│ │ Configure secrets: ❌                       │            │
│ │ Bootstrap infrastructure: ✅                │            │
│ │ Enable validation: ✅                       │            │
│ └────────────────────────────────────────────┘            │
│                                                            │
│ Reconfigure Secrets Only:                                 │
│ ┌────────────────────────────────────────────┐            │
│ │ Environment: all                           │            │
│ │ Setup Azure OIDC: ❌                        │            │
│ │ Setup GitHub App: ❌                        │            │
│ │ Configure secrets: ✅                       │            │
│ │ Bootstrap infrastructure: ❌                │            │
│ │ Enable validation: ❌                       │            │
│ └────────────────────────────────────────────┘            │
│                                                            │
│ Normal Operation:                                          │
│ ┌────────────────────────────────────────────┐            │
│ │ Just push code!                            │            │
│ │ Workflows automatically triggered          │            │
│ └────────────────────────────────────────────┘            │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

---

## 🎯 Automation Levels Compared

```
┌─────────────────────────┬──────────────┬──────────────┬──────────────┐
│ Feature                 │ Manual Only  │ PAT          │ GitHub App   │
├─────────────────────────┼──────────────┼──────────────┼──────────────┤
│ Secret Setup            │ ❌ Manual     │ ⚠️ Semi-auto │ ✅ Automated  │
│ Token Expiration        │ N/A          │ ❌ Yes       │ ✅ Never      │
│ Maintenance Required    │ ❌ Always     │ ⚠️ Periodic  │ ✅ Never      │
│ Workflow Breakage Risk  │ ❌ High       │ ⚠️ Medium    │ ✅ None       │
│ Setup Time              │ 10 min       │ 7 min        │ 15 min       │
│ Ongoing Time/Year       │ 60 min       │ 15 min       │ ✅ 0 min      │
│ Security Level          │ Low          │ Medium       │ ✅ High       │
│ Audit Trail             │ None         │ Limited      │ ✅ Full       │
│ Best For                │ Testing      │ Personal     │ ✅ Production │
└─────────────────────────┴──────────────┴──────────────┴──────────────┘
```

---

## 📚 Quick Reference

### Workflow Inputs Explained

| Input | Purpose | When to Use |
|-------|---------|-------------|
| **Setup Azure OIDC** | Creates Azure AD app and federated credentials | First-time setup only |
| **Setup GitHub App** | Checks if GitHub App configured, provides setup guide | First-time setup only |
| **Configure secrets** | Sets Azure credentials as GitHub secrets | After OIDC/App setup |
| **Bootstrap infrastructure** | Creates Azure resources (App Services, etc.) | First-time or new environments |
| **Enable validation** | Activates pre-deployment checks | During bootstrap |

### Secret Reference

| Secret | Set By | Purpose |
|--------|--------|---------|
| **APP_ID** | Manual (one-time) | GitHub App authentication |
| **APP_INSTALLATION_ID** | Manual (one-time) | GitHub App installation |
| **APP_PRIVATE_KEY** | Manual (one-time) | GitHub App private key |
| **AZUREAPPSERVICE_CLIENTID** | Workflow (automated) | Azure OIDC client ID |
| **AZUREAPPSERVICE_TENANTID** | Workflow (automated) | Azure AD tenant ID |
| **AZUREAPPSERVICE_SUBSCRIPTIONID** | Workflow (automated) | Azure subscription ID |

### Documentation Links

- **Quick Setup**: [quick-setup-github-app.md](./quick-setup-github-app.md)
- **Complete Guide**: [quick-start-azure-bootstrap.md](../deployment/quick-start-azure-bootstrap.md)
- **GitHub App Details**: [github-app-authentication.md](./github-app-authentication.md)
- **Troubleshooting**: All docs include troubleshooting sections

---

## ✨ The Result

```
┌──────────────────────────────────────────────────────┐
│                                                      │
│  15 MINUTES SETUP                                    │
│           ↓                                          │
│  ZERO MAINTENANCE                                    │
│           ↓                                          │
│  FOREVER AUTOMATED                                   │
│                                                      │
│  🎉 PUSH CODE → AUTO-DEPLOY                          │
│                                                      │
└──────────────────────────────────────────────────────┘
```
