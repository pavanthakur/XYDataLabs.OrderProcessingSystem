# Archive Index

This folder is the canonical archive for documentation rationalization.

Archive principles:

1. Archived documents are retained for traceability.
2. Archived documents are not authoritative unless explicitly stated.
3. Merged source documents are archived after their canonical destination is verified.
4. Superseded documents are archived rather than deleted.
5. Every implemented move or merge is logged in `logs/documentation-rationalization-summary.md`.
6. The canonical audit record for the rationalization effort lives in `logs/documentation-audit.md`.

Subtrees:

- `legacy-documentation/` — legacy documents migrated out of the old `Documentation/` tree
- `merged-sources/` — source documents merged into canonical documents
- `superseded/` — documents replaced by newer authoritative versions
- `historical-notes/` — historical plans, TODOs, and archived notes
- `logs/` — implementation logs, audit records, and archive traceability

Current implementation batch:

- Existing archived self-learning and internal historical notes were normalized into `historical-notes/`.
- No active source-of-truth document was moved or deleted.