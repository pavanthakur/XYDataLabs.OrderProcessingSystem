# Active Work

Session navigation only—not proof. Verify current Git, code, evidence and runtime state before acting.

## Checkpoint — 12 November 2026

- Acceptance candidate: `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe` (`dev`), clean at both E2E and NFR start/finish. Current branch tip before Checkpoint A work was `fb3e74ad`; the worktree now contains uncommitted CI-hardening changes. Verify Git before binding any new evidence.
- Review revision: `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe`
- Worktree state: `UNKNOWN`
- Verify Git state before continuing.
- Evidence revision: `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe`
- Evidence environment: `LOCAL DOCKER DESKTOP ON G:`
- Evidence scope: `bounded non-Azure local Docker acceptance; not full Phase 10 or Azure acceptance`
- Evidence reference: `TestResults/Phase10/accepted/phase10-local-acceptance-494ab4fd.json`
- Evidence status: `HISTORICAL`
- The pinned candidate's recorded verdict is **PASS, bounded non-Azure local acceptance**. Do not describe this as full Phase 10 closure or Azure acceptance.
- E2E: `phase10-docker-http-20261111-230915653`; NFR: `phase10-docker-nfr-20261111-234505649`; the v4 reconciler returned PASS with all 13 image identities equal. Sanitized tracked summary: `TestResults/Phase10/accepted/phase10-local-acceptance-494ab4fd.json`.
- E2E passed cold build, foundations, smoke, isolated integration, identity, deterministic and sandbox journeys (TenantA/B/C × Razorpay/OpenPay), messaging/Functions, persistence after Docker restart, and settings restoration. Six positives per payment mode; six Razorpay failure/cancellation cases passed.
- NFR passed all categories: 100/100 messages/effects at 2.273 s P95; replay visibility 1.080 s; outage recovery 26.201 s, zero lost/duplicate effects; retained Inventory rollback and restore passed. L5-R HTML had no issues and measured backend, frontend, and integration coverage.
- L6 A passed on this candidate (42 architecture-invariant tests + 1 Gateway topology test). L6 B passed with bounded local evidence. L6 C passed under DW-028 Option A: Drift Scanner, AI Customization Windows/Linux, and Documentation Links passed on this SHA; workflow `99` hosted parity is excluded. See the checklist for action links and limits.
- L6 C is closed/PASS for `494ab4fd` under Option A; no corrective rerun is required for that candidate. Azure and the separate combined `l6-ci-parity-and-azure` report gate remain NOT-RUN; that combined gate is not non-Azure L6 C. Checkpoint A CI improvements do not reopen the accepted verdict or certify later candidates. DW-023/DW-024 remain Phase 11 deferrals. Fulfillment, installments, unresolved-payment recovery, visible OpenPay 3DS, Razorpay S2S, and ACA revision rollback remain uncertified.

## Current implementation checkpoint — 12 November 2026

- Phase 10 Azure-readiness implementation candidate on `dev` is `6f6723ed904652caef368477d24e0b3fe95cd7f7` (`Align release checks with optional ADR validation`), following implementation commit `ef43d8c925f77f29d2dc9e91c1ee0f648f44dce1`. Later edits to the candidate record are documentation-only; verify the current branch tip before binding new evidence.
- Implemented: six digest-qualified application images plus Functions package provenance; exact release-run, hosted-evidence and deployment-parameter identity checks; read-only subscription/RBAC/provider preflight; dedicated Functions host StorageV2 account and user-assigned managed identity (`Storage Blob Data Owner`); verified deployed ZIP identity; deployment defaults to dry-run. User selected dedicated Storage + managed identity. No ACR publication, Azure provisioning, `what-if`, deployment, payment or directory write occurred.
- Hosted checks on exact HEAD `6f6723ed`: CI [43145783893](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43145783893), Drift Scanner [43145783824](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43145783824), AI Customization [43145783812](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43145783812), and AI Prompts [43145783839](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43145783839) passed. ADR validation [43145783776](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43145783776) was skipped because `ADR_VALIDATION_ENABLED` is not enabled; release verification now treats it as optional, not PASS. Focused release-run tests passed 6/6 after that correction. CI reported existing analyzer and Node 20 deprecation warnings; no failures.
- **Open release blocker:** source-branch/environment and exact-workflow-SHA equality prevent reusing one immutable artifact across dev→staging/main after merges change the commit SHA. Keep these guards. Design and test artifact-source SHA vs deployment-workflow revision before staging/main rollout. Remote staging is two commits behind/ahead relative to dev (2 target-only, 3 dev-only); main is substantially divergent. Do not merge while Azure branch-trigger behavior and the promotion policy are unresolved.
- Azure target permissions (`roleAssignments/write`), quotas, SKU cost, OIDC/RBAC state and real service readiness are not verified. Azure preflight/what-if/deployment and payment acceptance remain NOT-RUN. Historical Docker/L6 PASS is still limited to `494ab4fd`; it does not certify this candidate or Azure.

## Next action

Resolve and test the immutable-artifact promotion policy, then review branch-trigger behavior before separately approving any staging/main sync. For Azure dev, next obtain scoped approval for read-only preflight and Bicep what-if; resource creation/deployment remains a separate approval. Do not publish ACR images, create billable Azure resources, run payments, or merge branches automatically.

## Safety / navigation

- Local Docker SQL is loopback `14330`; native Windows SQL is `1433` and must remain untouched. Verify project ownership/physical SQL identity before separately approved DB work.
- The owner deleted `F:\DockerRetained\DockerDesktopWSL-before-G`; it is not a recovery backup. Do not touch unrelated F: backups.
- Preserve Docker volumes, provider settings and payment history. No resets, global prune, VHDX compaction, charges/refunds, Azure/directory writes or Git writes without explicit scoped approval.
- For older payment-history/currency and continuation limits, consult the existing runbook and Phase 11 deferral record; never infer old order state, force Paid, or retry/refund to resolve uncertainty.
- Canonical Phase 10 details: `docs/internal/phase10-implementation-checklist.md`; architecture and gate definitions: `docs/internal/phase10-preazure-lld.md`.
