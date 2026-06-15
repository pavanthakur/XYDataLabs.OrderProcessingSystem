# Phase 9 Review 1.0 - Diff Review Gate

Zoo role: Reviewer.

Strict mode: read-only review only. Do not write production code. Do not emit patches. Finish with `DONE`.

Input:

- Accepted output from `phase9_development1.0.md`
- Relevant git diff or change summary
- `.github/agents/code-reviewer.agent.md`
- `.github/instructions/clean-architecture.instructions.md`
- `.github/instructions/architecture.instructions.md`

Task:

Review the Phase 9 implementation slice for correctness, boundary compliance, and test coverage.

Required output:

1. Findings table with severity, file, and issue.
2. Whether the slice is accepted, accepted with corrections, needs revision, or rejected.
3. Smallest correction set, if needed.
4. Validation command to rerun after fixes.
5. Next step handoff artifact expected from developer or automation.

Hard rules:

- Do not edit files.
- Do not approve violations of Clean Architecture boundaries.
- Do not broaden scope beyond the accepted slice.

Stop after the review report.
