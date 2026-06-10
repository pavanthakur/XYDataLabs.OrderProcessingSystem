# Phase 9 Zoo Code Execution Pack

Purpose: run Phase 9 through Zoo Code as a gated architect-to-developer workflow. Architecture files are read-only decision prompts. Development files are executable implementation commands for one accepted slice at a time.

Canonical references remain:

- `.github/prompts/phase-handoffs/phase-09-microservices-architecture.prompt.md`
- `.github/prompts/phase-handoffs/phase-09-microservices-implementation.prompt.md`
- `.github/prompts/phase-handoffs/local-model-phase-handoff-guide.md`
- `docs/Zoo-config.md`
- `repomix-output.xml`

Run order:

1. `phase9_architect1.0.md`
2. `phase9_architect1.1.md`
3. `phase9_architect2.0.md`
4. `phase9_development1.0.md`
5. `phase9_development1.1.md`
6. `phase9_development2.0.md`
7. `phase9_development2.1.md`
8. `phase9_development3.0.md`
9. `phase9_development4.0.md`
10. `phase9_development5.0.md`
11. `phase9_development6.0.md`
12. `phase9_development9.0.md`
13. `phase9_architect9.0.md`
14. `phase9_architect99.0.md`
15. `phase9_development99.0.md`

Gate rule: do not run any development file until the preceding architect output has been reviewed and accepted by Copilot or the repository owner.
