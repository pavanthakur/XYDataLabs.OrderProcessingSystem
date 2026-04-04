# GitHub Configuration Workflow Separation - Architecture

## Before: Monolithic Bootstrap Workflow

```
azure-bootstrap.yml (3,740 lines)
├── validate-inputs
├── setup-oidc
├── setup-github-app          ← 194 lines
├── configure-secrets          ← 720 lines  
├── validate-final-configuration ← 178 lines
├── pre-validate-prerequisites  ← removed (Phase 3 obsoleted)
├── bootstrap-dev
├── bootstrap-staging
├── bootstrap-prod
├── enable-validation           ← removed (Phase 3 obsoleted)
├── summary
└── trigger-deployments

Total GitHub config: ~1,092 lines in main workflow
```

**Issues:**
- ❌ Long, complex workflow (3,740 lines)
- ❌ Difficult to debug GitHub configuration issues
- ❌ No independent execution tracking
- ❌ Hard to test secret configuration separately
- ❌ Mixed concerns (infrastructure + GitHub config)

---

## After: Separated Workflows

The original monolithic `azure-bootstrap.yml` was first split to extract GitHub
configuration into `configure-github-secrets.yml`, then **further split** into two
top-level workflows to fully separate one-time setup from day-to-day operations:

### Azure Initial Setup (one-time)

```
azure-initial-setup.yml (~767 lines)
├── validate-inputs
├── setup-github-app             ← Phase 0
├── setup-oidc                   ← Phase 1a
│   └── outputs: clientId, tenantId, subscriptionId
├── configure-github-secrets     ← Phase 1b (workflow_call)
│   └── calls: configure-github-secrets.yml
│       └── passes: environment, OIDC outputs, flags
└── summary

Run once per repository. Covers GitHub App + OIDC + secrets.
```

### Azure Bootstrap & Deploy (day-to-day)

```
azure-bootstrap.yml (significantly reduced)
├── check-trigger
├── validate-inputs
├── bootstrap-dev                ← Phase 2
├── bootstrap-staging            ← Phase 2
├── bootstrap-prod               ← Phase 2
├── cleanup-dev                  ← Phase X (⚠️ destructive)
├── cleanup-staging              ← Phase X (⚠️ destructive)
├── cleanup-prod                 ← Phase X (⚠️ destructive)
├── summary
└── trigger-deployments          ← Dispatches API/UI deploy workflows

Day-to-day: infrastructure provisioning + app deployment.
```

### Dedicated GitHub Secrets Workflow

```
configure-github-secrets.yml (670 lines)
├── validate-inputs
├── setup-github-app
│   ├── Check existing configuration
│   └── Provide setup guidance
├── configure-secrets
│   ├── Generate GitHub App token
│   ├── Set repository secrets
│   └── Set environment secrets (dev/staging/prod)
└── validate-configuration
    ├── Check setup status
    └── Create summary

Can be triggered:
  - Manually (workflow_dispatch)
  - From initial-setup (workflow_call)
  - From other workflows
```

---

## Architecture Flow

### Integrated Execution (Initial Setup — one-time)

```
┌─────────────────────────────────────────────────────────────┐
│                azure-initial-setup.yml                       │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  1. validate-inputs                                          │
│       ↓                                                       │
│  2. setup-github-app (Phase 0)                               │
│       ↓                                                       │
│  3. setup-oidc (Phase 1a)                                    │
│       ├─ Creates Azure OIDC app                              │
│       └─ Outputs: clientId, tenantId, subscriptionId        │
│       ↓                                                       │
│  4. configure-github-secrets (Phase 1b, workflow_call)       │
│       │                                                       │
│       ├──→ ┌────────────────────────────────────────┐       │
│       │    │  configure-github-secrets.yml          │       │
│       │    ├────────────────────────────────────────┤       │
│       │    │  • setup-github-app                    │       │
│       │    │  • configure-secrets                   │       │
│       │    │  • validate-configuration              │       │
│       │    └────────────────────────────────────────┘       │
│       │                                                       │
│       └─ Returns: setup-result, secrets-result               │
│       ↓                                                       │
│  5. summary                                                   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Integrated Execution (Bootstrap & Deploy — day-to-day)

```
┌─────────────────────────────────────────────────────────────┐
│                   azure-bootstrap.yml                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  1. validate-inputs                                          │
│       ↓                                                       │
│  2. bootstrap-dev/staging/prod (Phase 2)                     │
│       ↓                                                       │
│  3. cleanup-dev/staging/prod (⚠️ Phase X, if enabled)        │
│       ↓                                                       │
│  4. summary                                                   │
│       ↓                                                       │
│  5. trigger-deployments (dispatches API/UI workflows)        │
│                                                               │
└─────────────────────────────────────────────────────────────┘

Prerequisite: Azure Initial Setup must have run at least once.
```

### Independent Execution (Troubleshooting)

```
┌─────────────────────────────────────────────────────────────┐
│            configure-github-secrets.yml                      │
│                 (Standalone Execution)                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Manual Trigger → Actions → Configure GitHub Secrets        │
│                                                               │
│  Inputs:                                                      │
│    • environment: dev/staging/prod/all                       │
│    • setupGitHubApp: true/false                              │
│    • configureSecrets: true/false                            │
│    • clientId, tenantId, subscriptionId (optional)           │
│                                                               │
│  Jobs:                                                        │
│    1. validate-inputs                                         │
│    2. setup-github-app (optional)                            │
│    3. configure-secrets                                       │
│    4. validate-configuration                                  │
│                                                               │
│  Use Cases:                                                   │
│    • Reconfigure secrets for specific environment            │
│    • Validate GitHub App setup                               │
│    • Troubleshoot secret configuration issues                │
│    • Update secrets after OIDC changes                       │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### Context Passing (Initial Setup → GitHub Secrets)

```
azure-initial-setup.yml
     │
     │ setup-oidc job outputs:
     ├─ clientId: "abc123..."
     ├─ tenantId: "xyz789..."
     └─ subscriptionId: "sub456..."
     │
     ↓ workflow_call with inputs
     │
configure-github-secrets.yml
     │
     ├─ Receives: environment, setupGitHubApp, configureSecrets
     ├─ Receives: clientId, tenantId, subscriptionId
     │
     ↓ Uses credentials to:
     │
     ├─ Generate GitHub App token
     ├─ Set repository secrets:
     │  ├─ AZUREAPPSERVICE_CLIENTID = clientId
     │  ├─ AZUREAPPSERVICE_TENANTID = tenantId
     │  └─ AZUREAPPSERVICE_SUBSCRIPTIONID = subscriptionId
     │
     └─ Set environment secrets (per env):
        ├─ dev/AZUREAPPSERVICE_CLIENTID = clientId
        ├─ dev/AZUREAPPSERVICE_TENANTID = tenantId
        ├─ dev/AZUREAPPSERVICE_SUBSCRIPTIONID = subscriptionId
        ├─ staging/* (same pattern)
        └─ prod/* (same pattern)
     │
     ↓ Returns outputs:
     │
     ├─ setup-result: success/skipped/failure
     ├─ secrets-result: success/failure
     └─ validation-result: success/failure
     │
     ↓ Back to initial-setup
     │
azure-initial-setup.yml
     │
     └─ Summary job reports: setup-result, secrets-result
```

---

## Execution Tracking

### Before (Monolithic)

```
GitHub Actions UI:
├── azure-bootstrap.yml
    └── Single workflow run
        ├── All jobs grouped together
        └── Hard to isolate GitHub config issues
```

### After (Separated — Two Top-Level Workflows)

```
GitHub Actions UI:
├── azure-initial-setup.yml          ← One-time (Phase 0/1a/1b)
│   └── Setup workflow run
│       ├── setup-github-app
│       ├── setup-oidc
│       ├── configure-github-secrets ← Calls reusable workflow
│       └── summary
│
├── azure-bootstrap.yml               ← Day-to-day (Phase 2/X/Deploy)
│   └── Bootstrap workflow run
│       ├── bootstrap-dev/staging/prod
│       ├── cleanup-dev/staging/prod
│       ├── summary
│       └── trigger-deployments
│
├── configure-github-secrets.yml       ← Reusable / standalone
    └── Separate workflow run (nested or independent)
        ├── setup-github-app
        ├── configure-secrets
        └── validate-configuration
```

**Benefits:**
- ✅ Clear separation in UI — setup vs day-to-day
- ✅ Easy to find GitHub config runs
- ✅ Can debug independently
- ✅ Similar to API/UI deployment tracking

---

## Comparison Matrix

| Aspect | Before (Monolithic) | After (Separated) |
|--------|-------------------|------------------|
| **Lines of code** | 3,740 | ~767 initial-setup + reduced bootstrap + 670 config |
| **GitHub config lines** | 1,092 in main | 670 in separate workflow + ~767 in initial-setup |
| **Readability** | ❌ Long, complex | ✅ Modular, focused |
| **Independent execution** | ❌ No | ✅ Yes |
| **Troubleshooting** | ❌ Difficult | ✅ Easy |
| **Execution tracking** | ❌ Single workflow | ✅ Separate tracking |
| **Testing** | ❌ Must run full bootstrap | ✅ Can test independently |
| **Reusability** | ❌ Embedded | ✅ Can call from other workflows |
| **Maintainability** | ❌ Mixed concerns | ✅ Clear separation |
| **Context passing** | N/A | ✅ Via inputs/outputs |

---

## Benefits Summary

### 1. Modularity
- GitHub configuration is self-contained
- Clear separation of concerns
- Easier to understand and modify

### 2. Independent Execution
- Can run separately for troubleshooting
- Test secret configuration without full bootstrap
- Reconfigure specific environments independently

### 3. Better Tracking
- Separate workflow runs in Actions UI
- Similar to API/UI deployment workflows
- Easy to find and review GitHub config runs

### 4. Maintainability
- One-time setup fully separated from day-to-day operations
- Each workflow has focused responsibility
- Easier to debug and fix issues

### 5. Flexibility
- Can be called from multiple workflows
- Supports both manual and automated triggers
- Flexible input parameters

### 6. Context Preservation
- OIDC credentials passed from bootstrap
- Branch and environment context maintained
- Results available to downstream jobs

---

## Migration Impact

### Backward Compatibility
- ✅ Existing functionality preserved
- ✅ Same inputs to bootstrap workflow
- ✅ Same secret configuration behavior
- ✅ Same environment setup

### New Capabilities
- ✅ Can troubleshoot GitHub config independently
- ✅ Can reconfigure secrets without full bootstrap
- ✅ Better execution visibility
- ✅ Easier debugging

### Breaking Changes
- ❌ None - fully backward compatible

---

## Usage Patterns

### Pattern 1: First-Time Complete Setup
```
1. Run azure-initial-setup.yml
   - setupGitHubApp: true (Phase 0 — shows guidance)
   - setupOidc: true (Phase 1a)
   - configureSecrets: true (Phase 1b)

→ Automatically calls configure-github-secrets.yml
→ OIDC + secrets configured

2. Run azure-bootstrap.yml
   - bootstrapInfra: true (Phase 2)
   - deployApi / deployUi: true

→ Provisions infrastructure and deploys apps
```

### Pattern 2: Troubleshoot Secret Configuration
```
1. Run configure-github-secrets.yml directly
   - environment: staging
   - setupGitHubApp: false
   - configureSecrets: true
   - Provide OIDC credentials

→ Reconfigures secrets for staging only
→ No need to run full bootstrap
```

### Pattern 3: Validate GitHub App Setup
```
1. Run configure-github-secrets.yml directly
   - setupGitHubApp: true
   - configureSecrets: false

→ Checks current GitHub App configuration
→ Provides setup guidance if needed
```

### Pattern 4: Update After OIDC Changes
```
1. Update Azure OIDC app
2. Run configure-github-secrets.yml
   - environment: all
   - configureSecrets: true
   - New OIDC credentials

→ Updates all environment secrets
→ No infrastructure changes needed
```

---

**Document Version**: 2.0
**Last Updated**: 2026-03-18
**Migration Completed**: ✅ Yes (further split: initial-setup + bootstrap & deploy)

---

## 🗂️ Branch → Environment Mapping Reference

| Branch    | Environment | Azure Resource Group          | OIDC Subject                                        |
|-----------|-------------|-------------------------------|-----------------------------------------------------|
| `dev`     | `dev`       | `rg-orderprocessing-dev`      | `repo:pavanthakur/.../ref:refs/heads/dev`           |
| `staging` | `staging`   | `rg-orderprocessing-staging`  | `repo:pavanthakur/.../ref:refs/heads/staging`       |
| `main`    | `prod`      | `rg-orderprocessing-prod`     | `repo:pavanthakur/.../ref:refs/heads/main`          |

### Environment Secrets Per Environment

Each environment (`dev`, `staging`, `prod`) holds its own isolated set:
- `GH_APP_ID` / `GH_APP_PRIVATE_KEY`
- `AZUREAPPSERVICE_CLIENTID`
- `AZUREAPPSERVICE_TENANTID`
- `AZUREAPPSERVICE_SUBSCRIPTIONID`

### Workflow Environment Selection Pattern
```yaml
environment: ${{ github.ref == 'refs/heads/main' && 'prod' || github.ref == 'refs/heads/staging' && 'staging' || 'dev' }}
```
This pattern is used in `deploy-api-to-azure.yml` and `deploy-ui-to-azure.yml` to automatically select the correct environment based on branch.
