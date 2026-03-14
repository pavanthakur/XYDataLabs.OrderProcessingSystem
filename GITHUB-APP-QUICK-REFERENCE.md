# GitHub App Quick Reference Card

## 📝 Quick Commands

### Validate Configuration
```powershell
.\scripts\validate-github-app-config.ps1 -Detailed
```

### Setup New App
```powershell
.\scripts\setup-github-app-from-manifest.ps1
```

### Run Bootstrap (All Environments)
```yaml
Workflow: Azure Bootstrap Setup
Options:
  - Environment: all
  - Setup Azure OIDC: true (first time) / false (if already done)
  - Setup GitHub App: false (use script instead)
  - Configure Secrets: true
  - Bootstrap Infrastructure: true
```

---

## 📍 Important URLs

| Resource | URL |
|----------|-----|
| **Create GitHub App** | https://github.com/settings/apps/new |
| **Manage Apps** | https://github.com/settings/apps |
| **App Installations** | https://github.com/settings/installations |
| **Repository Secrets** | https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions |
| **Environments** | https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/environments |
| **Workflows** | https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions |

---

## 🔐 Required Secrets

### Repository Secrets (Once)
- `APP_ID` - GitHub App ID
- `APP_PRIVATE_KEY` - Private key (.pem file contents)
- `AZUREAPPSERVICE_CLIENTID` - Azure OIDC Client ID
- `AZUREAPPSERVICE_TENANTID` - Azure Tenant ID
- `AZUREAPPSERVICE_SUBSCRIPTIONID` - Azure Subscription ID

### Environment Secrets (Per Environment: dev, staging, prod)
- `AZUREAPPSERVICE_CLIENTID`
- `AZUREAPPSERVICE_TENANTID`
- `AZUREAPPSERVICE_SUBSCRIPTIONID`

---

## 🔧 Required Permissions

GitHub App must have these permissions:

| Permission | Level | Critical |
|------------|-------|----------|
| Actions | Read and write | Yes |
| **Secrets** | **Read and write** | **⚠️ CRITICAL** |
| Workflows | Read and write | Yes |
| Pull requests | Read and write | Yes |
| Administration | Read and write | Yes |
| **Environments** | **Read and write** | **⚠️ CRITICAL** |
| Contents | Read | Yes |
| Metadata | Read | Automatic |

---

## 🚀 Delete & Recreate Flow

### Quick Steps
1. **Backup**: `.\scripts\validate-github-app-config.ps1 -Detailed > backup.txt`
2. **Delete**: https://github.com/settings/apps → Advanced → Delete
3. **Recreate**: `.\scripts\setup-github-app-from-manifest.ps1`
4. **Update Secrets**: APP_ID and APP_PRIVATE_KEY
5. **Reinstall**: Install app on repository
6. **Configure**: Run bootstrap workflow
7. **Validate**: `.\scripts\validate-github-app-config.ps1 -Detailed`

---

## 📚 Documentation

| Document | Purpose |
|----------|---------|
| `Documentation/03-Configuration-Guides/GITHUB-APP-AUTOMATION.md` | Complete guide |
| `Documentation/03-Configuration-Guides/QUICK-SETUP-GITHUB-APP.md` | Quick setup |
| `GITHUB-APP-DELETION-SUMMARY.md` | Executive summary |
| `scripts/README.md` | Script documentation |
| `.github/app-manifest.json` | App configuration |

---

## 🐛 Troubleshooting

### App token generation failed
→ Check app is installed on repository
→ Verify APP_ID and APP_PRIVATE_KEY are correct
→ Ensure "Secrets: Read and write" permission is set

### Environment secrets failed
→ Add "Administration: Read and write" permission
→ Re-approve permissions on installation page

### Validation shows failures
→ Run: `gh auth login`
→ Check: https://github.com/settings/installations
→ Verify: All required permissions are set

---

## ⚡ Clean Deployment from Scratch

```powershell
# 1. Setup GitHub App
.\scripts\setup-github-app-from-manifest.ps1

# 2. Validate
.\scripts\validate-github-app-config.ps1 -Detailed

# 3. Run Bootstrap (via GitHub Actions UI)
#    - Environment: all
#    - Setup OIDC: true
#    - Configure Secrets: true
#    - Bootstrap Infra: true

# 4. Validate again
.\scripts\validate-github-app-config.ps1 -Detailed

# 5. Deploy (via GitHub Actions or automatic triggers)
```

---

## 🎯 Key Points

✅ **App deletion is safe** - Azure credentials remain intact
✅ **Manifest ensures consistency** - Recreations are identical
✅ **Secrets are automated** - After initial app setup
✅ **Validation is built-in** - Check config anytime
✅ **Documentation is comprehensive** - Step-by-step guides available

⚠️ **Cannot fully automate** - GitHub security requires OAuth approval
⚠️ **Update secrets after recreation** - New APP_ID and APP_PRIVATE_KEY needed
⚠️ **Secrets permission is critical** - Without it, automation fails

---

**Version**: 1.0
**Last Updated**: 2026-01-27
**Repository**: pavanthakur/XYDataLabs.OrderProcessingSystem
