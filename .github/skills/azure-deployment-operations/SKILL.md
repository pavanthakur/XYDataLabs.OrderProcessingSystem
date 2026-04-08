---
name: azure-deployment-operations
description: "Use when working on Azure bootstrap, deployment workflows, OIDC setup, App Service rollout checks, Bicep validation, health probes, or deployment troubleshooting for this repository."
---

# Azure Deployment Operations

Use this skill for repeatable Azure delivery work in this repository.

## Scope

Use when the task involves any of the following:

- GitHub Actions deployment workflows under `.github/workflows/`
- Azure bootstrap or initial setup flows
- OIDC credential setup or troubleshooting
- App Service deployment verification and health probes
- Bicep preflight validation or parameter consistency
- Deployment troubleshooting across `dev`, `staging`, or `prod`

Do not use this skill for:

- General C# domain or CQRS work
- UI-only work
- Local developer setup that does not touch Azure delivery behavior

## Required References

Open the relevant sources before changing deployment behavior:

- `.github/workflows/README.md`
- `.github/workflows/README-AZURE-INITIAL-SETUP.md`
- `.github/workflows/README-AZURE-BOOTSTRAP.md`
- `.github/instructions/azure-workflows.instructions.md`
- `docs/guides/deployment/README.md`
- `docs/reference/quick-command-reference.md`
- `docs/AI-OPERATING-MODEL.md` when the change touches shared AI governance surfaces

## Operating Rules

1. Keep the two-workflow split intact.
   - `azure-initial-setup.yml` is one-time setup.
   - `azure-bootstrap.yml` is the day-to-day coordinated deployment entrypoint.
2. Enforce branch-to-environment mapping.
   - `dev -> dev`
   - `staging -> staging`
   - `main -> prod`
3. Use OIDC, never stored service principal secrets.
4. Deployment readiness must fail closed.
   - API readiness probe: `/health/ready`
   - Do not use Swagger as a release gate.
5. Respect Azure naming constraints.
   - staging resource suffix is `stg`, not `staging`
6. Keep the deployment guard intact.
   - API/UI deploys must remain blocked when bootstrap fails.

## Recommended Execution Flow

1. Classify the task.
   - One-time setup
   - Day-to-day deploy
   - Infra-only validation
   - Workflow troubleshooting
2. Confirm the target environment and branch policy.
3. Identify the owning workflow, script, and README that must change together.
4. Apply the smallest safe change.
5. Validate the intended path.
   - Workflow or script validation for the changed area
   - `pwsh scripts/validate-ai-customization.ps1` if shared AI governance files changed
   - `node scripts/validate-doc-links.js` if `docs/` changed materially
6. Update the owning discovery docs so operators can still find the correct path.

## Common Checks

- If Azure login fails with `AADSTS700213`, verify the environment federated credential exists for all environments.
- If Azure login fails with `AADSTS700016`, verify the app registration and federated credential mapping.
- If bootstrap blocks deployment, treat bootstrap as the root problem and do not bypass the guard.
- If a deployment probe passes too early, inspect readiness endpoint semantics before changing retry logic.
- If parameter or configuration drift is suspected, validate the shared settings and environment parameter files together.

## Validation Path

After deployment-governance changes, prefer the same repo-standard checks used elsewhere:

- `pwsh scripts/validate-ai-customization.ps1` when `.github/` AI assets changed
- `node scripts/validate-doc-links.js` when `docs/` changed
- Focused workflow/script validation for the specific deployment path that changed

## Related Assets

- `.github/agents/azure-devops.agent.md`
- `.github/prompts/XYDataLabs-docker-start.prompt.md`
- `.github/prompts/XYDataLabs-sql-local-access.prompt.md`
- `.github/prompts/XYDataLabs-completion-check.prompt.md`
- `docs/internal/DEFERRED-WORK-LOG.md`