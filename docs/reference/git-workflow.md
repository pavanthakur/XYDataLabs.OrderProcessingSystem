# Git Workflow & Validation Commands

**Part of:** [quick-command-reference.md](./quick-command-reference.md)  
**Last Updated:** April 10, 2026

---

## 🚀 Daily Development Workflow

### **1. Start Your Day**
```powershell
# Navigate to project
cd Q:\GIT\TestAppXY_OrderProcessingSystem

# Check current branch and status
git status
git branch

# Pull latest changes
git pull origin dev

# Check for merge conflicts
git log --oneline --graph --all --decorate -10
```

### **2. Before Making Changes**
```powershell
# Create feature branch (optional but recommended)
git checkout -b feature/your-feature-name

# Verify you're on correct branch
git branch --show-current
```

---

## ✅ Validation Commands (CRITICAL — Use Before Every Commit)

### **Pre-Commit Validation Checklist**
```powershell
# 1. Validate workflow configurations (MANDATORY for workflow changes)
./Resources/Azure-Deployment/validate-workflow-config.ps1

# 2. Test branch-to-environment mapping (for infrastructure changes)
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev

# 3. Validate shared settings consistency (before config changes)
./Resources/Azure-Deployment/validate-sharedsettings-diff.ps1

# 4. Check for errors in solution (before committing code)
dotnet build XYDataLabs.OrderProcessingSystem.sln

# 5. Run unit tests (before committing code)
dotnet test XYDataLabs.OrderProcessingSystem.UnitTest/
```

### **Completion-Check / Phase Freeze Gate**
```powershell
# Strict build gate used by /XYDataLabs-completion-check
dotnet build XYDataLabs.OrderProcessingSystem.sln --warnaserror /warnnotaserror:NU1701 "/consoleloggerparameters:NoSummary;ForceNoAlign"

# Targeted test gate used during closeout
dotnet test tests/XYDataLabs.OrderProcessingSystem.Domain.Tests --no-build --logger "console;verbosity=minimal"
dotnet test tests/XYDataLabs.OrderProcessingSystem.Application.Tests --no-build --logger "console;verbosity=minimal"
dotnet test tests/XYDataLabs.OrderProcessingSystem.API.Tests --no-build --logger "console;verbosity=minimal"
dotnet test tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests --no-build --logger "console;verbosity=minimal"

# Patch hygiene + AI customization validation
git diff --check
pwsh scripts/validate-ai-customization.ps1
```

Notes:
- Use this gate for phase freezes, workflow closeout, and repo-shared AI customization changes.
- `validate-ai-customization.ps1` must stay green whenever `.github/copilot-instructions.md`, `.github/instructions/`, `.github/prompts/`, `.github/agents/`, or `.github/skills/` changes.

### **Exit Code Interpretation**
- **Exit Code 0** = ✅ PASS — Safe to proceed
- **Exit Code 1** = ❌ FAIL — Fix issues before committing
- **Exit Code 2** = ⚠️ WARNING — Review discrepancies

### **Validation Frequency**
| Action | Validation Required | Command |
|--------|-------------------|---------|
| Code changes | Build + Test | `dotnet build && dotnet test` |
| Workflow changes | **MANDATORY** | `./Resources/Azure-Deployment/validate-workflow-config.ps1` |
| Config changes | Recommended | `./Resources/Azure-Deployment/validate-sharedsettings-diff.ps1` |
| Before Azure deploy | **MANDATORY** | `./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev` |

---

## 📝 Git Workflow Commands

### **Standard Commit Flow**
```powershell
# 1. Check what files changed
git status

# 2. Review specific changes
git diff                                    # All changes
git diff .github/workflows/                 # Specific folder
git diff generate-github-app-token.yml      # Specific file

# 3. Stage changes
git add .                                   # All files
git add .github/workflows/generate-github-app-token.yml  # Specific file

# 4. Review staged changes
git diff --staged

# 5. Commit with descriptive message
git commit -m "feat: Add new feature description"
git commit -m "fix: Correct configuration bug"
git commit -m "docs: Update documentation"

# 6. Push to remote
git push origin dev
git push origin feature/your-feature-name
```

### **Sync Branches**
```powershell
# Sync dev with main (after testing)
git checkout dev
git pull origin dev
./Resources/Azure-Deployment/validate-workflow-config.ps1  # If workflow changed
git checkout main
git pull origin main
git merge dev --no-ff -m "Merge: Release v1.2.3"
git push origin main
git checkout dev

# Sync dev from main (get hotfixes)
git checkout dev
git pull origin dev
git merge main --no-ff -m "Merge: Hotfix from main"
git push origin dev
```

### **Emergency Rollback**
```powershell
# Undo last commit (keep changes)
git reset --soft HEAD~1

# Undo last commit (discard changes) - DANGEROUS
git reset --hard HEAD~1

# Undo changes to specific file
git checkout HEAD -- filename

# View commit history to find rollback point
git log --oneline -10
git reset --hard <commit-hash>
```

---

## 🎯 Common Development Scenarios

### **Scenario: Updating Application Code**
```powershell
# 1. Make code changes in Visual Studio/VS Code
# 2. Build and test locally
dotnet build
dotnet test

# 3. Run locally to verify
cd XYDataLabs.OrderProcessingSystem.API
dotnet run

# 4. Commit changes
git add .
git commit -m "feat: Add new order validation logic"
git push origin dev
```

### **Scenario: Updating Workflow Configuration**
```powershell
# 1. Make workflow changes in .github/workflows/
# 2. MANDATORY validation
./Resources/Azure-Deployment/validate-workflow-config.ps1

# 3. If validator passes (exit code 0)
git add .github/workflows/
git commit -m "fix: Update bootstrap-dev configuration"
git push origin dev

# 4. If validator fails (exit code 1) — DO NOT COMMIT
# Fix issues and re-run validator
```

### **Scenario: Updating Configuration Files**
```powershell
# 1. Edit configuration in Resources/Configuration/
# 2. Validate consistency
./Resources/Azure-Deployment/validate-sharedsettings-diff.ps1

# 3. Review discrepancies (if any)
git add Resources/Configuration/
git commit -m "config: Update database connection strings"
git push origin dev
```

---

## 🆘 Emergency: Workflow Failed — Rollback
```powershell
# 1. Check commit history
git log --oneline -5

# 2. Revert to last working commit
git reset --hard <commit-hash>
git push origin dev --force

# 3. Verify with validator
./Resources/Azure-Deployment/validate-workflow-config.ps1
```

## 🆘 Emergency: Build Completely Broken
```powershell
# 1. Stash current changes
git stash

# 2. Get last working version
git checkout <last-working-commit>

# 3. Test build
dotnet clean
dotnet build

# 4. If works, investigate changes
git stash pop
git diff
```

---

## 🔍 Troubleshooting

### **Git Issues**
```powershell
# Check remote URL
git remote -v

# Fix remote URL
git remote set-url origin https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem.git

# Resolve merge conflicts
git status                           # See conflicted files
# Edit files to resolve conflicts
git add .
git commit -m "Resolve merge conflicts"

# Abort merge
git merge --abort
```

### **Build Issues**
```powershell
# Clear NuGet cache
dotnet nuget locals all --clear

# Clean and rebuild
dotnet clean
Remove-Item -Recurse -Force bin, obj
dotnet restore
dotnet build
```

---

## 💡 Best Practices — Git Commit Messages

Use conventional commit format:
- `feat:` — New feature
- `fix:` — Bug fix
- `docs:` — Documentation only
- `refactor:` — Code refactoring (no behaviour change)
- `test:` — Adding tests
- `chore:` — Maintenance (deps, config)
- `perf:` — Performance improvement
- `Day N:` — Curriculum day completion (e.g. `Day 34: Enable EF Core SQL logging`)

---

## ⚠️ Red Flags to Watch For

When editing workflow files, these patterns indicate a misconfiguration:
- ❌ `prod` mentioned inside `bootstrap-dev` job
- ❌ `dev` mentioned inside `bootstrap-prod` job
- ❌ Logging messages don't match script parameters
- ❌ Parameter file (`dev.json`) doesn't match environment name
- ❌ Branch name (`main`) doesn't match job name `bootstrap-dev`

---

## 🔄 Daily Workflow Summary

```powershell
# Morning
cd Q:\GIT\TestAppXY_OrderProcessingSystem
git checkout dev
git pull origin dev

# During — validate frequently after changes
dotnet build                                                         # After code changes
dotnet test                                                          # After code changes
./Resources/Azure-Deployment/validate-workflow-config.ps1           # After workflow changes

# Before commit
git status
git diff
git add .
git commit -m "type: description"
git push origin dev
```
