# Azure Deployment Documentation - Navigation Guide

**Purpose**: Central navigation hub for all Azure deployment documentation  
**Last Updated**: November 17, 2025  
**Audience**: Developers, DevOps Engineers, Junior Developers, Code Reviewers

---

## 🚀 Quick Start - Where to Begin?

### For First-Time Users
Start here if you're deploying to Azure for the first time:

1. **Read**: [AZURE_DEPLOYMENT_GUIDE.md](./AZURE_DEPLOYMENT_GUIDE.md) - Sections: Overview, Prerequisites, Quick Start
2. **Execute**: Run the bootstrap script (single command deployment)
3. **Verify**: Follow the verification checklist

**Estimated Time**: 30 minutes reading + 5-20 minutes execution

---

### For Junior Developers / Code Reviewers
Start here if you need to understand the complete script flow:

1. **Read**: [BOOTSTRAP_SCRIPT_FLOW.md](./BOOTSTRAP_SCRIPT_FLOW.md) - Complete step-by-step breakdown
2. **Review**: Check line-by-line execution sequence with code examples
3. **Validate**: Use verification checklist to confirm expected behavior

**Estimated Time**: 1-2 hours for thorough understanding

---

### For Operations/DevOps Teams
Start here if you're managing production deployments:

1. **Read**: [AZURE_DEPLOYMENT_GUIDE.md](./AZURE_DEPLOYMENT_GUIDE.md) - Sections: Enterprise Strategy, Performance Optimizations
2. **Configure**: Multi-environment setup (dev, stg, prod)
3. **Monitor**: Set up Application Insights and monitoring

**Estimated Time**: 45 minutes reading + setup time

---

### For Troubleshooting
Start here if you're encountering issues:

1. **Check**: [BOOTSTRAP_SCRIPT_FLOW.md](./BOOTSTRAP_SCRIPT_FLOW.md#troubleshooting-guide) - Troubleshooting section
2. **Verify**: Run verification commands from checklist
3. **Debug**: Enable debug mode and review logs

**Estimated Time**: 10-30 minutes depending on issue

---

## 📚 Document Hierarchy

### Overview Diagram

```
02-Azure-Learning-Guides/
│
├── README.md (You are here - Start here for navigation)
│   ├── Quick Start guides by role
│   ├── Document hierarchy
│   └── Learning paths
│
├── AZURE_DEPLOYMENT_GUIDE.md (Main deployment strategy)
│   ├── Architecture & Overview
│   ├── Performance Optimizations ⚡
│   ├── Enterprise Multi-Environment Strategy
│   ├── Script Reference
│   ├── Simplified Workflow (Recommended)
│   ├── Alternative Manual Workflow
│   └── Production Best Practices
│
├── BOOTSTRAP_SCRIPT_FLOW.md (Detailed execution flow)
│   ├── Complete Step-by-Step Flow (with line numbers)
│   ├── Phase-by-Phase Breakdown
│   ├── Verification Checklist ✅
│   ├── Troubleshooting Guide 🔧
│   └── Debug Mode Instructions
│
├── APPLICATION_INSIGHTS_SETUP.md (Monitoring setup)
│   ├── Manual Application Insights configuration
│   ├── Connection string setup
│   └── Telemetry configuration
│
└── DEPLOYMENT_EXERCISES.md (Hands-on tutorials)
    ├── Exercise-based learning
    ├── Step-by-step deployment walkthroughs
    └── Common scenarios and solutions
```

---

## 📖 Detailed Document Descriptions

### 1. AZURE_DEPLOYMENT_GUIDE.md
**Primary Purpose**: Complete Azure deployment strategy and workflow guide

| Section | Purpose | Audience | Time |
|---------|---------|----------|------|
| **Overview & Architecture** | Understand deployed resources and architecture | Everyone | 5 min |
| **Performance Optimizations** | Learn about script optimizations and improvements | DevOps, Reviewers | 10 min |
| **Enterprise Strategy** | Multi-environment setup and best practices | DevOps, Architects | 15 min |
| **Script Reference** | Understand available automation scripts | Developers | 10 min |
| **Simplified Workflow** | Single-command deployment (recommended) | Everyone | 5 min |
| **Alternative Manual Workflow** | Step-by-step manual OIDC setup | Advanced Users | 10 min |

**Key Features**:
- ✅ High-level strategy and concepts
- ✅ Performance comparison (old vs new)
- ✅ Single-command deployment instructions
- ✅ Enterprise multi-environment patterns
- ✅ OIDC authentication setup
- ✅ RBAC and security best practices

**When to Use**:
- Planning initial deployment
- Understanding overall strategy
- Configuring multi-environment setup
- Learning about optimizations

---

### 2. BOOTSTRAP_SCRIPT_FLOW.md
**Primary Purpose**: Line-by-line execution flow for code review and validation

| Section | Purpose | Audience | Time |
|---------|---------|----------|------|
| **Quick Overview** | Understand what the script does | Everyone | 3 min |
| **Prerequisites** | Verify required tools and permissions | Everyone | 5 min |
| **Execution Command** | Learn all parameters and syntax | Developers | 5 min |
| **Complete Step-by-Step Flow** | Follow exact execution sequence | Reviewers, Juniors | 30 min |
| **Detailed Phase Breakdown** | Deep dive into each phase | Reviewers | 20 min |
| **Verification Checklist** | Post-execution validation | Everyone | 10 min |
| **Troubleshooting Guide** | Resolve common issues | Everyone | As needed |

**Key Features**:
- ✅ Line-by-line code explanations
- ✅ Exact PowerShell commands shown
- ✅ Timeline estimates per phase
- ✅ Parallel execution diagrams
- ✅ Error handling strategies
- ✅ Comprehensive verification commands
- ✅ 7+ common issues with resolutions

**When to Use**:
- Code review and validation
- Understanding script internals
- Training junior developers
- Troubleshooting execution issues
- Auditing automation workflow

---

### 3. APPLICATION_INSIGHTS_SETUP.md
**Primary Purpose**: Manual Application Insights configuration (legacy/reference)

**Status**: ⚠️ Partially superseded by bootstrap script automation

**When to Use**:
- Manual Application Insights setup needed
- Bootstrap script Application Insights creation failed
- Custom Application Insights configuration required
- Reference for understanding connection strings

**Note**: The bootstrap script now automatically creates Application Insights and configures connection strings. This document is retained for manual scenarios.

---

### 4. DEPLOYMENT_EXERCISES.md
**Primary Purpose**: Hands-on learning exercises and tutorials

**When to Use**:
- Learning Azure deployment concepts
- Practicing manual deployment steps
- Understanding individual Azure CLI commands
- Step-by-step guided tutorials

**Note**: Some exercises may reference older manual approaches. Refer to AZURE_DEPLOYMENT_GUIDE.md for current automated workflow.

---

## 🎯 Learning Paths

### Path 1: Quick Deployment (30 minutes)
**Goal**: Get infrastructure running ASAP

```
1. AZURE_DEPLOYMENT_GUIDE.md
   └─ Read: Overview, Prerequisites (5 min)

2. AZURE_DEPLOYMENT_GUIDE.md
   └─ Read: Simplified Workflow (5 min)

3. Execute bootstrap script (5-20 min)

4. BOOTSTRAP_SCRIPT_FLOW.md
   └─ Use: Verification Checklist (5 min)

5. Add GitHub secrets (5 min)
```

**Outcome**: Fully provisioned infrastructure with OIDC configured

---

### Path 2: Deep Understanding (2-3 hours)
**Goal**: Understand every aspect of the deployment

```
1. AZURE_DEPLOYMENT_GUIDE.md
   └─ Read: Complete document (30 min)

2. BOOTSTRAP_SCRIPT_FLOW.md
   └─ Read: Complete document (60 min)

3. Review actual script code
   └─ Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1 (30 min)

4. Execute with monitoring
   └─ Watch each phase execute (20 min)

5. Post-execution analysis
   └─ Verify all resources in Azure Portal (15 min)
```

**Outcome**: Complete understanding of automation workflow, ready to customize or troubleshoot

---

### Path 3: Enterprise Multi-Environment (1 hour)
**Goal**: Set up dev, staging, production environments

```
1. AZURE_DEPLOYMENT_GUIDE.md
   └─ Read: Enterprise Production Strategy (15 min)

2. AZURE_DEPLOYMENT_GUIDE.md
   └─ Read: Performance Optimizations (10 min)

3. Plan environment strategy
   └─ Define SKUs, regions, RBAC (10 min)

4. Execute bootstrap for all environments (20 min)
   └─ -Environments dev,stg,prod

5. Configure GitHub workflows
   └─ Branch-based deployment (10 min)
```

**Outcome**: Production-ready multi-environment infrastructure with proper isolation

---

### Path 4: Troubleshooting & Debug (As needed)
**Goal**: Resolve deployment issues

```
1. BOOTSTRAP_SCRIPT_FLOW.md
   └─ Navigate to: Troubleshooting Guide (5 min)

2. Identify issue category
   └─ Match to 7 common issues (5 min)

3. Run diagnostic commands
   └─ Use provided verification queries (5 min)

4. Check Azure Portal
   └─ Activity logs, resource status (10 min)

5. Re-run script if needed
   └─ Idempotent - safe to retry (5-20 min)
```

**Outcome**: Issue identified and resolved with minimal downtime

---

## 🔍 Quick Reference - Common Tasks

### Task: Deploy Infrastructure (First Time)

```powershell
# 1. Prerequisites
az login
az account set --subscription "<SUBSCRIPTION_ID>"

# 2. Execute bootstrap script (single command)
./Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1 `
  -BaseName orderprocessing `
  -Location centralindia `
  -Environments dev

# 3. Add GitHub secrets (from clipboard - auto-copied by script)
# Navigate to: https://github.com/{owner}/{repo}/settings/secrets/actions
# Add: AZUREAPPSERVICE_CLIENTID, TENANTID, SUBSCRIPTIONID
```

**Reference**: [AZURE_DEPLOYMENT_GUIDE.md - Simplified Workflow](./AZURE_DEPLOYMENT_GUIDE.md#recommended-end-to-end-sequence-enterprise-multi-environment)

---

### Task: Verify Deployment

```powershell
# Check all resources
az group list --query "[?contains(name, 'orderprocessing')]" --output table
az webapp list --query "[?contains(name, 'orderprocessing')]" --output table

# Verify OIDC setup
./Resources/Azure-Deployment/check-app-registration.ps1

# Test endpoints
Invoke-WebRequest -Uri "https://orderprocessing-api-xyapp-dev.azurewebsites.net"
```

**Reference**: [BOOTSTRAP_SCRIPT_FLOW.md - Verification Checklist](./BOOTSTRAP_SCRIPT_FLOW.md#verification-checklist)

---

### Task: Troubleshoot Failed Deployment

```powershell
# Check script output for specific error
# Look for [FAIL] or [WARN] messages

# Check Azure activity logs
az monitor activity-log list --resource-group rg-orderprocessing-dev --query "[?level=='Error']"

# Verify permissions
az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv)

# Re-run script (idempotent - safe)
./Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1 -BaseName orderprocessing -Location centralindia -Environments dev
```

**Reference**: [BOOTSTRAP_SCRIPT_FLOW.md - Troubleshooting Guide](./BOOTSTRAP_SCRIPT_FLOW.md#troubleshooting-guide)

---

### Task: Add Additional Environment

```powershell
# Add staging environment to existing dev
./Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1 `
  -BaseName orderprocessing `
  -Location centralindia `
  -Environments stg `
  -StgSku B1

# OIDC already configured automatically from `Resources/Azure-Deployment/branch-policy.json` (current defaults: dev, staging, main branches)
```

**Reference**: [AZURE_DEPLOYMENT_GUIDE.md - Enterprise Strategy](./AZURE_DEPLOYMENT_GUIDE.md#enterprise-production-strategy-multi-environment)

---

### Task: Configure GitHub Workflows

```yaml
# Workflow already configured in .github/workflows/
# Just push to trigger deployment:

# Dev environment
git push origin dev

# Staging environment
git push origin staging

# Production environment
git push origin main
```

**Reference**: [AZURE_DEPLOYMENT_GUIDE.md - GitHub Workflow Adjustments](./AZURE_DEPLOYMENT_GUIDE.md#github-workflow-adjustments)

---

## 📊 Document Comparison Matrix

| Feature | AZURE_DEPLOYMENT_GUIDE.md | BOOTSTRAP_SCRIPT_FLOW.md | APPLICATION_INSIGHTS_SETUP.md | DEPLOYMENT_EXERCISES.md |
|---------|---------------------------|--------------------------|-------------------------------|-------------------------|
| **Level** | High-level strategy | Low-level implementation | Specific feature | Tutorial/Practice |
| **Detail** | Conceptual | Line-by-line code | Configuration steps | Step-by-step exercises |
| **Audience** | Everyone | Reviewers, Juniors | Operations | Learners |
| **Use Case** | Planning, Strategy | Code Review, Validation | Manual Config | Training |
| **Length** | ~1300 lines | ~850 lines | ~200 lines | ~500 lines |
| **Code Examples** | High-level | Detailed PowerShell | CLI commands | Mixed |
| **Troubleshooting** | Best practices | 7 common issues | Limited | Exercise-specific |
| **Up-to-Date** | ✅ Nov 2025 | ✅ Nov 2025 | ⚠️ Partially superseded | ⚠️ Some legacy content |

---

## 🎓 Recommended Reading Order

### For Developers (New to Project)
1. **README.md** (this file) - Quick Start section → 5 minutes
2. **AZURE_DEPLOYMENT_GUIDE.md** - Overview through Simplified Workflow → 20 minutes
3. **Execute deployment** → 5-20 minutes
4. **BOOTSTRAP_SCRIPT_FLOW.md** - Verification Checklist → 10 minutes

**Total Time**: ~40-55 minutes to first deployment

---

### For Code Reviewers
1. **README.md** (this file) - Document Hierarchy → 5 minutes
2. **BOOTSTRAP_SCRIPT_FLOW.md** - Complete document → 60 minutes
3. **Review script source** - bootstrap-enterprise-infra.ps1 → 30 minutes
4. **AZURE_DEPLOYMENT_GUIDE.md** - Performance Optimizations → 10 minutes

**Total Time**: ~1 hour 45 minutes for thorough review

---

### For DevOps/Operations
1. **README.md** (this file) - Quick Start for Operations → 5 minutes
2. **AZURE_DEPLOYMENT_GUIDE.md** - Enterprise Strategy → 30 minutes
3. **BOOTSTRAP_SCRIPT_FLOW.md** - Quick Overview, Verification Checklist → 15 minutes
4. **Execute multi-environment deployment** → 20 minutes
5. **Set up monitoring and alerts** → Additional time

**Total Time**: ~1 hour 10 minutes + monitoring setup

---

## 🔗 External Resources

### Azure Documentation
- [Azure App Service Overview](https://docs.microsoft.com/azure/app-service/)
- [Azure CLI Reference](https://docs.microsoft.com/cli/azure/)
- [Azure RBAC Documentation](https://docs.microsoft.com/azure/role-based-access-control/)
- [GitHub Actions for Azure](https://docs.microsoft.com/azure/developer/github/github-actions)

### OIDC & Security
- [OpenID Connect with GitHub Actions](https://docs.github.com/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Azure AD App Registrations](https://docs.microsoft.com/azure/active-directory/develop/quickstart-register-app)
- [Federated Identity Credentials](https://docs.microsoft.com/azure/active-directory/develop/workload-identity-federation)

### PowerShell & Automation
- [PowerShell Background Jobs](https://docs.microsoft.com/powershell/module/microsoft.powershell.core/about/about_jobs)
- [Azure CLI in PowerShell](https://docs.microsoft.com/cli/azure/install-azure-cli-windows)

---

## 🆘 Getting Help

### Internal Resources
1. **Check Troubleshooting Section**: [BOOTSTRAP_SCRIPT_FLOW.md - Troubleshooting](./BOOTSTRAP_SCRIPT_FLOW.md#troubleshooting-guide)
2. **Review Common Issues**: 7 documented scenarios with resolutions
3. **Run Verification Commands**: Automated checks in documentation

### Tools
- **OIDC Verification**: `./Resources/Azure-Deployment/check-app-registration.ps1`
- **Azure Portal**: https://portal.azure.com (Activity logs, Resource health)
- **Azure Service Health**: https://status.azure.com/

### Team Support
- DevOps Team: For infrastructure and deployment issues
- Security Team: For RBAC and permissions issues
- Development Team: For application-specific configuration

---

## 📝 Document Maintenance

### Update Frequency
- **AZURE_DEPLOYMENT_GUIDE.md**: Updated when strategy or workflow changes
- **BOOTSTRAP_SCRIPT_FLOW.md**: Updated when script logic changes
- **README.md**: Updated when new documents added or hierarchy changes

### Last Updated
- **README.md**: November 17, 2025
- **AZURE_DEPLOYMENT_GUIDE.md**: November 17, 2025
- **BOOTSTRAP_SCRIPT_FLOW.md**: November 17, 2025

### Contributing
When updating documentation:
1. Update the "Last Updated" date
2. Update this README.md if hierarchy changes
3. Maintain cross-references between documents
4. Keep line number references accurate in BOOTSTRAP_SCRIPT_FLOW.md

---

## 🎯 Success Criteria

After reading and following this documentation, you should be able to:

- ✅ Deploy complete Azure infrastructure in under 30 minutes
- ✅ Understand the optimized parallel execution workflow
- ✅ Configure GitHub Actions OIDC authentication without manual steps
- ✅ Set up multi-environment deployments (dev, stg, prod)
- ✅ Verify all resources are properly configured
- ✅ Troubleshoot common deployment issues
- ✅ Explain the complete execution flow to team members

---

## 📞 Quick Links

| Document | Purpose | Link |
|----------|---------|------|
| **Main Strategy Guide** | Deployment strategy and workflow | [AZURE_DEPLOYMENT_GUIDE.md](./AZURE_DEPLOYMENT_GUIDE.md) |
| **Detailed Execution Flow** | Line-by-line script breakdown | [BOOTSTRAP_SCRIPT_FLOW.md](./BOOTSTRAP_SCRIPT_FLOW.md) |
| **Application Insights** | Monitoring setup (legacy) | [APPLICATION_INSIGHTS_SETUP.md](./APPLICATION_INSIGHTS_SETUP.md) |
| **Exercises** | Hands-on tutorials | [DEPLOYMENT_EXERCISES.md](./DEPLOYMENT_EXERCISES.md) |
| **Script Source** | Bootstrap automation script | [../../Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1](../../Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1) |
| **OIDC Verification** | Check OIDC configuration | [../../Resources/Azure-Deployment/check-app-registration.ps1](../../Resources/Azure-Deployment/check-app-registration.ps1) |

---

**Happy Deploying! 🚀**

For questions or issues not covered in documentation, consult with the DevOps team or create an issue in the repository.
