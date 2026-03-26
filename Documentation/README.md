# Documentation Organization

This folder contains all project documentation files organized into logical categories for better navigation and maintenance.

> 🤖 **Copilot / AI Reference**: For a single-page overview of the entire repository (structure, workflows, scripts, patterns, common issues), see [`.github/copilot-instructions.md`](../.github/copilot-instructions.md).

---

## 🤖 Copilot AI Tooling — How to Use

This repository has a structured Copilot customization layer. Here's what exists and how to use each piece.

### Custom Agents (pick before asking)

Open VS Code Chat (**Ctrl+Shift+I**) → click the **agent picker dropdown** at the top → select the agent that matches your task:

| Agent | When to select | What it does |
|-------|---------------|--------------|
| **Azure DevOps** | Workflows, Bicep, PowerShell, Docker, OIDC | Scoped to IaC/CI/CD files; won't touch C# business logic |
| **CQRS Backend** | C# entities, handlers, DTOs, EF Core, tests | Scoped to Domain/Application/Infrastructure; follows clean-arch rules |
| **Code Reviewer** | Review changes before committing | **Read-only** — checks architecture, security, tenant safety; outputs severity table |
| *(default)* | General questions, multi-domain work | No scope restriction — loads all context |

**Tip**: Always pick a specialized agent when your task fits one domain. The default agent loads everything; specialized agents stay focused and follow domain-specific rules.

### Instruction Files (automatic — no action needed)

These auto-attach based on which file you're editing. You don't invoke them manually.

| File you're editing | Instructions that auto-load |
|---------------------|----------------------------|
| Any `.cs` or `.csproj` | `clean-architecture.instructions.md` |
| `Infrastructure/**`, `Migrations/**` | + `ef-migrations.instructions.md` |
| Domain entities, DTOs, payment handlers, controllers | + `multitenant-payment-schema.instructions.md` |
| `.github/workflows/**` | `azure-workflows.instructions.md` |
| `infra/**`, `*.bicep` | `bicep.instructions.md` |
| `docs/architecture/**`, `*ADR*` | `architecture.instructions.md` |
| `05-Self-Learning/**`, `*CURRICULUM*` | `curriculum.instructions.md` |

Full overlap matrix: see [`.github/copilot-instructions.md` §9](../.github/copilot-instructions.md).

### Reusable Prompts (slash commands in Agent mode)

Open VS Code Chat → switch to **Agent mode** → type the command:

| Command | When to use | What it does |
|---------|------------|--------------|
| `/XYDataLabs-day-complete` | After finishing a curriculum day | Routes updates to curriculum checkboxes, command references, daily logs |
| `/XYDataLabs-sql-local-access` | Need local SSMS access to Azure SQL | Opens/closes firewall rule, prints connection details |
| `/XYDataLabs-context-audit` | Periodically or after major refactors | Detects stale AI context by diffing memory files vs actual codebase |

**Typical workflow**:
```
[After a coding/learning day]
└─ /XYDataLabs-day-complete  →  auto-updates curriculum + command docs
   └─ [Optional] /XYDataLabs-context-audit  →  verify no stale references

[After bootstrap or deploy]
└─ /XYDataLabs-sql-local-access  →  open firewall + SSMS details
   └─ [When done] /XYDataLabs-sql-local-access  →  close firewall
```

### File Locations

| What | Where |
|------|-------|
| Global project context | [`.github/copilot-instructions.md`](../.github/copilot-instructions.md) |
| Instruction files (7) | [`.github/instructions/`](../.github/instructions/) |
| Custom agents (3) | [`.github/agents/`](../.github/agents/) |
| Reusable prompts (3) | [`.github/prompts/`](../.github/prompts/) |
| Repository memory | `/memories/repo/` (local only, not in git) |

> **Maintenance rule**: When adding a new agent, instruction, or prompt — update [`.github/copilot-instructions.md` §9](../.github/copilot-instructions.md) and [`.github/prompts/README.md`](../.github/prompts/README.md).

### End-to-End Example: Adding a New Feature with Multitenant Support

**Scenario**: You need to add a `Shipment` entity with full CQRS, controller, EF migration, and tests — all tenant-aware.

#### Step 1 — Plan (default agent)

Use the **default agent** for cross-cutting planning:

```
Prompt: "I need to add a Shipment feature with multitenant support.
         Plan the full end-to-end: entity, handler, DTO, controller, migration, tests."
```

Copilot will outline all layers needed. Once you agree on the plan, switch to specialized agents.

#### Step 2 — Domain + Application + Infrastructure (CQRS Backend agent)

Switch to **CQRS Backend** agent → it auto-follows clean-architecture + multitenant + ef-migrations rules.

```
Prompt: "Create the Shipment entity in Domain with TenantId, OrderId, TrackingNumber,
         ShippedDate, Status. Then create CreateShipmentCommand, handler, DTO,
         and configure it in OrderProcessingSystemDbContext."
```

What happens behind the scenes:
- `clean-architecture.instructions.md` fires → enforces layer boundaries
- `multitenant-payment-schema.instructions.md` fires → enforces `TenantId` FK, composite indexes, tenant filter
- `ef-migrations.instructions.md` fires → follows DbContext configuration rules

Files created/modified:
```
Domain/Entities/Shipment.cs                          ← new entity with TenantId
Application/DTO/ShipmentDto.cs                       ← new DTO
Application/Features/Shipments/Commands/             ← new command + handler
Infrastructure/DataContext/OrderProcessingSystemDbContext.cs  ← DbSet + config
```

#### Step 3 — Generate EF Migration (CQRS Backend agent)

Stay on **CQRS Backend** agent:

```
Prompt: "Generate the EF migration for Shipment, run drift check, verify it's clean."
```

Terminal commands it will run:
```powershell
# Generate migration
dotnet ef migrations add AddShipment `
  --project XYDataLabs.OrderProcessingSystem.Infrastructure `
  --startup-project XYDataLabs.OrderProcessingSystem.API `
  --context OrderProcessingSystemDbContext

# Drift check — should produce empty migration
dotnet ef migrations add DriftCheck `
  --project XYDataLabs.OrderProcessingSystem.Infrastructure `
  --startup-project XYDataLabs.OrderProcessingSystem.API `
  --context OrderProcessingSystemDbContext

# Remove drift check migration
dotnet ef migrations remove `
  --project XYDataLabs.OrderProcessingSystem.Infrastructure `
  --startup-project XYDataLabs.OrderProcessingSystem.API `
  --context OrderProcessingSystemDbContext
```

#### Step 4 — Controller (CQRS Backend agent)

```
Prompt: "Add ShipmentController with POST and GET endpoints, 
         dispatching to the command/query handlers."
```

#### Step 5 — Tests (CQRS Backend agent)

```
Prompt: "Add unit tests for CreateShipmentCommandHandler 
         and architecture tests for Shipment entity tenant compliance."
```

#### Step 6 — Build + Test

```
Prompt: "Build the solution and run all tests."
```

```powershell
dotnet build XYDataLabs.OrderProcessingSystem.sln
dotnet test XYDataLabs.OrderProcessingSystem.sln --no-build
```

#### Step 7 — Review (Code Reviewer agent)

Switch to **Code Reviewer** agent before committing:

```
Prompt: "Review all uncommitted changes for architecture compliance, 
         tenant safety, and security."
```

It will output a severity table:

| Severity | File | Finding |
|----------|------|---------|
| ✅ PASS | Shipment.cs | TenantId FK present, composite index defined |
| ✅ PASS | ShipmentController.cs | No Infrastructure imports in controller |
| 🟡 LOW | ShipmentDto.cs | Consider adding validation attributes |

#### Step 8 — Commit + Update Context

```powershell
git add -A
git commit -m "Add Shipment entity with multitenant CQRS and EF migration"
```

Then optionally run `/XYDataLabs-context-audit` to verify instruction files still reflect the codebase.

#### Summary: Which Agent at Each Step

| Step | Agent | Why |
|------|-------|-----|
| 1. Plan | default | Cross-cutting, needs full context |
| 2. Entity + CQRS | **CQRS Backend** | Enforces clean-arch + tenant rules |
| 3. Migration | **CQRS Backend** | Follows ef-migrations protocol |
| 4. Controller | **CQRS Backend** | Ensures no layer violations in API |
| 5. Tests | **CQRS Backend** | Knows test project conventions |
| 6. Build + test | **CQRS Backend** | Runs dotnet build/test |
| 7. Review | **Code Reviewer** | Read-only audit before commit |
| 8. Context check | `/XYDataLabs-context-audit` | Detects stale instruction references |

---

## 🏗️ Current Architecture vs Learning Plan

### Current Production Architecture (Week 4 - Deployed ✅)
```
Azure App Service Deployment (Monolith)
├── API (Single Service)
│   ├── Orders Management
│   ├── Customer Management
│   ├── Payment Processing (OpenPay)
│   └── Swagger Documentation
├── UI (MVC Web App)
├── Azure SQL Database
├── Application Insights (Monitoring)
└── Key Vault (Created, needs configuration)
```

**Projects in Solution (7 projects):**
- `XYDataLabs.OrderProcessingSystem.API` - Single API handling all business logic
- `XYDataLabs.OrderProcessingSystem.UI` - MVC presentation layer
- `XYDataLabs.OrderProcessingSystem.Application` - Use cases and DTOs
- `XYDataLabs.OrderProcessingSystem.Domain` - Core entities
- `XYDataLabs.OrderProcessingSystem.Infrastructure` - Data access
- `XYDataLabs.OrderProcessingSystem.SharedKernel` - Shared kernel / cross-cutting concerns
- `XYDataLabs.OpenPayAdapter` - Payment integration

**Status:** ✅ Working, deployed, monitored

---

### Target Architecture (Week 5-6 Learning Goal 📅)
```
YARP Microservices Architecture (Planned)
├── YARP Gateway (Port 8080) - NEW ⭐
│   └── Single entry point for all services
├── Orders API (orders.localhost) - Refactored from existing
│   └── Order processing logic only
├── Inventory API (inventory.localhost) - NEW ⭐
│   └── Stock management and reservations
├── Notifications API (notifications.localhost) - NEW ⭐
│   └── Email/SMS notifications
├── UI (ui.localhost) - Existing
└── Docker Compose (5 services) - Enhanced
```

**New Projects to Create (3 projects):**
- `XYDataLabs.OrderProcessingSystem.Gateway` - YARP reverse proxy
- `XYDataLabs.OrderProcessingSystem.InventoryAPI` - Stock management microservice
- `XYDataLabs.OrderProcessingSystem.NotificationsAPI` - Notification microservice

**Status:** 📅 Planned for Days 41-56 (detailed guide in AZURE-PROGRESS-EVALUATION.md)

---

### Learning Path Timeline

| Phase | Weeks | Architecture | Status |
|-------|-------|--------------|--------|
| **Phase 1** | Week 1-4 (Days 1-31) | Monolith on Azure App Service | ✅ **Complete** |
| **Phase 2** | Week 5-6 (Days 41-56) | YARP Microservices (local) | 📅 Next Goal |
| **Phase 3** | Week 7-10 (Days 57-70) | Azure Functions + Container Apps | 📅 Future |

**Current Position:** Completed Phase 1, ready to start Phase 2

---

## 📁 Folder Structure

### 01-Project-Overview
Contains main project documentation and overview files:
- `README.md` - Main project documentation
- `CLEANUP_SUMMARY.md` - Project cleanup activities summary

### 02-Azure-Learning-Guides
**Azure deployment, monitoring, and infrastructure automation guides**

📖 **START HERE**: [Azure Documentation Navigation Guide](./02-Azure-Learning-Guides/AZURE_README.md)

| Document | Purpose | Audience |
|----------|---------|----------|
| **AZURE_README.md** | Central navigation hub for all Azure documentation | Everyone |
| **AZURE_DEPLOYMENT_GUIDE.md** | Complete deployment strategy and workflow (1300+ lines) | Developers, DevOps |
| **BOOTSTRAP_SCRIPT_FLOW.md** | Line-by-line execution flow for code review (850+ lines) | Junior Devs, Reviewers |
| **APP_INSIGHTS_AUTOMATED_SETUP.md** | Automated App Insights setup per environment (enterprise) | DevOps, Architects |
| **DOCKER_COMPREHENSIVE_GUIDE.md** | Full Docker startup script reference + migration guide | Developers |
| **VISUAL_STUDIO_DOCKER_PROFILES.md** | VS Docker launch profiles and debugging setup | Developers |
| **Containerization-ACA-Aspire-Learning-Path.md** | Learning path: Docker → ACA → .NET Aspire | Learners |

**Quick Links by Use Case**:
- 🚀 **First-time deployment** → [AZURE_README.md - Quick Start](./02-Azure-Learning-Guides/AZURE_README.md#quick-start---where-to-begin)
- 🔍 **Code review** → [BOOTSTRAP_SCRIPT_FLOW.md](./02-Azure-Learning-Guides/BOOTSTRAP_SCRIPT_FLOW.md)
- 🏢 **Enterprise setup** → [AZURE_DEPLOYMENT_GUIDE.md - Enterprise Strategy](./02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md#enterprise-production-strategy-multi-environment)
- 🐳 **Docker reference** → [DOCKER_COMPREHENSIVE_GUIDE.md](./02-Azure-Learning-Guides/DOCKER_COMPREHENSIVE_GUIDE.md)

### 03-Configuration-Guides
**GitHub App, Key Vault, secrets, and workflow configuration guides**

| Document | Purpose |
|----------|---------|
| **QUICK-SETUP-GITHUB-APP.md** | 5-minute GitHub App creation and secret configuration |
| **GITHUB-APP-AUTHENTICATION.md** | GitHub App token generation and authentication deep-dive |
| **AZURE-APPSERVICE-SECRETS-GUIDE.md** | Azure App Service secrets and environment variable setup |
| **KEY-VAULT-INTEGRATION.md** | Key Vault managed identity integration guide |
| **WORKFLOW-AUTOMATION-VISUAL-GUIDE.md** | Visual guide to workflow parameter selection and execution |

### 04-Enterprise-Architecture
**Architecture plans and weekly learning schedule**

| Document | Purpose |
|----------|---------|
| **ACA-Migration-Plan.md** | Migration plan from App Service to Azure Container Apps |
| **WEEKLY_AZURE_LEARNING_PLAN.md** | Week-by-week breakdown with daily tasks |

### 05-Self-Learning
**Azure learning curriculum and progress tracking**

📖 **LEARNING HUB**: [Azure Curriculum README](./05-Self-Learning/Azure-Curriculum/README.md)

| Document | Purpose | Audience | Status |
|----------|---------|----------|--------|
| **1_MASTER_CURRICULUM.md** | 18-week comprehensive Azure learning plan (Days 1-126) | Learners, Junior Devs | ✅ Active |
| **AZURE_PROGRESS_EVALUATION.md** (Root) | Current progress tracker & next steps (Weeks 1-10) | Everyone | ✅ Updated Dec 2025 ⭐ |
| **00_MASTER_PLAN.md** | Strategic 18-week microservices migration roadmap | Architects, Senior Devs | ✅ Complete |
| **WEEKLY_AZURE_LEARNING_PLAN.md** | Week-by-week breakdown with daily tasks | Daily learners | ✅ Active |

**Current Status (January 2026)**:
- ✅ **Weeks 1-4 Complete (Days 1-31)**: Azure fundamentals, App Service, OIDC, IaC with Bicep
  - **Architecture Achieved:** Monolithic API + UI deployed to Azure App Service
  - **Infrastructure:** SQL Database, Key Vault, Application Insights, CI/CD with GitHub Actions
  - **Status:** Production-ready monolith working successfully
- 📅 **Week 5-6 (Days 41-56) - NEXT GOAL**: 🆕 **YARP Microservices Architecture** ⭐ HIGH PRIORITY
  - Split monolith into microservices
  - YARP Gateway implementation (new project)
  - Inventory API (new microservice)
  - Notifications API (new microservice)
  - Docker Compose integration (5 services)
  - Service-to-service communication patterns
  - **Note:** This is a learning exercise, not replacing production deployment
- 📅 **Week 7-10 (Days 57-70)**: Azure Functions, Security, Container Apps migration

**Quick Links by Learning Stage**:
- 🎓 **Start learning** → [1_MASTER_CURRICULUM.md](./05-Self-Learning/Azure-Curriculum/1_MASTER_CURRICULUM.md)
- 📊 **Check progress** → [AZURE_PROGRESS_EVALUATION.md](../AZURE-PROGRESS-EVALUATION.md)
- 🏗️ **YARP implementation** → [AZURE_PROGRESS_EVALUATION.md - APPENDIX](../AZURE-PROGRESS-EVALUATION.md#appendix-yarp-implementation-guide-days-41-56)
- 🎯 **Weekly tasks** → [WEEKLY_AZURE_LEARNING_PLAN.md](./04-Enterprise-Architecture/WEEKLY_AZURE_LEARNING_PLAN.md)

**Latest Updates (December 2025)**:
- ✅ Prioritized YARP microservices architecture (Week 5-6)
- ✅ Added detailed Day 41-56 implementation guide
- ✅ Repositioned Azure Functions to Week 7 (integrates with YARP)
- ✅ Updated 10-week roadmap with Container Apps migration
- ✅ Complete code examples for Gateway, APIs, and Docker Compose

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
