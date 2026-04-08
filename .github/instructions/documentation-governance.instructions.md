---
applyTo: "**/docs/*.md,**/docs/**/*.md"
---
# Documentation Governance — XYDataLabs.OrderProcessingSystem

## Canonical Documentation Rule
- `docs/` is the only active human-facing documentation tree.
- The legacy `Documentation/` tree has been retired.
- The former `docs/archive/` tree has also been retired.
- Do not recreate or reintroduce a parallel `Documentation/` content tree.
- Do not recreate a replacement historical documentation tree for normal work.

## Read This First
Before making documentation changes, use these pages as the operating model:
- `docs/README.md`
- `docs/DEVELOPER-OPERATING-MODEL.md`

## One Source Of Truth Per Topic
- Curriculum execution: `docs/learning/curriculum/1_MASTER_CURRICULUM.md`
- Milestone and phase truth: `docs/internal/AZURE-PROGRESS-EVALUATION.md`
- Commands and validation: `docs/reference/quick-command-reference.md`
- Procedures and how-to guidance: `docs/guides/`
- Architecture decisions: `docs/architecture/decisions/`

## Editing Rules
1. Update the minimum number of documents necessary.
2. Prefer updating an existing canonical page over creating a new page.
3. Do not duplicate the same guidance in multiple places.
4. If a page already owns the topic, update that page instead of adding a side note elsewhere.
5. Delete stale material after any still-useful guidance has been merged into the canonical page that owns it.

## Routing Rules
- "What should I do next?" → `docs/learning/curriculum/1_MASTER_CURRICULUM.md`
- "What phase are we in?" → `docs/internal/AZURE-PROGRESS-EVALUATION.md`
- "How do I run, validate, deploy, or troubleshoot this?" → `docs/guides/` or `docs/reference/`
- "What future constraint must not be broken?" → `docs/architecture/decisions/`

## Validation Rule
If `docs/` content changes materially, run:

```powershell
node scripts/validate-doc-links.js
```

This validator is the lightweight guardrail for local markdown links and heading anchors in the canonical docs tree.

## Simplification Rule
When in doubt, simplify:
- link instead of copy
- update instead of duplicate
- delete stale content once useful guidance is preserved in the owning canonical page
- use short navigation pages instead of sprawling summaries