# Active Work

## Last Session
- 2026-06-29: Verified `staging` after the `dev` merge with a clean tree, clean solution build, and passing Domain/Application/Gateway/Integration test suites.
- Recorded the validation outcome in the phase closeout surfaces and merged the validated `dev` commit into `staging`.
- Captured the automation dry-run result: local and docker-dev-http passed; Azure dry-run failed on external SQL auth in the sandbox and was treated as environment-specific.

## Pending / Next Actions
- Start the Phase 10 Azure transport + DLQ operations work when ready.
- If more closeout metadata changes happen, re-run the context audit so the prompt/index surfaces stay aligned.

## Recent Key Facts
- Phase 9 closeout and Phase 9.5 portability are now treated as complete in the main status surfaces.
- Phase 10 is the next active engineering phase.
- `dev` was merged to `staging` as commit `25d9e12`.
- The Phase 9 closeout prompts require documented, aligned VS Code task sequences for `local-http` and `docker-dev-http`.
- Azure infra naming and teardown should stay environment-scoped and symmetric:
  - Resource groups use `rg-<base>-<env>`
  - App/service names use `<base>-<service>-<env>` for Phase 10 infra and matching cleanup
  - Phase 10 ACA abbreviations are `gate`, `ord`, `inv`, `notif`, and `ui`
  - Phase X cleanup in `azure-bootstrap.yml` is the matching teardown for the same environment stack
  - Service Bus and related transport names in Phase 10 should also carry the environment suffix so deploy and cleanup stay aligned
- Phase 10 deployment summaries should publish Container App ingress URLs for the gateway and UI; old `azurewebsites.net` links are legacy App Service paths.
- Going forward, any new Azure service, queue, topic, subscription, or similar infra should follow the same `appname-env` pattern for easy identification and cleanup.

## If returning after a long gap
- Current focus: Phase 10 Azure transport + DLQ operations.
- Last known closeout status: Phase 9 and Phase 9.5 are complete, and the validated `dev` merge is now on `staging`.
- Watch for drift in `.github/prompts/README.md`, `.github/copilot-instructions.md`, `ARCHITECTURE-EVOLUTION.md`, and the curriculum/status docs before making any new phase claim.
