# Local Models Operating Pack

Purpose: local-only execution support for running repository phases through local model tools such as Zoo Code, Continue, Cline, and Ollama.

This folder is an execution cockpit, not the canonical documentation source. Canonical architecture, prompts, and governance stay in `.github/`, `docs/`, and `zoocode/`. Files here point to those sources, define local model profiles, and record local run evidence.

## Folder Layout

| Folder | Purpose |
| --- | --- |
| `ollama/` | Local Ollama model index, routing config, and helper scripts. |
| `ai-guidelines/` | Local operating rules for architect and developer model profiles. |
| `zoocode/` | Local execution copies of phase packs for manual model runs. |
| `prompt-runs/` | Optional run records, model outputs, review notes, and validation evidence. |

## RooCode Handoff

Use RooCode/local models as an operator-assist lane, not as the source of truth for deployment decisions.

Canonical Phase 10 handoff guidance lives in:

- `docs/internal/phase10-roocode-local-model-handoff.md`

Use that document when asking RooCode to draft staging/prod promotion checklists, summarize workflow logs, or identify documentation gaps after the dev baseline has been validated.

## Recommended Flow

1. Start with the architect profile to review the phase, create or refine the ADR/blueprint, and define the first safe implementation slice.
2. Review the architect output as repo owner before developer execution.
3. Run the developer profile only on one accepted slice at a time.
4. Record model, prompt, output, files changed, and validation results in `prompt-runs/` when a run affects implementation.
5. Keep generated caches and exploratory outputs local unless explicitly approved for commit.

## Local Performance Baseline

- Default model for Phase 9: `qwen2.5-coder:7b`.
- Quick Ask/docs model: `qwen2.5-coder:3b`.
- Architecture escalation only: `deepseek-r1-14b-32k:latest`.
- Default context: 4096 for fast work, 8192 for Phase 9 architecture, 16384 only for deliberate escalation.
- Avoid 32768/65536 context windows as defaults on the Acer Predator Helios 300 profile.

See `ai-guidelines/local-ai-performance-tuning.md` before changing local model settings.
