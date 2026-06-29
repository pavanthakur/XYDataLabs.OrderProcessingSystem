# Phase Closure Standard

Use this pattern for every future phase and sub-phase closeout.

## Required Gates

1. Build cleanly with the phase’s expected build command.
2. Run architecture or contract tests.
3. Run gateway or API contract tests.
4. Run integration tests.
5. Run Playwright or equivalent end-to-end automation.
6. Log warnings separately from blocking failures.
7. Close the phase only when every required gate passes.

## Standard Automation Rules

- Bootstrap environment before tests.
- Use deterministic scripts for environment setup.
- Fail fast on missing infrastructure or missing databases.
- Do not depend on manual intervention for the normal success path.
- Keep the test matrix and pass/fail summary in the run log.
- Keep cleanup separate from functional verification.

## Standard Runbook Sections

Each phase should have a closeout document with:

1. What was verified
2. Key automation files
3. Clean restart commands
4. Log file locations
5. Known warnings or non-blocking notes
6. Final sign-off status

## Standard File Placement

- Keep automation scripts under the phase or shared `scripts` folder.
- Keep phase-specific closeout notes under the phase folder.
- Keep run logs in `.tmp` or the phase’s designated log location.

## Standard Failure Policy

- If setup fails, stop before test execution.
- If a required DB, service, or environment variable is missing, fail immediately.
- If the testcase matrix does not appear in the transcript, fix logging before sign-off.
- If cleanup leaves orphaned resources, remove them before closure.

## Standard Success Criteria

- Environment bootstraps automatically.
- Tests run end to end without manual correction.
- The full testcase matrix is visible in logs.
- Final cleanup leaves the environment tidy.
- The phase is reproducible from the documented commands.
