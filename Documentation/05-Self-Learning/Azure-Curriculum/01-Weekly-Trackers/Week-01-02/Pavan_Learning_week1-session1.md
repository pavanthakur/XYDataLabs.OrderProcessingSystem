- [ ] **Tool Installation** (20 min)
  - [ ] Install Azure CLI: `winget install Microsoft.AzureCLI`
  - [ ] Install VS Code Azure extensions: `ms-vscode.vscode-node-azure-pack`
  - [ ] Test Azure CLI login: `az login`

# Tool Installation – Detailed Breakdown

> Purpose: Set up core Azure tooling with quick validation. Total time: ~20 minutes.

---

## 1. Install Azure CLI

The Azure CLI is a cross‑platform command-line tool to manage Azure resources from your terminal.

### Steps
1. Open Windows Terminal / PowerShell / Command Prompt.
2. Install via Windows Package Manager (winget):

```powershell
winget install Microsoft.AzureCLI
```
3. After installation, verify:

```powershell
az --version
```
You should see version info (CLI core, Python, extensions list).

### Notes
- winget is available on Windows 10+ (if missing, install *App Installer* from Microsoft Store).
- If corporate proxy issues occur, test with: `az version` (offline metadata) or configure proxy env vars.

---

## 2. Install VS Code Azure Extensions

Enhance VS Code to manage Azure resources directly inside the editor.

### Core Extension Pack
Search and install: `Azure Tools` (modern name for the pack formerly referenced by `ms-vscode.vscode-node-azure-pack`). It bundles:
- Azure App Service
- Azure Functions
- Azure Storage
- Azure Key Vault
- Azure Resources (ARM & Bicep)
- Container Apps / Containers integration (via Docker & Azure extensions)

### Steps
1. Open VS Code.
2. Press `Ctrl+Shift+X` (Extensions view).
3. Search: `Azure Tools`.
4. Click Install.
5. (Optional) Also install:
   - `Azure CLI Tools`
   - `Docker`
   - `Bicep` (for infrastructure templates)

### Post-Install Check
Open the Azure panel (icon in Activity Bar) → Sign in → Ensure subscriptions load.

---

## 3. Test Azure CLI Login

Authenticate to enable CLI commands against your subscription.

### Steps
```powershell
az login
```
A browser window opens → complete sign-in (includes MFA if required). On success, JSON of subscription(s) displays.

### Common Issues & Fixes
| Symptom | Cause | Fix |
|---------|-------|-----|
| Browser does not open | Default browser blocked | Use `az login --use-device-code` |
| MFA loop | Conditional Access policy | Complete MFA in same browser profile |
| Proxy / network error | Corporate proxy | Set `HTTPS_PROXY` env var, then retry |
| No subscriptions returned | Wrong tenant | Use `az account tenant set --tenant <tenantId>` |

### Helpful Commands
```powershell
# List subscriptions
az account list --output table

# Set active subscription
az account set --subscription "<SUBSCRIPTION NAME OR ID>"
```

---

## 4. Summary Timeline
- Install Azure CLI: ~5 minutes
- Install VS Code Azure Extensions: ~10 minutes
- Test Azure CLI Login: ~5 minutes

> ✅ After completing these steps you are ready to: build & tag Docker images, push to Azure Container Registry (ACR), and begin Azure Container Apps setup per your Week 1 plan.

---

## 5. Quick Verification Checklist
| Item | Command / Action | Verified? |
|------|------------------|-----------|
| Azure CLI installed | `az --version` shows versions | ☐ |
| Logged into Azure | `az account show` returns JSON | ☐ |
| Subscription set | `az account show --query name` | ☐ |
| VS Code Azure signed in | Azure panel lists resources | ☐ |
| Docker (prereq for images) | `docker --version` | ☐ |

---

## 6. Next Recommended Step
Proceed to: Create Azure Resource Group + Azure Container Registry (ACR) per Week 1 Day 3, then push your first image.

```powershell
# Example next actions
az group create -n rg-orderprocessing-dev -l centralus
az acr create -n <ACR_NAME> -g rg-orderprocessing-dev --sku Basic
az acr login -n <ACR_NAME>
```

---

*Maintained enterprise standard: documentation clarity + actionable verification.*