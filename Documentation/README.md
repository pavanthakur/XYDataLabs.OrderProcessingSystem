# Documentation Organization

This folder contains all project documentation files that were previously scattered in the root directory. The files have been organized into logical categories for better navigation and maintenance.

## 📁 Folder Structure

### 01-Project-Overview
Contains main project documentation and overview files:
- `README.md` - Main project documentation
- `CLEANUP_SUMMARY.md` - Project cleanup activities summary

### 02-Azure-Learning-Guides
**Azure deployment, monitoring, and infrastructure automation guides**

📖 **START HERE**: [Azure Documentation Navigation Guide](./02-Azure-Learning-Guides/AZURE_README.md)

| Document | Purpose | Audience | Status |
|----------|---------|----------|--------|
| **AZURE_README.md** | Central navigation hub for all Azure documentation | Everyone | ✅ Latest |
| **AZURE_DEPLOYMENT_GUIDE.md** | Complete deployment strategy and workflow (1300+ lines) | Developers, DevOps | ✅ Nov 2025 |
| **BOOTSTRAP_SCRIPT_FLOW.md** | Line-by-line execution flow for code review (850+ lines) | Junior Devs, Reviewers | ✅ Nov 2025 |
| **APP_INSIGHTS_AUTOMATED_SETUP.md** | Automated App Insights setup per environment (enterprise) | DevOps, Architects | ✅ Nov 2025 ⭐ NEW |
| **APPLICATION_INSIGHTS_SETUP.md** | Monitoring setup (legacy/reference) | Operations | ⚠️ Partially superseded |
| **DEPLOYMENT_EXERCISES.md** | Hands-on tutorials and exercises | Learners | ⚠️ Some legacy content |

**Quick Links by Use Case**:
- 🚀 **First-time deployment** → [AZURE_README.md - Quick Start](./02-Azure-Learning-Guides/AZURE_README.md#quick-start---where-to-begin)
- 🔍 **Code review** → [BOOTSTRAP_SCRIPT_FLOW.md](./02-Azure-Learning-Guides/BOOTSTRAP_SCRIPT_FLOW.md)
- 🏢 **Enterprise setup** → [AZURE_DEPLOYMENT_GUIDE.md - Enterprise Strategy](./02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md#enterprise-production-strategy-multi-environment)
- 🔧 **Troubleshooting** → [BOOTSTRAP_SCRIPT_FLOW.md - Troubleshooting](./02-Azure-Learning-Guides/BOOTSTRAP_SCRIPT_FLOW.md#troubleshooting-guide)

**Latest Enhancements (Nov 2025)**:
- ✅ Parallel resource creation (3-4x faster)
- ✅ Integrated OIDC setup (zero manual steps)
- ✅ Intelligent 20-minute wait with interval checks
- ✅ Automatic .NET 8 runtime configuration
- ✅ Pre-existence checks for safe re-runs
- ✅ Complete verification checklist
- ✅ **Automated App Insights configuration per environment** ⭐ NEW
- ✅ **Enterprise-grade observability with SDK integration** ⭐ NEW

### 03-Database-Guides
*Currently empty - reserved for database-related documentation*

### 03-Configuration-Guides
Contains application configuration and settings documentation:
- `SIMPLIFIED_CONFIG_GUIDE.md` - Simplified configuration guide (7KB)
- `DOTENV_DEPENDENCY_ELIMINATION_SUMMARY.md` - Environment configuration summary (8KB)

### 04-Enterprise-Architecture
*Currently empty - reserved for enterprise architecture documentation*

### 06-Testing-and-Results
*Currently empty - reserved for testing documentation and results*

## �️ Resources Folder Organization

The project has been reorganized with a centralized **Resources** folder containing:

### Resources/BuildConfiguration
- `BannedSymbols.txt` - Code analysis banned symbols
- `CodeAnalysis.ruleset` - Static code analysis rules
- `Directory.Build.props` - MSBuild global properties
- `Directory.Packages.props` - Package management configuration

### Resources/Configuration
- `sharedsettings.dev.json` - Development environment settings
- `sharedsettings.uat.json` - UAT environment settings
- `sharedsettings.prod.json` - Production environment settings
- `sharedsettings.local.json` - Local development overrides

### Resources/Docker
- `start-docker.ps1` - Main Docker startup script with enterprise features
- `docker-compose.dev.yml` - Development environment composition
- `docker-compose.uat.yml` - UAT environment composition
- `docker-compose.prod.yml` - Production environment composition
- `docker-compose.database.yml` - Database services composition

### Resources/Certificates
- SSL certificates for HTTPS development and testing

## �📋 Organization Summary

**Files with Content (6 files):**
- Project Overview: 2 files with content 
- Docker Guides: 3 files (all with substantial content - 75KB total)
- Configuration Guides: 2 files (15KB total)

**Resources Structure:**
- Build Configuration: 4 files for MSBuild and code analysis
- Configuration: 4 environment-specific settings files
- Docker: 1 script + 4 compose files for multi-environment deployment
- Certificates: SSL/TLS certificates for secure development

## 🔄 Path Updates

**Important:** The project structure has been reorganized. Key script locations:
- **Docker Script:** `Resources\Docker\start-docker.ps1` (moved from root)
- **Configuration:** `Resources\Configuration\sharedsettings.*.json`
- **Build Files:** `Resources\BuildConfiguration\*`

## 🔄 Maintenance

This organization makes it easier to:
- Find relevant documentation quickly
- Identify gaps in documentation (empty folders)
- Maintain and update related documents together
- Keep the root directory clean and organized
- Centralize all resources in logical subfolders
- Maintain consistent build and deployment configurations

## 📝 Next Steps

Consider:
1. Populating empty categories with relevant documentation
2. Creating index files for each category if they grow larger
3. Adding new documentation files to appropriate categories
4. Keeping the folder structure aligned with Visual Studio solution

## 🚀 Docker Startup Interface (Nov 16 2025 Simplification)

The `start-docker.ps1` script was simplified to reduce cognitive load while improving resilience.

### New / Core Flags
| Flag | Purpose |
|------|---------|
| `-Strict` | CI-grade startup: base image retry + fallback warming, enforced health wait, normalized exit code. |
| `-LegacyBuild` | Reuse existing images for faster local cycles (dev only recommended). |
| `-Reset` | Stop stack + remove images for selected profile (http/https) then rebuild cleanly. |
| `-NoPrePull` | Skip base image warm pre-pull step (use when images already cached). |
| `-Help` | Inline usage and migration guidance. |

### Health Behavior
Health wait is automatic when using `-Strict` or `-LegacyBuild`. Timeout configurable via `-HealthTimeoutSec` (default 90s).

### Deprecated → Replacement
| Deprecated | Replacement / Now Handled By |
|------------|------------------------------|
| `-PrePullRetryCount` | Built-in retries (3) under `-Strict`. |
| `-UseBuildFallbackForPrePull` | Automatic fallback warming under `-Strict`. |
| `-FailOnPrePullError` | Implied by `-Strict` (fatal on unresolved base image pulls). |
| `-WaitForHealthy` | Implied by `-Strict` & `-LegacyBuild`. |
| `-CleanImages` | Use `-Reset` for per-profile clean rebuild. |

> **Note on First-Time Setup:** The initial download of base Docker images (like .NET SDK and ASP.NET runtime) can be time-consuming, especially on slower networks. The script will display a message box to inform you when this one-time download is in progress. Please be patient and allow the process to complete.

### Quick Examples
```powershell
# Standard dev fresh build
./start-docker.ps1 -Environment dev -Profile http

# Fast strict reuse (image reuse + health gating)
./start-docker.ps1 -Environment dev -Profile http -LegacyBuild -Strict

# Clean rebuild of HTTPS profile only
./start-docker.ps1 -Environment dev -Profile https -Reset

# UAT strict with HTTPS
./start-docker.ps1 -Environment uat -Profile https -Strict

# Skip base warm pull (fast network)
./start-docker.ps1 -Environment dev -Profile http -NoPrePull

# Show help
./start-docker.ps1 -Help
```

### Compose Auto-Detection (Nov 16 2025 Update)
The Docker startup script now automatically detects which Compose invocation is available:

| Scenario | Detected Form | Action Needed |
|----------|---------------|---------------|
| Docker Desktop (modern) | `docker compose` | None – plugin used automatically |
| Legacy install | `docker-compose` | None – legacy binary used if plugin absent |
| Both present | `docker compose` | Preferred (v2) |
| Neither present | (error) | Install Docker Desktop / Compose plugin |

Manual commands in the guides still show `docker-compose` for backward compatibility. You can safely use `docker compose` – the script adapts either way. Prefer `docker compose` going forward (officially maintained v2). No documentation changes required for existing automation or CI; GitHub Actions runners already provide the v2 plugin.

Minimal manual log tail example (dev):
```powershell
docker compose -f docker-compose.dev.yml logs -f api
```

If you see an error like "Docker Compose not found" ensure Docker Desktop is installed and restarted; then re-run `./start-docker.ps1 -Help`.

### Why Simplify?
Previous granular resilience flags created friction with little day‑to‑day benefit. Consolidating into `-Strict` gives reliable deterministic startup in pipelines and local health verification without parameter tuning. `-Reset` replaces image clean logic; `-NoPrePull` provides explicit opt‑out when warming is unnecessary.

### Reference
For full details see `02-Azure-Learning-Guides/DOCKER_COMPREHENSIVE_GUIDE.md` (Parameter table + migration section).
