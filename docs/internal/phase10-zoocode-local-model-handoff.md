# Phase 10 Zoo Code Local Model Handoff

Purpose: use Zoo Code with local models as a bounded assistant for Phase 10 staging/prod promotion planning, log triage, checklist drafting, and documentation review after the Azure dev baseline has already been validated.

This is an operator-assist lane. It does not replace the active GitHub Actions deployment path, the Phase 10 smoke workflows, or final human/Codex review before repo changes.

## Current Baseline

Dev has already validated the Phase 10 baseline:

- `00 Azure Platform Foundation` created the persistent platform ACR and pull identity.
- `01 Phase 10 Azure Deploy Orchestrator` deployed the dev app environment.
- `02 Phase 10 Azure Runtime Smoke` passed for gateway, routed API, UI shell, and UI API proxy.
- `03 Phase 10 Azure Transport Smoke` passed for Service Bus publish, fan-out, DLQ forwarding, and replay.

Next promotion focus:

1. Repeat the same sequence for `staging`.
2. Review staging evidence.
3. Promote to `prod` only after staging is green and the cleanup/rollback boundary is understood.

## Local Model Fit

Your 4 GB GPU can help reduce server load, but it should be used for scoped work.

| Work type | Good local-model fit? | Notes |
|---|---|---|
| Summarize workflow logs | Yes | Keep each prompt scoped to one run or one failure packet. |
| Draft staging/prod checklists | Yes | Use the canonical Phase 10 docs as context. |
| Compare docs for stale wording | Yes | Ask for findings first, not automatic edits. |
| Generate proposed prompts or runbooks | Yes | Review before committing. |
| Make Azure cleanup/deploy decisions | No | Use the validated workflows and explicit operator approval. |
| Modify secrets, RBAC, or workflow IAM | No | Keep this with human/Codex review. |
| Large repo-wide refactors | No | Too risky for small local models and limited context. |

Recommended model lanes:

| Lane | Suggested local model size | Use |
|---|---|---|
| Fast checklist / summary | 3B to 4B instruct/coder model | Quick Zoo Code planning and log summaries. |
| Focused code/doc review | 7B or 8B Q4 model if stable on your machine | Small file batches only. |
| Architecture escalation | Cloud/Codex or a larger local model only if available | Do not force a 4 GB GPU into large architecture prompts. |

Practical candidates:

- `qwen2.5-coder:3b` for quick planning.
- `qwen2.5-coder:7b` or a Q4 variant for focused code/doc review if it runs acceptably.
- `phi3.5`/small instruct models for fast summaries if coder models are slow.

Avoid making 14B+ models the default on this machine.

## Zoo Code Setup Options

Use one of these local backends:

| Backend | Typical endpoint | Zoo Code configuration idea |
|---|---|---|
| Ollama native | `http://localhost:11434` | Use Zoo Code's Ollama provider profile. |
| Ollama OpenAI-compatible | `http://localhost:11434/v1` | Use an OpenAI-compatible provider with a dummy API key if Zoo Code requires one. |
| LM Studio OpenAI-compatible | `http://localhost:1234/v1` | Start the local server in LM Studio, then point Zoo Code at it. |

Before using Zoo Code, confirm the local model is available:

```powershell
ollama list
ollama pull qwen2.5-coder:3b
```

Keep context small:

- Attach only the specific docs or logs needed.
- Prefer one task per prompt.
- Ask Zoo Code for a proposed patch or checklist, not direct broad changes.

## Handoff Boundary

Zoo Code may:

- inspect `docs/internal/phase10-implementation-checklist.md`
- inspect `docs/runbooks/phase10-azure-smoke.md`
- inspect `docs/internal/phase10-parity-matrix.md`
- inspect one workflow run summary/log packet at a time
- produce a staging/prod promotion checklist
- produce a risk list and suggested verification order
- propose doc wording changes

Zoo Code must not directly:

- run Azure deploy or cleanup workflows
- change GitHub secrets, Key Vault secrets, RBAC, or identity wiring
- commit changes
- rewrite workflow IAM or destructive cleanup behavior
- introduce new architecture layers without an explicit roadmap entry

## Recommended Zoo Code Prompt

Use this as the first handoff prompt:

```text
You are assisting with Phase 10 Azure promotion planning for XYDataLabs.OrderProcessingSystem.

Current fact: dev is already validated for Phase 10. Do not reopen Phase 1-9.

Read these files:
- docs/internal/phase10-implementation-checklist.md
- docs/runbooks/phase10-azure-smoke.md
- docs/internal/phase10-parity-matrix.md

Task:
1. Produce a staging promotion checklist using workflows 00, 01, 02, 03, and 04.
2. Identify any prod-specific approval, cleanup, or rollback risks.
3. List exact evidence that should be captured from each workflow summary.
4. Do not propose direct Azure cleanup, RBAC, or secret changes.
5. Do not modify files. Output findings and a proposed checklist only.
```

## Staging Then Prod Baby Steps

Use this sequence after dev is green.

| Step | Environment | Workflow | Expected result |
|---|---|---|---|
| 1 | `staging` | `00 Azure Platform Foundation` | Run only if platform foundation or provider registration needs refresh. |
| 2 | `staging` | `01 Phase 10 Azure Deploy Orchestrator` | App RG and runtime resources deploy cleanly. |
| 3 | `staging` | `02 Phase 10 Azure Runtime Smoke` | Gateway/UI/API proxy checks pass. |
| 4 | `staging` | `03 Phase 10 Azure Transport Smoke` | Service Bus fan-out, DLQ, and replay checks pass. |
| 5 | `staging` | `04 Phase 10 Azure Payment Matrix` | All-tenant payment/provider E2E checks pass against Azure. |
| 6 | `prod` | `00 Azure Platform Foundation` | Run only if platform foundation or provider registration needs refresh. |
| 7 | `prod` | `01 Phase 10 Azure Deploy Orchestrator` | Deploy only after staging evidence is accepted. |
| 8 | `prod` | `02 Phase 10 Azure Runtime Smoke` | Runtime smoke passes. |
| 9 | `prod` | `03 Phase 10 Azure Transport Smoke` | Transport smoke passes. |
| 10 | `prod` | `04 Phase 10 Azure Payment Matrix` | Run only during approved production validation. |

Cleanup rule:

- Dev/staging cleanup can be used for reset testing when approved.
- Prod cleanup must remain an explicit approved teardown action.
- App cleanup must not delete the platform foundation ACR or pull identity.

## Evidence Packet

For each staging/prod run, capture:

- workflow name
- run ID
- environment
- resource group
- ACR login server
- gateway URL
- UI URL
- smoke status
- transport smoke status
- payment matrix status
- any warnings or skipped checks
- next operator action

If Zoo Code summarizes evidence, it should include the run IDs and exact workflow names.

## Validation After Zoo Code Output

If Zoo Code suggests docs or script changes, use the normal repo validation path:

```powershell
git diff --check
node scripts/validate-doc-links.js
```

If Zoo Code suggests local parity validation, use the existing hook:

```powershell
npm --prefix automation run xydatalabs-test-docker-local-e2e-dev
```

Keep prompt-run artifacts under `local models/prompt-runs/` only when the evidence is intentionally useful. Do not commit raw exploratory output unless it is reviewed.
