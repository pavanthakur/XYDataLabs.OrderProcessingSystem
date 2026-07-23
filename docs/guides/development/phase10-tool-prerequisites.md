# Phase 10 Tool Prerequisites

## Scope

This guide covers developer machine prerequisites required before Phase 10 implementation.

It does not describe application architecture, Azure infrastructure provisioning, deployment workflows, or feature implementation. Those belong in the Phase 10 implementation checklist, deployment guides, and runbooks.

## Document Governance

Update this guide whenever changes are made to:

- developer tooling
- SDK versions
- CI/CD tooling
- local runtime architecture
- emulator strategy
- onboarding automation

Changes to the approved tool version matrix should be reviewed alongside CI/CD updates so developer machines, GitHub Actions, and Azure deployments remain aligned.

## Principles

- Docker Compose is the canonical local Phase 10 runtime.
- Azure is a deployment-validation environment, not the development environment.
- Infrastructure is defined through Infrastructure as Code.
- Azure Portal is not the source of truth.
- Setup instructions must remain single-source and should not be duplicated across docs.

## Implementation Rules

- Aspire is optional and must not replace Docker Compose as the supported local path.
- Tool versions follow the approved matrix in this guide.
- Tool matrix changes must be reviewed with CI/CD updates so local, GitHub Actions, and Azure validation stay aligned.
- Manual Azure resources must be removed or captured in Infrastructure as Code before becoming supported.
- Emulator images should be pinned after the first validated working stack.
- Local application logic must remain testable through abstractions even when an emulator is unavailable or incomplete.

## Tool Categories

### Required Tools

| Tool | Purpose |
|---|---|
| .NET 8 SDK | repository build and test |
| PowerShell 7 | repo scripts |
| Node.js 20 LTS / npm 10.x | frontend and automation |
| Docker Desktop with Compose v2 | canonical local runtime and emulator host |
| Azure CLI | Azure authentication, `DefaultAzureCredential`, and deployment support |
| Bicep CLI | infrastructure validation |
| Azure Functions Core Tools v4 | local Azure Functions isolated worker debugging and host management |
| GitHub CLI | workflow and artifact debugging |
| Visual Studio 2022 or VS Code plus C# Dev Kit | development, debugging, and test execution |

### Recommended Tools

- Azure Storage Explorer
- SQL Server Management Studio or DBeaver
- Postman or Bruno
- Redis Insight
- VS Code Azure, Docker, Bicep, GitHub Actions, and YAML extensions

### Optional Tools

- Azure Developer CLI (`azd`)
- Aspire workload/tooling
- Dev Containers
- `jq`
- `yq`

## Approved Tool Version Matrix

| Component | Approved |
|---|---|
| .NET SDK | 8.x |
| PowerShell | 7.x |
| Node.js | 20 LTS |
| npm | 10.x |
| Docker Desktop | Current supported stable |
| Azure CLI | Current supported stable |
| GitHub CLI | Current supported stable |
| Azure Developer CLI | Optional; current supported stable when used |
| Azure Functions Core Tools | v4 |
| Azurite | Docker image, pinned tag |
| Service Bus emulator | Docker image, pinned tag |
| SQL Server container | Existing pinned SQL 2022 image |
| Redis container | Existing pinned Redis 7 image |
| `jq` | Optional; current supported stable when used |
| `yq` | Optional; current supported stable when used |

## Local Azure Service Support Matrix

Emulate what is practical, abstract what is not, and validate real cloud integrations in Azure.

| Capability | Local Strategy | Local Debug | Azure Validation |
|---|---|---|---|
| Azure Functions | Functions Core Tools for isolated debugging; Dockerized worker for Compose validation | breakpoints in Visual Studio or VS Code | Function App |
| Blob Storage | Azurite in Docker | Storage Explorer and app breakpoints | Azure Storage |
| Service Bus | emulator where supported plus transport abstractions | local adapter/debug flow | Azure Service Bus |
| SQL | SQL Server container | SSMS or DBeaver plus app breakpoints | Azure SQL |
| Redis | Redis container | Redis Insight plus app breakpoints | Azure Cache for Redis |
| Key Vault | user-secrets plus `DefaultAzureCredential` | local config/auth flow | Key Vault |
| Authentication | Keycloak local realm | local JWT/OIDC testing | Entra ID |
| Gateway | YARP | gateway breakpoints | APIM plus YARP |
| Containers | Docker Compose | Docker/IDE debugging | ACA |
| Eventing | integration tests and handler invocation | application event abstractions | Event Grid |

## Installation Order

### 1. Fix Local Profile Permissions

Fix access to:

```text
C:\Users\Pavan\.azure
C:\Users\Pavan\.docker
```

Validate:

```powershell
az --version
docker --version
docker compose version
docker ps
```

Expected:

- Azure CLI prints version details without profile permission errors.
- Docker prints version details without config permission warnings.
- Docker Desktop is reachable.
- Docker Compose v2 is available.

### 2. Install .NET 8 SDK

Install:

```powershell
winget install --exact --id Microsoft.DotNet.SDK.8
```

Validate:

```powershell
dotnet --list-sdks
dotnet --info
```

Expected:

- An `8.0.x` SDK is listed.
- Newer SDKs may remain installed, but the repository must pin the approved SDK through `global.json`.

### 3. Verify Repository SDK Pinning

Verify the repository contains a valid `global.json`. If it is missing, create it before Phase 10 implementation starts.

Recommended shape:

```json
{
  "sdk": {
    "version": "8.0.400",
    "rollForward": "latestPatch",
    "allowPrerelease": false
  }
}
```

Replace `8.0.400` with the approved .NET 8 SDK patch version used by the repository.

### 4. Install Azure Functions Core Tools v4

Prefer `winget` or the official MSI. Do not use a global npm install as the standard project setup.

Install:

```powershell
winget install --exact --id Microsoft.Azure.FunctionsCoreTools
```

Validate:

```powershell
func --version
where func
```

Expected:

- `func` returns a v4 version.
- Only one active `func` path wins on `PATH`.

Azure Functions local prerequisites:

- .NET 8 isolated worker runtime support must be available.
- Azure Functions Core Tools v4 must be installed.
- Function extension bundle/runtime compatibility must be verified once the Functions project exists.
- `func start` is for local isolated debugging.
- Dockerized Functions worker execution is for Compose validation.

### 5. Install Or Repair Azure CLI

Install or repair:

```powershell
winget install --exact --id Microsoft.AzureCLI
```

Validate:

```powershell
az --version
az login
az account show
```

Expected:

- Azure CLI works without profile permission errors.
- `az login` and `az account show` work before Azure SDK, Blob, Key Vault, or deployment validation.

### 6. Validate Bicep CLI

Validate:

```powershell
az bicep version
```

If missing:

```powershell
az bicep install
```

### 7. Install GitHub CLI

Install:

```powershell
winget install --exact --id GitHub.cli
```

Validate:

```powershell
gh --version
gh auth status
```

Usage:

- trigger workflows
- inspect Actions runs
- download workflow artifacts
- check pull request and build status

### 8. Install Recommended Debug Tools

#### Azure Storage Explorer

Install:

```powershell
winget install --exact --id Microsoft.Azure.StorageExplorer
```

Usage:

- connect to Azurite
- inspect local containers, blobs, and metadata
- compare local Azurite state with Azure Storage Account state

Azure Storage Explorer is a debugging tool, not an automation dependency.

#### SQL Inspection Tool

Use either SQL Server Management Studio or DBeaver.

SSMS:

```powershell
winget install --exact --id Microsoft.SQLServerManagementStudio
```

DBeaver:

```powershell
winget install --exact --id dbeaver.dbeaver
```

#### API And Redis Inspection

Postman or Bruno is recommended for API testing.

Redis Insight is optional for Redis inspection.

### 9. Install Supported IDE Tooling

Supported IDEs:

- Visual Studio 2022
- VS Code plus C# Dev Kit

Both should support:

- API debugging
- gateway debugging
- Azure Functions debugging
- Docker-backed debugging
- test execution

VS Code extensions:

```powershell
code --install-extension ms-dotnettools.csharp
code --install-extension ms-dotnettools.csdevkit
code --install-extension ms-azuretools.vscode-docker
code --install-extension ms-azuretools.vscode-azurefunctions
code --install-extension ms-azuretools.vscode-bicep
code --install-extension github.vscode-github-actions
code --install-extension redhat.vscode-yaml
code --install-extension ms-vscode.azure-account
code --install-extension ms-azuretools.vscode-azureresourcegroups
```

### 10. Install Optional CLI Utilities

Install only if useful for troubleshooting:

```powershell
winget install --exact --id jqlang.jq
winget install --exact --id mikefarah.yq
```

Validate:

```powershell
jq --version
yq --version
```

### 11. Install Optional Azure Developer CLI

Install only if evaluating Aspire manifest or `azd` deployment packaging later:

```powershell
winget install --exact --id Microsoft.Azd
```

Validate:

```powershell
azd version
```

`azd` is not required for Phase 10 because the active delivery model is Bicep plus GitHub Actions.

## Local Runtime Modes

### Docker Compose Validation Mode

This is the canonical Phase 10 local gate.

Docker runs:

- SQL Server
- Redis
- Keycloak
- Azurite
- Service Bus emulator when selected
- Functions worker
- gateway
- service APIs
- UI

Use this mode for repeatable validation and CI parity.

### Docker Backing Services And Debug Mode

Use this mode for daily bug fixes and breakpoint debugging.

Docker runs:

- SQL Server
- Redis
- Keycloak
- Azurite
- Service Bus emulator when selected

Visual Studio, VS Code, or command-line processes run:

- API/services
- gateway
- Functions worker
- UI

### Aspire Optional Inner Loop Mode

Aspire may orchestrate the same local graph for developer productivity, dashboard visibility, and later distributed app testing.

Aspire is optional in Phase 10. Docker Compose remains the supported baseline.

## Local Debug Identity Flow

Local debugging:

```text
Developer
  -> Keycloak local realm
  -> JWT token
  -> YARP Gateway
  -> API authorization policies
```

Azure validation:

```text
Developer
  -> Entra ID
  -> JWT token
  -> APIM/YARP
  -> API authorization policies
```

The local identity path is debug-friendly and portable. The Azure path remains production-aligned with Entra ID. Both paths use the same JWT/OIDC authorization model.

## Local Secrets Strategy

- Non-Docker local secrets use `.NET user-secrets`.
- Docker local secrets use `Resources/Docker/.env.local`.
- CI secrets use GitHub secrets.
- Azure runtime secrets use Key Vault.
- Azure SDK local identity uses `DefaultAzureCredential` through `az login`.

Avoid:

- secrets in `appsettings.Development.json`
- committed `.env.local`
- committed real provider keys
- portal-only secret configuration

## Service Bus Emulator Strategy

- Use Azure Service Bus emulator where it supports the selected local transport strategy.
- If Service Bus emulator is part of the selected local transport strategy, its health endpoint must pass.
- Application logic must remain testable through transport abstractions if emulator support is incomplete.
- The emulator is a local validation aid, not an architectural dependency.

## Environment Readiness Gate

Phase 10 implementation should not start until:

- required tools are installed
- repository contains valid `global.json` targeting the approved .NET 8 SDK
- Docker works without permission warnings
- Docker Desktop is installed
- Docker engine is running
- Docker Compose v2 is available
- Azure CLI works without profile permission errors
- `az login` and `az account show` work
- `az bicep version` works
- `func --version` works
- GitHub CLI is authenticated
- `docker compose version` works
- `docker compose config` succeeds
- Docker Compose environment file validation passes
- required local configuration files exist, including `Resources/Docker/.env.local` when Docker profiles require it
- Azure Functions runtime/extension compatibility is verified once the Functions project exists
- clean repo build succeeds
- existing tests can run
- local emulator stack starts and stops cleanly
- logs/artifacts are created for prerequisite checks

## Health Checklist

Validate:

- Docker Desktop is running.
- SQL container starts.
- Redis container starts.
- Azurite starts.
- Service Bus emulator health responds if selected.
- Docker Compose full stack starts.
- Docker Compose cleanup works with `down -v`.
- `dotnet build` succeeds.
- `dotnet test` succeeds.
- `func start` works once a Functions project exists.
- Azure Storage Explorer connects to Azurite.
- GitHub CLI can inspect workflow status.
- Azure CLI can authenticate and show subscription.

## Local Runtime Ports

These ports are the expected local defaults for Phase 10 tooling and backing services. Exact application ports remain owned by the relevant Docker Compose and profile files; update this table only when those files intentionally change.

| Service | Local Port |
|---|---|
| SQL Server | `1433` |
| Redis | `6379` |
| Azurite Blob | `10000` |
| Azurite Queue | `10001` |
| Azurite Table | `10002` |
| Service Bus Emulator AMQP | `5672`, if selected |
| Service Bus Emulator health/management | `5300`, if selected |
| Keycloak | repo profile-defined; current Phase 10 Docker stack uses `8081` host to `8080` container |
| Gateway | repo profile-defined |
| UI | repo profile-defined |
| Orders API | repo profile-defined |
| Inventory API | repo profile-defined |
| Notifications API | repo profile-defined |

## Update Process

When introducing a new required tool:

1. Update the approved tool matrix.
2. Update installation instructions.
3. Update the readiness checklist.
4. Verify CI/CD compatibility.
5. Update onboarding documentation if needed.

## Cross-Reference Convention

Other documents should reference this guide for setup instructions.

Do not duplicate installation or validation steps in planning, runbook, architecture, or reference documents.

## Deferred Work

| Item | Phase | Reason |
|---|---:|---|
| Developer bootstrap script `scripts/bootstrap.ps1` | Phase 12 | Automates prerequisite installation after the tool standard is stable |
| Environment verification script `scripts/verify-environment.ps1` | Phase 12 | Automates Environment Readiness Gate checks |
| `.devcontainer/` support | Phase 12/13 | Improves contributor onboarding after the toolchain stabilizes |
| Infrastructure folder consolidation | Phase 12 | Reduces platform asset sprawl after Phase 10 delivery stabilizes |
| Aspire deepening | Phase 13 | Inner-loop maturity after Docker Compose validation is stable |
| Aspire manifest / `azd` deployment evaluation | Phase 13 | ADR-backed deployment packaging decision |
| Tool version lockfile / richer machine bootstrap | Phase 12 | Governed developer environment standardization |

## Out Of Scope

This guide does not cover:

- Azure resource provisioning
- Bicep architecture
- GitHub Actions implementation
- Azure Functions application code
- ACA deployment
- APIM configuration
- Service Bus topology
- production networking
- cost governance

## Official References

- Azure Service Bus emulator: https://learn.microsoft.com/en-us/azure/service-bus-messaging/test-locally-with-service-bus-emulator
- Azurite: https://learn.microsoft.com/en-us/azure/storage/common/storage-install-azurite
- Azure Functions local development: https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local
- Azure CLI for Windows: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows
- Docker Desktop for Windows: https://docs.docker.com/desktop/setup/install/windows-install/
