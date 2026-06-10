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

## Recommended Flow

1. Start with the architect profile to review the phase, create or refine the ADR/blueprint, and define the first safe implementation slice.
2. Review the architect output as repo owner before developer execution.
3. Run the developer profile only on one accepted slice at a time.
4. Record model, prompt, output, files changed, and validation results in `prompt-runs/` when a run affects implementation.
5. Keep generated caches and exploratory outputs local unless explicitly approved for commit.
