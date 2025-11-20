# Operations Quick Links

Purpose: Single-click access to the highest value operational artifacts for provisioning, configuring, validating, and troubleshooting the Order Processing System across environments.

## Included Items (Why)
- AZURE_DEPLOYMENT_GUIDE.md: End-to-end deployment & dry-run playbook.
- SKU_UPGRADE_TESTING_GUIDE.md: Safe process for scaling/upgrading App Service SKU.
- infra-deploy.yml / README-INFRA-DEPLOY.md: Infrastructure workflow trigger & usage details.
- Bootstrap / Provision / Migrations / App Insights / Readiness / Slots / Enterprise Test scripts: Core lifecycle tasks from first resource creation through validation & slot operations.
- Docker start & dev compose: Local container startup + environment parity.
- main.bicep + identity module: Infrastructure surface & future identity enablement reference.
- Parameters (dev/staging/prod): Quick environment knob edits.
- sharedsettings.dev.json: Configuration pattern exemplar.
- CodeAnalysis.ruleset: Shows code quality standards enforced.

## Usage Flow (Common Scenario)
1. Read AZURE_DEPLOYMENT_GUIDE.md for sequence overview.
2. Trigger infra workflow (infra-deploy.yml) with dryRun=true for validation.
3. Run bootstrap-enterprise-infra.ps1 if doing local/manual scripted provisioning.
4. provision-azure-sql.ps1 -> run-database-migrations.ps1 -> setup-appinsights-dev.ps1.
5. wait-appservice-ready.ps1 to ensure app endpoints respond.
6. test-enterprise-deployment.ps1 for post-deploy smoke tests.
7. manage-appservice-slots.ps1 for slot creation or swap operations.
8. Adjust parameters/*.json when environment changes (SKU, region) and re-run workflow.
9. If scaling: consult SKU_UPGRADE_TESTING_GUIDE.md before changing plans.

## Update Policy
- Add only artifacts used weekly or critical to bootstrap/scale/troubleshoot.
- Avoid adding long-tail self-learning or historical tracking documents.
- Remove items if superseded or rarely invoked (review monthly).

## Requesting Changes
Open an issue or PR titled: "ops-quick-links update: <short rationale>".
Include: why needed, frequency of use, and any doc link supporting addition.

## Troubleshooting Pointers
- Provision failures: check infra-deploy.yml run logs + bootstrap script output.
- Identity issues: verify identity.bicep parameters and OIDC federated credentials.
- Slow readiness: inspect wait-appservice-ready.ps1 timings & App Service diagnostics.
- Configuration drift: compare sharedsettings.*.json across environments.

## Naming Conventions
Apps: <github-username>-orderprocessing-(api|ui)-xyapp-<env>
Plan: asp-orderprocessing-<env>
Insights: ai-orderprocessing-<env>
Resource Group: rg-orderprocessing-<env>

Stay lean. Optimize navigation. Improve operator efficiency.
