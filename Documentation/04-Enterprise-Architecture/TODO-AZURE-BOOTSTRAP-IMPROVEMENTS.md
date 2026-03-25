# TODO — Azure Bootstrap & Deployment Improvements

> **Created**: March 2026 | **Scope**: `azure-bootstrap.yml`, IaC, CI/CD, hosting
> **Purpose**: Prioritized backlog of enterprise-grade improvements for XYDataLabs.OrderProcessingSystem

---

## Current Rating: 6 / 10

| Area | Score | Notes |
|------|-------|-------|
| Workflow automation & OIDC | 9/10 | Excellent — passwordless auth, multi-env, Phase 0/1a/1b/2/X orchestration |
| Infrastructure as Code | 6/10 | Bicep exists but missing network isolation, alerts, Log Analytics |
| Security & secrets | 3/10 | Hardcoded passwords in source — blocking issue for production |
| CI/CD pipeline maturity | 5/10 | Tests run, but no slots, no gates, no rollback, no scanning |
| Observability | 4/10 | App Insights provisioned but classic mode, no alerts, no dashboards |
| Resilience & scaling | 4/10 | Single instance, no auto-scale, no circuit breaker, no health endpoint |
| Documentation & runbooks | 8/10 | Very well documented; runbook folder exists but largely empty |
| Environment consistency | 8/10 | Fixed in this session — `stg` suffix consistent everywhere |

---

## Priority Legend

| Priority | Meaning | When to address |
|----------|---------|-----------------|
| **P0 — MUST** | Security/compliance blocker, will cause outages or data breaches | **Before any real deployment** |
| **P1 — SHOULD** | Strong enterprise expectation, significant risk reduction | **Next sprint / iteration** |
| **P2 — GOOD TO HAVE** | Improves reliability, reduces operational burden | **Planned backlog** |
| **P3 — PERFECT** | Gold-standard, differentiator, defense-in-depth | **When bandwidth allows** |

---

## P0 — MUST (Security & Compliance Blockers)

### SEC-01: Remove hardcoded credentials from source control ⚠️ CRITICAL — PUBLIC REPO

> **This repository is public.** Every credential below is visible to anyone on the internet
> and persisted in Git history. This item must be addressed before any other TODO.

#### Exposure Inventory (32 instances across 10 files)

| Credential | Files | Example value |
|------------|-------|---------------|
| SQL admin password | `infra/parameters/dev.json`, `staging.json`, `prod.json` | `<hardcoded SQL password>` — **FIXED ✅ 2026-03-20** (KV ARM reference) |
| SQL admin password (script default) | `provision-azure-sql.ps1` (L20), `run-database-migrations.ps1` (L17) | `<hardcoded SQL password>` — **FIXED ✅ 2026-03-20** (KV retrieval) |
| SQL connection-string password | `sharedsettings.dev.json`, `sharedsettings.local.json`, `sharedsettings.uat.json`, `sharedsettings.prod.json` | `<hardcoded SQL password>` |
| OpenPay MerchantId | `sharedsettings.{dev,local,uat,prod}.json` | (visible in file) |
| OpenPay PrivateKey | `sharedsettings.{dev,local,uat,prod}.json` | (visible in file) |
| OpenPay DeviceSessionId | `sharedsettings.{dev,local,uat,prod}.json` | (visible in file) |
| Certificate password | `sharedsettings.{dev,local,uat,prod}.json` | `<hardcoded certificate password>` |

#### Implementation Steps

**Step 1 — Rotate every exposed credential immediately**
- [ ] Change SQL admin password in Azure Portal for every environment
- [ ] Regenerate OpenPay API keys in the OpenPay dashboard
- [ ] Generate a new certificate with a new password
- [ ] Update Key Vault with the new values (do NOT commit new values to repo)

**Step 2 — Store all secrets in Azure Key Vault**
- [ ] Add secrets to Key Vault (`kv-orderproc-{dev|stg|prod}`): `SqlAdminPassword`, `OpenPayMerchantId`, `OpenPayPrivateKey`, `OpenPayDeviceSessionId`, `CertPassword`
- [ ] Use `populate-keyvault-secrets.ps1` or `az keyvault secret set` (ensure script itself does not hardcode secrets — pass via pipeline variables or interactive prompt)

**Step 3 — Replace hardcoded values with placeholders in config files**
- [ ] In `sharedsettings.{dev,uat,prod}.json` replace real passwords/keys with `"<<KEY-VAULT>>"` or remove the keys entirely
- [ ] Keep `sharedsettings.local.json` with developer-safe defaults (e.g. `localdb` no password) or `"<<SET-IN-USER-SECRETS>>"`

**Step 4 — Configure App Service to read from Key Vault**
- [ ] Add app settings with Key Vault references: `@Microsoft.KeyVault(SecretUri=https://kv-orderproc-{env}.vault.azure.net/secrets/{name})`
- [ ] Ensure App Service managed identity has `Key Vault Secrets User` role (see SEC-03)

**Step 5 — Use Bicep `reference()` or `getSecret()` for SQL password in IaC**
- [x] Remove `sqlAdminPassword` value from `infra/parameters/*.json` — **DONE ✅ 2026-03-20** (ARM Key Vault reference)
- [ ] In `infra/modules/sql.bicep` use `@secure() param sqlAdminPassword string` and pass via Key Vault reference at deployment time
- [ ] Example: `sqlAdminPassword: keyVault.getSecret('SqlAdminPassword')` in the parameters block

**Step 6 — Remove default password values from PowerShell scripts**
- [x] `provision-azure-sql.ps1` L20: change hardcoded SQL password default → empty default with KV fallback — **DONE ✅ 2026-03-20**
- [x] `run-database-migrations.ps1` L17: same pattern — KV fallback if not supplied — **DONE ✅ 2026-03-20**

**Step 7 — Scrub Git history (optional but recommended for public repo)**
- [ ] Use `git filter-repo` or BFG Repo-Cleaner to remove secrets from all historical commits
- [ ] Force-push cleaned history (coordinate with any collaborators)
- [ ] Alternatively: if history cleanup is too disruptive, treat all exposed credentials as compromised (Step 1 covers this)

**Step 8 — Prevent future leaks**
- [ ] Add a `.gitignore` pattern for any local secrets file (e.g. `sharedsettings.local.secrets.json`)
- [ ] Add a [pre-commit hook or GitHub Action](https://github.com/gitleaks/gitleaks) (gitleaks / trufflehog) to scan for secrets on every push
- [ ] Consider `dotnet user-secrets` for local development instead of JSON files

- **Risk**: Secrets visible to anyone on the internet and in Git history; violates SOC 2, ISO 27001, PCI-DSS

### SEC-02: Enable Key Vault purge protection
- [ ] Set `enablePurgeProtection: true` in `bicep/appservice-with-kv.bicep`
- [ ] Set `enablePurgeProtection: true` in `infra/modules/keyvault.bicep`
- **Risk**: Deleted Key Vault secrets can be permanently purged, losing all production secrets

### SEC-03: Migrate Key Vault from Access Policies to RBAC
- [ ] Set `enableRbacAuthorization: true` in both Bicep KV definitions
- [ ] Replace `accessPolicies` with `Microsoft.Authorization/roleAssignments` (Key Vault Secrets User role)
- [ ] Update `bootstrap-enterprise-infra.ps1` to use `az role assignment create` instead of `az keyvault set-policy`
- **Why**: Access Policies are legacy; Microsoft recommends RBAC exclusively since 2021

### SEC-04: Add health check endpoints to API
- [ ] Add `Microsoft.Extensions.Diagnostics.HealthChecks` NuGet package
- [ ] Implement `/health/live` (liveness), `/health/ready` (readiness — includes SQL, KV checks)
- [ ] Update Docker health checks from Swagger to `/health/live`
- [ ] Update all workflow health check steps to use `/health/ready`
- **Why**: Critical dependency for deployment slots, auto-healing, load balancer probes, and Kubernetes readiness (if migrating to ACA later)

---

## P1 — SHOULD (Strong Enterprise Expectations)

### CICD-01: Implement deployment slots (blue-green)
- [ ] Add `Microsoft.Web/sites/slots` resource to `infra/modules/hosting.bicep` (staging slot for prod)
- [ ] Update `deploy-api-to-azure.yml` to deploy to staging slot first
- [ ] Add health check validation on staging slot before swap
- [ ] Add `az webapp deployment slot swap` step
- [ ] Auto-rollback: if health check fails after swap, swap back
- **Prerequisite**: SEC-04 (health endpoints), SKU upgrade to Standard or Premium (Free/Basic don't support slots)
- **Impact**: Zero-downtime deployments, instant rollback capability

### CICD-02: Add production approval gates
- [ ] Configure GitHub Environment `production` with required reviewers
- [ ] Configure `staging` environment with deployment branch rules
- [ ] Update `deploy-api-to-azure.yml` and `deploy-ui-to-azure.yml` to reference environments
- **Risk mitigated**: Prevents accidental production deployments from unauthorized pushes

### CICD-03: Add CodeQL / SAST security scanning
- [ ] Create `.github/workflows/codeql.yml` — run on push to `main`, `dev`, `staging`
- [ ] Enable `csharp` language analysis
- [ ] Add `dotnet list package --vulnerable` step to build pipelines
- [ ] Enable GitHub secret scanning on repository settings
- **Impact**: Catches SQL injection, XSS, insecure deserialization patterns, vulnerable NuGet packages

### CICD-04: Add post-deployment smoke tests
- [ ] After each deployment, verify: health endpoint, Swagger reachable, basic API GET returns 200
- [ ] Add response time baseline check (fail if > 2s)
- [ ] Add to both `deploy-api-to-azure.yml` and `deploy-ui-to-azure.yml`
- **Files**: New step in deploy workflows

### INFRA-01: Migrate App Insights to workspace-based (Log Analytics)
- [ ] Create `Microsoft.OperationalInsights/workspaces` resource (new module `loganalytics.bicep`)
- [ ] Link Application Insights via `WorkspaceResourceId` and `IngestionMode: 'LogAnalytics'`
- [ ] Set retention: 30 days (dev), 90 days (staging), 180 days (prod)
- **Why**: Classic Application Insights is deprecated; workspace-based enables KQL cross-resource queries, long-term retention, Azure Monitor integration

### INFRA-02: Add alert rules and action groups
- [ ] Create Action Group (email notification to team)
- [ ] Alert: HTTP 5xx error rate > 5% over 15 min (Severity 2)
- [ ] Alert: Response time p95 > 2s over 10 min (Severity 3)
- [ ] Alert: App Service CPU > 80% over 5 min (Severity 3)
- [ ] Alert: SQL DTU > 90% over 10 min (Severity 2)
- **Files**: New Bicep module `infra/modules/alerts.bicep`

### INFRA-03: Restrict SQL Server network access
- [ ] Remove `0.0.0.0` firewall rule (allows all Azure services) from `infra/modules/sql.bicep`
- [ ] Add only specific App Service outbound IPs as firewall rules (or use VNet in P2)
- [ ] For prod: evaluate Private Endpoint (see NET-01 in P2)
- **Current**: `publicNetworkAccess: 'Enabled'` with any-Azure firewall rule

### DB-01: Enable geo-redundant backup for production
- [ ] Change `requestedBackupStorageRedundancy: 'Local'` to `'Geo'` in `infra/modules/sql.bicep` for prod
- [ ] Document RPO (Recovery Point Objective) and RTO (Recovery Time Objective)
- **Cost**: ~10% additional on database cost

### SCALE-01: Upgrade production App Service Plan SKU
- [ ] Change prod SKU from `B1` (Basic) to minimum `S1` (Standard) — enables slots, auto-scale, custom domains
- [ ] Ideal: `P1v3` (Premium v3) for always-on, VNet integration, 2 cores, 8 GB RAM
- [ ] Update `infra/parameters/prod.json` and `bootstrap-enterprise-infra.ps1` `$ProductionSku`
- **Current**: `B1` ($12/mo) → **Recommended**: `S1` ($70/mo) or `P1v3` ($150/mo)

---

## P2 — GOOD TO HAVE (Reliability & Operational Excellence)

### NET-01: Implement VNet with Private Endpoints (production)
- [ ] Create VNet with subnets: `snet-app` (App Service), `snet-data` (Private Endpoints)
- [ ] Add Private Endpoint for SQL Server (eliminate public access)
- [ ] Add Private Endpoint for Key Vault
- [ ] Configure App Service VNet integration
- [ ] Add Private DNS Zones for `privatelink.database.windows.net` and `privatelink.vaultcore.azure.net`
- **Files**: New module `infra/modules/networking.bicep`
- **Cost**: ~$7-10/month per Private Endpoint
- **Prerequisite**: SCALE-01 (Premium SKU needed for VNet integration)

### RESIL-01: Add Polly retry/circuit breaker to OpenPay adapter
- [ ] Add `Microsoft.Extensions.Http.Polly` NuGet package
- [ ] Implement retry policy (3 retries, exponential backoff: 100ms → 300ms → 900ms)
- [ ] Add circuit breaker (break after 3 consecutive failures, 30s cool-down)
- [ ] Log retry attempts via Serilog/App Insights
- **File**: `XYDataLabs.OpenPayAdapter/OpenPayAdapterService.cs`, `ServiceCollectionExtensions.cs`

### RESIL-02: Add auto-scaling rules for production
- [ ] Create `Microsoft.Insights/autoscaleSettings` resource
- [ ] Scale out: CPU > 70% over 5 min → add 1 instance (max 4)
- [ ] Scale in: CPU < 30% over 10 min → remove 1 instance (min 2)
- [ ] Add memory-based scaling as secondary trigger
- **Prerequisite**: SCALE-01 (Standard tier minimum for auto-scale)

### OBS-01: Add Azure Monitor workbook / dashboard
- [ ] Create operational dashboard: request rate, error rate, p50/p95/p99 latency, dependency health
- [ ] Export as ARM/Bicep template for IaC deployment
- [ ] Add to `infra/modules/` as `dashboard.bicep`

### OBS-02: Add availability tests (synthetic monitoring)
- [ ] Create `Microsoft.Insights/webtests` pinging `/health/ready` from 3+ regions
- [ ] Frequency: every 5 minutes
- [ ] Alert on 2 consecutive failures from 2+ locations
- **Prerequisite**: SEC-04 (health endpoints)

### CICD-05: Add automated rollback on deployment failure
- [ ] If post-deploy health check fails → automatic slot swap back (if slots enabled)
- [ ] If no slots → redeploy last known-good artifact from GitHub Actions cache
- [ ] Add failure notification to team (Slack/Teams webhook or email)
- **Prerequisite**: CICD-01 (deployment slots)

### DB-02: Migrate SQL auth to Managed Identity (passwordless)
- [ ] Configure Azure SQL to accept AAD-only authentication
- [ ] Grant App Service managed identity `db_datareader` + `db_datawriter` roles
- [ ] Update EF Core connection string to use `Authentication=Active Directory Managed Identity`
- [ ] Remove SQL password from all config files (complements SEC-01)
- **Impact**: Eliminates SQL credentials entirely — strongest production posture

### DOC-01: Create operational runbooks
- [ ] `docs/runbooks/incident-response.md` — escalation matrix, first-responder procedures
- [ ] `docs/runbooks/rollback-procedure.md` — manual rollback steps for each component
- [ ] `docs/runbooks/secret-rotation.md` — steps to rotate OIDC, KV secrets, SQL password, OpenPay keys
- [ ] `docs/runbooks/disaster-recovery.md` — RTO/RPO targets, failover procedures

---

## P3 — PERFECT (Gold-Standard, Defense-in-Depth)

### NET-02: Add Azure Front Door with WAF
- [ ] Deploy Azure Front Door for global load balancing + DDoS protection
- [ ] Add WAF policy with OWASP 3.2 managed rules
- [ ] Configure custom rules: rate limiting, geo-filtering
- [ ] CDN for UI static assets
- **Cost**: $35-100/month (justified for public-facing production)

### DB-03: Add SQL failover group (disaster recovery)
- [ ] Create secondary SQL Server in paired Azure region (e.g., `southindia`)
- [ ] Configure auto-failover group with 1-hour grace period
- [ ] Test failover quarterly
- **Cost**: ~2x database cost (read replica)

### RESIL-03: Implement feature flags (Azure App Configuration)
- [ ] Add `Microsoft.AppConfiguration` resource
- [ ] Integrate `Microsoft.FeatureManagement` NuGet package
- [ ] Use feature flags for gradual rollouts and kill switches
- **Impact**: Decouple deployment from release — deploy code anytime, enable features when ready

### OBS-03: Add custom business metrics to App Insights
- [ ] Track orders/minute, payment success rate, average order value
- [ ] Create custom metrics in `TelemetryClient`
- [ ] Build KPI dashboard in Azure Monitor Workbooks
- **Prerequisite**: INFRA-01 (workspace-based App Insights)

### CICD-06: Implement canary deployments
- [ ] Route 10% traffic to new version → monitor error rates → gradually increase
- [ ] Requires Front Door or App Service traffic routing
- **Prerequisite**: NET-02 (Front Door), CICD-01 (slots)

### CICD-07: Add integration test suite in pipeline
- [ ] Create `XYDataLabs.OrderProcessingSystem.IntegrationTest` project
- [ ] Test API endpoints against ephemeral test database
- [ ] Run in CI before deployment
- **Impact**: Catches issues that unit tests miss (EF Core queries, middleware, auth)

### SEC-05: Implement managed identity for all inter-service communication
- [ ] SQL → Managed Identity (see DB-02)
- [ ] Key Vault → Managed Identity (already done ✅)
- [ ] App Configuration → Managed Identity
- [ ] Eliminate ALL stored credentials from runtime config

---

## Suggested Implementation Roadmap

| Sprint | Focus | Items |
|--------|-------|-------|
| **Sprint 1** | Security remediation | SEC-01, SEC-02, SEC-03, SEC-04 |
| **Sprint 2** | CI/CD hardening | CICD-01, CICD-02, CICD-03, CICD-04, SCALE-01 |
| **Sprint 3** | Observability | INFRA-01, INFRA-02, OBS-01, OBS-02 |
| **Sprint 4** | Resilience | RESIL-01, RESIL-02, INFRA-03, DB-01 |
| **Sprint 5** | Network & DR | NET-01, DB-02, DOC-01 |
| **Sprint 6+** | Gold-standard | NET-02, DB-03, RESIL-03, OBS-03, CICD-05, CICD-06, CICD-07 |

---

## Quick Wins (< 1 hour each)

- [ ] SEC-02 — Add `enablePurgeProtection: true` (2 lines in 2 files)
- [ ] DB-01 — Change backup redundancy to `'Geo'` for prod (1 line)
- [ ] CICD-03 — Add CodeQL workflow (copy template, ~20 lines)
- [ ] CICD-04 — Add `curl --fail` health check step to deploy workflows (~5 lines each)

---

> **Note**: This project is explicitly a **learning project** for Azure. Many P2/P3 items represent
> aspirational targets. Focus on P0 (security) first — these are non-negotiable for any real deployment.
> P1 items establish a credible enterprise baseline. P2/P3 demonstrate mastery.
