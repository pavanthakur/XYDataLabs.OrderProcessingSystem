# Prompt Run Records

Use this folder for local evidence from architect/developer model runs.

Keep records lightweight and local. Do not store secrets, private keys, raw access tokens, production connection strings, or large generated caches here.

## Suggested Folder Naming

```text
prompt-runs/
  2026-06-11-phase9-architect-intake/
  2026-06-11-phase9-developer-slice-01/
```

Each run folder can contain:

- `run-record.md` copied from `run-record-template.md`
- `prompt.md` if the prompt was manually assembled
- `output-summary.md` for accepted model output
- `validation.txt` for command output summary

For milestone closeout or day-complete records, include the current roadmap alignment in the run record:

- Current phase
- Next phase
- Optional horizon items
- Explicitly deferred items

Do not commit prompt run records unless they are intentionally part of a reviewed architecture handoff.
