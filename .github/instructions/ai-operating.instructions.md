---
applyTo: "**/*"
description: "Repo-wide local AI slice-sizing and drift-control rules"
---

# AI Operating Rules

- Keep every task slice-sized.
- Do not expand scope beyond the accepted handoff.
- Prefer the minimum set of files needed to make progress.
- If context starts drifting, stop and realign before editing.
- Treat architecture output as advisory until reviewed and accepted.
- Treat developer output as implementation-only; do not invent architecture.
- Validate the narrowest useful change first, then widen only if needed.
- Preserve canonical decisions in ADRs, docs, tests, and code, not only in chat history.
