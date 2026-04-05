# Archive Deletion File-by-File Review

This review is intentionally blunt. It does not assume every deletion was lossless.

Verdict meanings:
- `Safe`: active canonical replacement exists and deleting the archived copy is not meaningful loss.
- `Safe - convenience lost`: substance is covered by implemented repo assets or current guides; only shortcut summaries, informal framing, or convenience packaging disappeared.
- `Safe - roadmap coverage`: the deleted file described future work; surviving coverage exists in the active roadmap/master-plan rather than in implemented code.
- `Safe - mixed coverage`: part of the substance is implemented now and the rest survives as active roadmap coverage; no extra promotion is required.

Coverage basis meanings:
- `Implemented`: the surviving replacement is backed by actual repo assets or current guides for features that already exist.
- `Planned`: the surviving replacement is roadmap coverage in `1_MASTER_CURRICULUM.md`, `AZURE-PROGRESS-EVALUATION.md`, `ARCHITECTURE-EVOLUTION.md`, or ADRs, not implemented code.
- `Promoted before safe deletion`: the original gap was real, but the important reasoning has now been preserved in an active canonical document.

## Archive Index

### `docs/archive/README.md`
- Purpose: index page for the retired archive tree.
- Active coverage now lives in `docs/README.md` and `docs/DEVELOPER-OPERATING-MODEL.md`.
- Once `docs/archive/` was deleted, this file had no remaining navigation role.
- No subject-matter guidance was lost; only the map of a deleted folder disappeared.
- Verdict: `Safe`.

## Historical Internal Notes

### `docs/archive/historical-notes/internal/AZURE-TOP-7-SERVICES-ANALYSIS.md`
- Purpose: meta-analysis of whether the curriculum covered the top seven Azure services.
- The resulting coverage snapshot survives in `docs/learning/curriculum/1_MASTER_CURRICULUM.md` and the concrete additions survive in `docs/internal/AZURE-PROGRESS-EVALUATION.md`.
- Cosmos DB, Storage Queues, and APIM were all carried forward into the active plan.
- The original rationale has now been preserved in `docs/architecture/decisions/ADR-014-azure-service-coverage-rationale.md`, with the curriculum linked back to it.
- Coverage basis: `Promoted before safe deletion`.
- Verdict: `Safe`.

### `docs/archive/historical-notes/internal/GITHUB-APP-DELETION-SUMMARY.md`
- Purpose: executive summary for deleting and recreating the GitHub App safely.
- Active guidance now lives in `docs/guides/configuration/quick-setup-github-app.md`, `docs/guides/configuration/github-app-authentication.md`, `.github/workflows/README.md`, and `scripts/README.md`.
- The deletion/recreation procedure is still operationally covered through current setup and validation guidance.
- Actual repo assets also exist: `.github/app-manifest.json`, `scripts/setup-github-app-from-manifest.ps1`, and `scripts/validate-github-app-config.ps1`.
- Coverage basis: `Implemented`.
- Verdict: `Safe - convenience lost`.

### `docs/archive/historical-notes/internal/GITHUB-APP-QUICK-REFERENCE.md`
- Purpose: command card and URL cheat sheet for GitHub App setup and validation.
- Equivalent operational content exists across `docs/guides/configuration/quick-setup-github-app.md`, `docs/guides/configuration/github-app-authentication.md`, `.github/workflows/README.md`, and `scripts/README.md`.
- The repo still contains the setup script, validation script, workflow entry points, and secret expectations.
- Coverage basis: `Implemented`.
- Verdict: `Safe - convenience lost`.

### `docs/archive/historical-notes/internal/IMPLEMENTATION-COMPLETE.md`
- Purpose: milestone/status note saying a GitHub App automation implementation was finished.
- The real assets named in that note still exist in the repo: `.github/app-manifest.json`, setup/validation scripts, workflow docs, and configuration guides.
- Status declarations are not durable documentation once the actual implementation and canonical instructions exist.
- Deleting this file removed a celebration marker, not an operating dependency.
- Verdict: `Safe`.

## Historical Learning Help

### `docs/archive/historical-notes/self-learning/learning-help/DockerHelp.md`
- Purpose: beginner-facing Docker startup and troubleshooting help.
- Active coverage now exists in `docs/guides/development/docker-comprehensive-guide.md`, `docs/guides/development/visual-studio-docker-profiles.md`, and `docs/guides/development/project-overview.md`.
- The current guides are broader, more canonical, and tied to the actual scripts and environment model.
- The surviving docs match actual repo assets such as `Resources/Docker/start-docker.ps1` and the current Docker profiles.
- Coverage basis: `Implemented`.
- Verdict: `Safe - convenience lost`.

### `docs/archive/historical-notes/self-learning/learning-help/sharedsettingsHelp.md`
- Purpose: explanation of the sharedsettings-based multi-environment configuration model.
- Active coverage now lives in `docs/guides/development/docker-comprehensive-guide.md`, `docs/guides/configuration/key-vault-integration.md`, `docs/guides/configuration/keyvault-setup.md`, and `docs/reference/quick-command-reference.md`.
- The sharedsettings pattern, Docker environment mapping, and Key Vault transition are all still documented.
- The surviving docs match actual repo assets such as `Resources/Configuration/sharedsettings.*.json`, `SharedSettingsLoader.cs`, and the validation scripts.
- Coverage basis: `Implemented`.
- Verdict: `Safe - convenience lost`.

## Historical Azure Migration TODO Notes

### `docs/archive/historical-notes/self-learning/todo/azure-migration/01_AZURE_CLOUD_MIGRATION_STRATEGY.md`
- Purpose: early planning note for cloud migration sequencing.
- Active strategy now lives in `ARCHITECTURE-EVOLUTION.md`, `docs/guides/deployment/aca-migration-plan.md`, and `docs/learning/curriculum/1_MASTER_CURRICULUM.md`.
- The current roadmap documents own the live migration path and sequencing decisions.
- The deleted file may have contained earlier brainstorming, but it is no longer the decision source.
- Coverage basis: `Planned`.
- Verdict: `Safe - roadmap coverage`.

### `docs/archive/historical-notes/self-learning/todo/azure-migration/02_DATABASE_CLOUD_MIGRATION.md`
- Purpose: planning note for database migration to Azure.
- Active coverage now lives in `docs/guides/deployment/aca-migration-plan.md`, `docs/learning/curriculum/1_MASTER_CURRICULUM.md`, and `docs/architecture/decisions/ADR-004-ef-core-azure-sql.md`.
- Azure SQL remains the canonical primary-store decision, and the curriculum covers the migration work.
- What was removed was early planning detail, not the active database migration model.
- Coverage basis: `Planned`.
- Verdict: `Safe - roadmap coverage`.

### `docs/archive/historical-notes/self-learning/todo/azure-migration/03_EF_CORE_CLOUD_PATTERNS.md`
- Purpose: exploratory note on EF Core patterns for cloud deployment.
- Active coverage now exists in `docs/architecture/decisions/ADR-004-ef-core-azure-sql.md`, `docs/learning/curriculum/1_MASTER_CURRICULUM.md`, and `docs/learning/implementation-notes/implementation-notes-days-29-38.md`.
- The canonical sources now capture the actual adopted EF Core direction instead of speculative pattern notes.
- Some exploratory rationale is gone, but the chosen patterns remain documented.
- Coverage basis: `Planned`.
- Verdict: `Safe - roadmap coverage`.

### `docs/archive/historical-notes/self-learning/todo/azure-migration/04_MULTI_ENVIRONMENT_CLOUD_SETUP.md`
- Purpose: planning note for multi-environment Azure setup.
- Active coverage now lives in `docs/guides/deployment/quick-start-azure-bootstrap.md`, `docs/guides/deployment/azure-deployment-guide.md`, and `.github/workflows/README.md`.
- Branch-to-environment mapping, OIDC setup, secrets, and bootstrap sequencing are all covered in canonical docs.
- The deleted file was superseded planning, not the authoritative environment setup guide.
- Verdict: `Safe`.

### `docs/archive/historical-notes/self-learning/todo/azure-migration/05_DATABASE_ARCHITECTURE_INSIGHTS.md`
- Purpose: database architecture thought process during Azure migration planning.
- Active architectural decisions now live in `docs/architecture/decisions/ADR-004-ef-core-azure-sql.md`, `ARCHITECTURE.md`, and `ARCHITECTURE-EVOLUTION.md`.
- The repo’s current position on relational primary storage, tenant isolation, and Cosmos read models is documented elsewhere.
- What disappeared is idea-stage analysis, not the adopted database architecture.
- Coverage basis: `Planned`.
- Verdict: `Safe - roadmap coverage`.

### `docs/archive/historical-notes/self-learning/todo/azure-migration/06_EF_CORE_STANDARDIZATION.md`
- Purpose: note on standardizing EF Core practices.
- Active coverage is spread across `docs/architecture/decisions/ADR-004-ef-core-azure-sql.md`, `docs/learning/curriculum/1_MASTER_CURRICULUM.md`, and the implementation notes.
- The actual standards that matter are now enforced by code, architecture tests, and the chosen ADRs.
- Some intermediate standardization thinking may be gone, but the standard itself is not dependent on this file.
- Coverage basis: `Planned`.
- Verdict: `Safe - roadmap coverage`.

### `docs/archive/historical-notes/self-learning/todo/azure-migration/07_CLOUD_TESTING_STRATEGIES.md`
- Purpose: planning note for cloud-focused testing strategy.
- Active testing expectations now live in `README.md`, `docs/learning/curriculum/1_MASTER_CURRICULUM.md`, `docs/reference/quick-command-reference.md`, and the actual `tests/` projects.
- The repo now expresses testing strategy through implemented test projects and execution commands, not a loose TODO note.
- This is one of the weaker replacements for narrative reasoning, but it is still not an operational dependency.
- Coverage basis: `Implemented` for test assets, `Planned` for the broader cloud-testing narrative.
- Verdict: `Safe - mixed coverage`.

### `docs/archive/historical-notes/self-learning/todo/azure-migration/08_PRODUCTION_CONFIGURATION_PATTERNS.md`
- Purpose: planning note for production-grade configuration patterns.
- Active coverage now lives in `docs/guides/configuration/key-vault-integration.md`, `docs/guides/configuration/appservice-secrets-guide.md`, and `docs/guides/configuration/infrastructure-security-notes.md`.
- The current docs cover Key Vault, secrets handling, managed identity, and production configuration posture directly.
- Deleting the old planning note did not remove the repo’s actual production configuration guidance.
- Verdict: `Safe`.

## Historical Microservices Architecture TODO Notes

### `docs/archive/historical-notes/self-learning/todo/microservices-architecture/01_MICROSERVICES_ARCHITECTURE_DESIGN.md`
- Purpose: early decomposition plan for future microservices.
- Active coverage now lives in `ARCHITECTURE-EVOLUTION.md`, `docs/guides/deployment/aca-migration-plan.md`, and later curriculum phases.
- Service decomposition, migration order, and platform direction are now documented in the active roadmap instead of a draft planning note.
- Some richer brainstorming examples were lost, but the execution path remains covered.
- Coverage basis: `Planned`.
- Verdict: `Safe - roadmap coverage`.

### `docs/archive/historical-notes/self-learning/todo/microservices-architecture/02_ENTERPRISE_PATTERNS_REFERENCE.md`
- Purpose: pattern brainstorm for enterprise microservice implementation.
- Active coverage now exists in `ARCHITECTURE.md`, the ADR set under `docs/architecture/decisions/`, and the curriculum phases on event-driven architecture and CQRS.
- The actual non-negotiable patterns are better expressed as ADRs and active curriculum checkpoints.
- What was lost is reference-style brainstorming, not the enforced architectural stance.
- Coverage basis: `Planned`.
- Verdict: `Safe - roadmap coverage`.

### `docs/archive/historical-notes/self-learning/todo/microservices-architecture/03_DATABASE_MICROSERVICES_DESIGN.md`
- Purpose: planning note for per-service data strategy.
- Active coverage now lives in `ARCHITECTURE-EVOLUTION.md`, `docs/architecture/decisions/ADR-004-ef-core-azure-sql.md`, and the Cosmos DB/CQRS sections of the curriculum.
- Database-per-service, relational primary storage, and Cosmos read model ideas are represented elsewhere.
- The deleted file may have had more speculative examples, but not unique operating decisions.
- Coverage basis: `Planned`.
- Verdict: `Safe - roadmap coverage`.

### `docs/archive/historical-notes/self-learning/todo/microservices-architecture/04_FOUNDATION_ARCHITECTURE_PATTERNS.md`
- Purpose: note on foundational architecture patterns for the future platform.
- Active coverage now lives in `ARCHITECTURE.md`, `ARCHITECTURE-EVOLUTION.md`, and the ADR set.
- The repo now documents foundation patterns as binding constraints and phased execution, which is stronger than a planning note.
- Deleting the draft did not remove the governing architecture source.
- Verdict: `Safe`.

## Historical Technical Enhancement TODO Notes

### `docs/archive/historical-notes/self-learning/todo/technical-enhancements/01_TECHNICAL_EXCELLENCE_ROADMAP.md`
- Purpose: generic roadmap for technical improvements.
- Active coverage now lives in `docs/learning/curriculum/1_MASTER_CURRICULUM.md`, `ARCHITECTURE-EVOLUTION.md`, and the ADR set.
- The current roadmap documents already own planned technical improvements in a more actionable form.
- The deleted note was a backlog-style precursor, not the current execution contract.
- Coverage basis: `Planned`.
- Verdict: `Safe - roadmap coverage`.

### `docs/archive/historical-notes/self-learning/todo/technical-enhancements/02_INFRASTRUCTURE_IMPROVEMENTS.md`
- Purpose: backlog note for infrastructure improvements.
- Active coverage now lives in `docs/internal/azure-bootstrap-improvements-backlog.md`, `docs/guides/deployment/azure-deployment-guide.md`, and `docs/guides/deployment/quick-start-azure-bootstrap.md`.
- The internal backlog is the correct active owner for pending infra improvements.
- The deleted file would only have duplicated backlog material already tracked elsewhere.
- Verdict: `Safe`.

### `docs/archive/historical-notes/self-learning/todo/technical-enhancements/03_ENTERPRISE_DOCKER_PATTERNS.md`
- Purpose: planning note for enterprise Docker patterns.
- Active coverage now exists in `docs/guides/development/docker-comprehensive-guide.md`, `docs/guides/development/visual-studio-docker-profiles.md`, and `docs/reference/docker-enterprise-quick-reference.md`.
- The repo already documents concrete Docker usage, environment profiles, and enterprise checks in canonical locations.
- Some exploratory comparison text may be gone, but not the actual Docker guidance.
- Verdict: `Safe`.

### `docs/archive/historical-notes/self-learning/todo/technical-enhancements/04_DOCKER_STRATEGY_GUIDE.md`
- Purpose: strategic note on Docker direction.
- Active coverage now lives in `docs/guides/development/docker-comprehensive-guide.md`, `docs/guides/development/project-overview.md`, and the learning reference material.
- The canonical development guides already express the adopted Docker strategy and operating modes.
- This deletion removed planning narrative, not a required guide.
- Coverage basis: `Implemented` for current Docker usage, `Planned` for future container-platform direction.
- Verdict: `Safe - mixed coverage`.

### `docs/archive/historical-notes/self-learning/todo/technical-enhancements/05_DEVELOPMENT_WORKFLOW_INSIGHTS.md`
- Purpose: note of workflow learnings and developer-process ideas.
- Active operational workflow now lives in `docs/reference/git-workflow.md`, `docs/reference/quick-command-reference.md`, and `docs/guides/development/project-overview.md`.
- The current docs capture the commands and process a contributor actually needs to follow.
- Informal insight text is gone, but the maintained workflow surface remains.
- Coverage basis: `Implemented`.
- Verdict: `Safe - convenience lost`.

## Historical Weekly Plan

### `docs/archive/historical-notes/self-learning/weekly-plans/WEEKLY_AZURE_LEARNING_PLAN.md`
- Purpose: older weekly execution plan before the master curriculum matured.
- Active coverage now lives in `docs/learning/curriculum/1_MASTER_CURRICULUM.md` and `docs/internal/AZURE-PROGRESS-EVALUATION.md`.
- Those two docs now own daily execution and milestone tracking explicitly.
- The weekly-plan format itself was removed, but the active plan was not.
- Coverage basis: `Planned`.
- Verdict: `Safe - roadmap coverage`.

## Archived Legacy Documentation Copies

### `docs/archive/legacy-documentation/ACA-Migration-Plan.md`
- Purpose: archived copy of the ACA migration roadmap.
- Active replacement is `docs/guides/deployment/aca-migration-plan.md`.
- The curriculum and progress tracker both point to the canonical roadmap, not the archived copy.
- Deleting this file removed a duplicate copy, not the roadmap itself.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/APP_INSIGHTS_AUTOMATED_SETUP.md`
- Purpose: archived copy of the App Insights setup guide.
- Active replacement is `docs/guides/configuration/app-insights-automated-setup.md`.
- The current guide is already the referenced configuration source for telemetry setup.
- Deleting the archived copy does not remove any required setup guidance.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/AZURE_DEPLOYMENT_GUIDE.md`
- Purpose: archived copy of the main Azure deployment guide.
- Active replacement is `docs/guides/deployment/azure-deployment-guide.md`.
- The current deployment guide is the maintained source referenced from the docs hub.
- The archived file was redundant once the canonical guide existed.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/AZURE_README.md`
- Purpose: archived Azure-guides overview page.
- Active replacement is `docs/guides/deployment/azure-guides-overview.md`.
- The current overview page already routes readers to the maintained deployment guides.
- This deletion removed a duplicate hub, not a unique guide family.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/BOOTSTRAP_SCRIPT_FLOW.md`
- Purpose: archived bootstrap execution-flow guide.
- Active replacement is `docs/guides/deployment/bootstrap-script-flow.md`.
- The live deployment docs already point to the maintained flow explanation.
- Deleting the archived copy did not remove the bootstrap sequencing guide.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/Containerization-ACA-Aspire-Learning-Path.md`
- Purpose: archived copy of the containerization learning path.
- Active replacement is `docs/learning/reference/containerization-aca-aspire-learning-path.md`.
- The master curriculum still references the active learning-path document directly.
- This was a duplicate historical copy, not the current learning reference.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/DOCKER_COMPREHENSIVE_GUIDE.md`
- Purpose: archived copy of the full Docker guide.
- Active replacement is `docs/guides/development/docker-comprehensive-guide.md`.
- The development hub and related docs already route users to the canonical guide.
- Deleting the archive copy does not remove Docker operating guidance.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/GITHUB-WORKFLOW-SEPARATION-ARCHITECTURE.md`
- Purpose: archived rationale for splitting setup and bootstrap workflows.
- Active replacement is `docs/guides/deployment/workflow-separation-architecture.md`.
- The workflow split is also reflected in `.github/workflows/README.md` and repo memory.
- The archived copy was redundant after the canonical guide was established.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/Operations-Quick-Links-README.md`
- Purpose: archived operational navigation hub.
- Active replacement is `docs/reference/operations-quick-links.md`.
- The reference hub already exposes the canonical operations quick-links document.
- Deleting the archived copy did not reduce operational navigation coverage.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/QUICK-COMMAND-REFERENCE.md`
- Purpose: archived consolidated command reference.
- Active replacement is `docs/reference/quick-command-reference.md`.
- The command family under `docs/reference/` is now the maintained command surface.
- Removing the archived version is pure duplicate removal.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/QUICK-START-AZURE-BOOTSTRAP.md`
- Purpose: archived quick-start guide for bootstrap.
- Active replacement is `docs/guides/deployment/quick-start-azure-bootstrap.md`.
- Deployment and workflow docs still point to the canonical quick-start.
- The archived file added no active guidance beyond the maintained guide.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/README.md`
- Purpose: archived copy of the old documentation hub.
- Active replacement is `docs/README.md`.
- The active documentation hub is now shorter, cleaner, and the only canonical entry point.
- Deleting the archived hub is not a knowledge loss because the subject matter lives elsewhere.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/SKU_UPGRADE_SLOT_TESTING.md`
- Purpose: archived guide for App Service slot and SKU testing.
- Active replacement is `docs/guides/deployment/sku-upgrade-slot-testing.md`.
- The deployment guide family still contains the maintained slot-testing procedure.
- The deleted file was only an extra copy.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/TODO-AZURE-BOOTSTRAP-IMPROVEMENTS.md`
- Purpose: archived bootstrap improvement backlog.
- Active replacement is `docs/internal/azure-bootstrap-improvements-backlog.md`.
- The internal backlog is the correct live owner for pending bootstrap work.
- Keeping the archived backlog would only split one backlog into two versions.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/VISUAL_STUDIO_DOCKER_PROFILES.md`
- Purpose: archived Visual Studio Docker-profile guide.
- Active replacement is `docs/guides/development/visual-studio-docker-profiles.md`.
- The current development docs still explain profile usage and sharedsettings integration.
- Deleting the archived copy removed duplication, not guidance.
- Verdict: `Safe`.

## Archived Command Reference Copies

### `docs/archive/legacy-documentation/commands/azure-infra.md`
- Purpose: archived Azure infrastructure command reference.
- Active replacement is `docs/reference/azure-infra.md`.
- The reference hub still routes users to the canonical infra commands page.
- Deleting the archived copy is operationally lossless.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/commands/azure-sql-ef.md`
- Purpose: archived Azure SQL and EF Core command reference.
- Active replacement is `docs/reference/azure-sql-ef.md`.
- The command set remains available and still hangs off the quick-command reference hub.
- The deleted copy was redundant.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/commands/git-workflow.md`
- Purpose: archived git workflow command reference.
- Active replacement is `docs/reference/git-workflow.md`.
- The active docs still capture validation, commit, and branch workflow commands.
- The archived copy added no unique operational value.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/commands/local-dev.md`
- Purpose: archived local-development command reference.
- Active replacement is `docs/reference/local-dev.md`.
- Local dev commands remain documented under the reference family.
- Deleting the historical copy is not a loss of current run guidance.
- Verdict: `Safe`.

## Archived Configuration Guide Copies

### `docs/archive/legacy-documentation/configuration-guides/AZURE-APPSERVICE-SECRETS-GUIDE.md`
- Purpose: archived App Service secrets guide.
- Active replacement is `docs/guides/configuration/appservice-secrets-guide.md`.
- Secrets, OIDC, and deployment credential expectations remain documented in the current config guide.
- The deleted copy was redundant once the canonical guide existed.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/configuration-guides/GITHUB-APP-AUTHENTICATION.md`
- Purpose: archived GitHub App authentication guide.
- Active replacement is `docs/guides/configuration/github-app-authentication.md`.
- Authentication flow and secret handling still live in the canonical configuration docs.
- The archive copy was not the active owner of this topic.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/configuration-guides/KEY-VAULT-INTEGRATION.md`
- Purpose: archived Key Vault integration guide.
- Active replacement is `docs/guides/configuration/key-vault-integration.md`.
- Managed identity, secret precedence, and sharedsettings override behavior remain covered in the current guide.
- Deleting the archived duplicate is not a knowledge loss.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/configuration-guides/QUICK-SETUP-GITHUB-APP.md`
- Purpose: archived quick setup guide for GitHub App onboarding.
- Active replacement is `docs/guides/configuration/quick-setup-github-app.md`.
- The quick-start still exists in the maintained config guide family.
- The old copy was redundant once the canonical quick-start existed.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/configuration-guides/WORKFLOW-AUTOMATION-VISUAL-GUIDE.md`
- Purpose: archived visual guide for workflow automation and secret setup.
- Active replacement is `docs/guides/configuration/workflow-automation-visual-guide.md`.
- The visual guidance and workflow relationships are still present in the canonical guide.
- Deleting the archive copy is lossless from an operating perspective.
- Verdict: `Safe`.

## Archived Curriculum and Learning Copies

### `docs/archive/legacy-documentation/curriculum-IMPLEMENTATION_NOTES.md`
- Purpose: archived older implementation-notes document.
- Active replacement is `docs/learning/implementation-notes/implementation-notes-days-29-38.md`.
- Implementation evidence still exists in the active learning tree where contributors now expect to find it.
- The archive copy was a retained snapshot, not the source of truth.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/curriculum-README.md`
- Purpose: archived curriculum navigation guide.
- Active replacement is `docs/learning/curriculum/README.md`.
- The current learning hub and curriculum README already route readers correctly.
- Deleting the archived copy is duplicate removal, not capability loss.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/project-overview.md`
- Purpose: archived project-overview and onboarding guide.
- Active replacement is `docs/guides/development/project-overview.md`.
- The development guide family now owns onboarding and local run options.
- The archive copy no longer served an active navigation purpose.
- Verdict: `Safe`.

### `docs/archive/legacy-documentation/self-learning/README.md`
- Purpose: archived hub for the old self-learning subtree.
- Active replacement is `docs/learning/README.md` plus the curriculum files under `docs/learning/curriculum/`.
- The active learning tree now owns learning navigation completely.
- Deleting the archived hub removed an obsolete structure, not the current learning path.
- Verdict: `Safe`.

## Superseded Workflow Documentation

### `docs/archive/superseded/README-AZURE-BOOTSTRAP-SETUP.md`
- Purpose: retained copy of the old pre-split bootstrap-setup workflow README.
- Active replacement is `.github/workflows/README-AZURE-BOOTSTRAP.md` together with `.github/workflows/README-AZURE-INITIAL-SETUP.md`.
- The repo now documents the two-workflow split explicitly instead of keeping the old combined setup README around.
- Deleting the superseded copy prevents readers from following a dead workflow model.
- Verdict: `Safe`.

## Bottom Line

- The `legacy-documentation/`, `commands/`, `configuration-guides/`, curriculum-copy, and superseded workflow files were overwhelmingly duplicate copies. Their deletion is mostly `Safe`.
- The `historical-notes/` area was different. Those files usually fell into one of two buckets: implemented convenience summaries or roadmap/planning notes.
- The Azure Top 7 service rationale was the only deletion that needed promotion before it became safe; that rationale now lives in `docs/architecture/decisions/ADR-014-azure-service-coverage-rationale.md`.
- The implemented-summary deletions are best read as `Safe - convenience lost`: the repo still has the real scripts, workflows, and maintained guides.
- The future-state planning deletions are best read as `Safe - roadmap coverage`: they were never implemented solution truth, but they remain represented in the master curriculum, progress tracker, roadmap docs, or ADR set.