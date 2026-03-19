# Quick Command Reference — Index
**Last Updated:** March 20, 2026 (Day 34 — refactored to index + topic files)

This is an **index file**. Detailed commands live in the topic files below.
Add new commands to the appropriate topic file, not here.

---

## 📂 Navigate by Topic

| Topic | File | Days |
|-------|------|------|
| Git, daily workflow, validation, scenarios | [commands/git-workflow.md](commands/git-workflow.md) | All |
| Azure CLI, Bicep, OIDC, GitHub workflows | [commands/azure-infra.md](commands/azure-infra.md) | All |
| Azure SQL, EF Core migrations, sqlcmd | [commands/azure-sql-ef.md](commands/azure-sql-ef.md) | 32+ |
| Local dev, dotnet run, Docker, SQL logging | [commands/local-dev.md](commands/local-dev.md) | All |

---

## ✅ Pre-Commit Checklists (Quick Reference)

### Code Changes
- [ ] `git status` — review changed files
- [ ] `dotnet build` — build passes
- [ ] `dotnet test` — tests pass
- [ ] `git diff` — review changes

### Workflow Changes (MANDATORY)
- [ ] `./Resources/Azure-Deployment/validate-workflow-config.ps1` — exit code 0
- [ ] Verify `bootstrap-dev` uses `dev` environment / `dev.json`
- [ ] Verify `bootstrap-staging` uses `staging` environment / `staging.json`
- [ ] Verify `bootstrap-prod` uses `prod` environment / `prod.json`
- [ ] DO NOT COMMIT if validator fails

### Before Azure Bootstrap
- [ ] `./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev` — dry run
- [ ] `az account show` — verify correct subscription
- [ ] Review workflow inputs carefully in GitHub UI

### Before Deploying to Production
- [ ] All tests pass in dev + staging
- [ ] Code review completed
- [ ] Documentation updated
- [ ] Rollback procedure documented

---

## ⚠️ Red Flags (Workflow Misconfiguration)

- ❌ `prod` mentioned inside a `bootstrap-dev` job
- ❌ `dev` mentioned inside a `bootstrap-prod` job
- ❌ Logging messages don't match script parameters
- ❌ Parameter file (`dev.json`) doesn't match environment name
- ❌ Branch name (`main`) doesn't match job name `bootstrap-dev`

> See [commands/git-workflow.md](commands/git-workflow.md) for full troubleshooting steps.

---

## 🤖 Copilot Agent Prompts (VS Code Chat)

Reusable agent prompts stored in `.github/prompts/`. Type in VS Code Chat (`Ctrl+Shift+I` → Agent mode).

| Command | When to use | What it does |
|---------|-------------|--------------|
| `/day-complete` | End of every curriculum day | Routes updates to curriculum, commands files, ADRs, memory. Suggests commit. |
| `/sql-local-access` | After every fresh bootstrap/deploy | Opens/closes Azure SQL firewall for your local IP. Prints SSMS details. |

**How to run:** `Ctrl+Shift+I` → Agent mode → type `/day-complete` → answer "What did you complete today?"

### Routing Decision (quick ref)

| What you did | Where it goes |
|--------------|---------------|
| Completed checklist item | `1_MASTER_CURRICULUM.md` |
| Ran a CLI command | `Documentation/commands/<topic>.md` |
| Chose technology X over Y | New `docs/architecture/decisions/ADR-NNN.md` |
| Learned reusable pattern | `/memories/architect-patterns.md` |
| New Azure resource/FQDN | `/memories/repo/azure-resources.md` |
| New .NET class/convention | `/memories/repo/dotnet-conventions.md` |
| Workflow/deployment gotcha | `/memories/repo/workflow-split.md` |

---

## 💰 Cost-Saving Rules

1. ✅ Always validate before committing workflow changes
2. ✅ Always dry-run before Azure deployments
3. ✅ Test locally before cloud deployment
4. ✅ Use dev environment for all experimentation
5. ✅ Prevention > Debugging — 2 seconds validation saves hours of debugging

---

## 🔗 Important URLs

- **Repository:** https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem
- **Actions:** https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions
- **Azure Portal:** https://portal.azure.com
- **API (dev):** https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger
- **UI (dev):** https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net

---

## 📚 Related Documentation

- `Documentation/commands/` — all detailed command reference files (this index points here)
- `Resources/Azure-Deployment/` — all Azure automation scripts
- `Resources/Configuration/` — sharedsettings per environment
- `.github/workflows/README.md` — workflow overview and secrets
- `TROUBLESHOOTING-INDEX.md` — quick links for common errors

---

**Remember:** Prevention is cheaper than debugging. Always validate before committing critical changes.
