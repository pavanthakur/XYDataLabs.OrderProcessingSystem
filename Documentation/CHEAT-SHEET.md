# Development Workflow Cheat Sheet
**Quick Reference - Keep This Handy**

---

## ⚡ CRITICAL VALIDATIONS (Before Every Commit)

```powershell
# Workflow changes → MANDATORY
./Resources/Azure-Deployment/validate-workflow-config.ps1

# Configuration changes → Recommended
./Resources/Azure-Deployment/validate-sharedsettings-diff.ps1

# Before Azure deployment → MANDATORY
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev

# Code changes → Standard
dotnet build && dotnet test
```

**Exit Code 0 = ✅ Safe to proceed | Exit Code 1 = ❌ Fix before commit**

---

## 🔄 Daily Git Workflow

```powershell
# Start day
git checkout dev; git pull origin dev

# Make changes, then commit
git status
git diff
git add .
git commit -m "type: description"
git push origin dev

# Sync dev → main
git checkout main; git merge dev --no-ff; git push origin main; git checkout dev
```

---

## 📝 Commit Message Format

```
feat: Add new feature
fix: Correct bug
docs: Update documentation
refactor: Restructure code
test: Add tests
chore: Maintenance tasks
```

---

## 🧪 Build & Test

```powershell
dotnet build                                    # Build solution
dotnet test                                     # Run all tests
dotnet run --project XYDataLabs.OrderProcessingSystem.API  # Run API
dotnet run --project XYDataLabs.OrderProcessingSystem.UI   # Run UI
```

---

## ☁️ Azure Quick Commands

```powershell
az login                                        # Login
az account show                                 # Check subscription
az group list --output table                    # List resource groups
az ad app federated-credential list --id <id>   # Check OIDC credentials
```

---

## 🐳 Docker Quick Commands

```powershell
docker ps                                       # Running containers
docker ps -a                                    # All containers
docker logs container-name --follow             # Watch logs
docker-compose up -d                            # Start all services
docker-compose down                             # Stop all services
```

---

## 🆘 Emergency Rollback

```powershell
git reset --soft HEAD~1                         # Undo commit (keep changes)
git reset --hard HEAD~1                         # Undo commit (discard changes)
git checkout HEAD -- filename                   # Undo file changes
```

---

## ✅ Pre-Commit Checklist

**Code Changes:**
- [ ] `git status` - Review files
- [ ] `dotnet build` - Build passes
- [ ] `dotnet test` - Tests pass
- [ ] `git diff` - Review changes

**Workflow Changes:**
- [ ] `validate-workflow-config.ps1` - MANDATORY ✅
- [ ] Validator exits with code 0
- [ ] Review environment mappings
- [ ] DO NOT COMMIT if validator fails

**Azure Bootstrap:**
- [ ] `test-branch-env-mapping.ps1 -Environment dev` - Dry run
- [ ] `az account show` - Verify subscription
- [ ] Review workflow inputs carefully
- [ ] Monitor execution in GitHub Actions

---

## 💰 Cost-Saving Rules

1. ✅ Always validate before committing workflows
2. ✅ Always dry-run before Azure deployments
3. ✅ Test locally before cloud deployment
4. ✅ Use dev environment for testing

**Remember:** 2 seconds validation saves hours of debugging!

---

## 📂 Key File Locations

| File | Location |
|------|----------|
| Workflow validator | `Resources/Azure-Deployment/validate-workflow-config.ps1` |
| Branch-env mapper | `Resources/Azure-Deployment/test-branch-env-mapping.ps1` |
| Config validator | `Resources/Azure-Deployment/validate-sharedsettings-diff.ps1` |
| GitHub App Token workflow | `.github/workflows/generate-github-app-token.yml` |
| Prevention guide | `Documentation/HOW-TO-AVOID-CONFIG-ERRORS.md` |
| Full reference | `QUICK-COMMAND-REFERENCE.md` |

---

## 🎯 Common Scenarios Quick Guide

### Update Code
```powershell
# Make changes → Build → Test → Commit → Push
dotnet build && dotnet test
git add .; git commit -m "feat: description"; git push origin dev
```

### Update Workflow
```powershell
# Make changes → VALIDATE → Commit → Push
./Resources/Azure-Deployment/validate-workflow-config.ps1
git add .; git commit -m "fix: workflow update"; git push origin dev
```

### Azure Bootstrap (First Time)
```powershell
# Dry-run → Login → Run workflow in GitHub UI
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev
az login
# Go to: github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions
```

---

**When in doubt, validate! Prevention > Debugging**

*Print this and keep it near your desk*
