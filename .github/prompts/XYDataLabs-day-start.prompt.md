---
agent: agent
description: "Session start: uses the concise repository handoff with bounded read-only verification to report current scope, evidence limits, pending actions and key entry points"
---

# Day Start

Read repository-relative `memories/repo/active-work.md` through the available filesystem or repository tool. It is a checkpoint, not authoritative proof of runtime correctness; do not require a special memory tool or read personal memory stores.

Perform bounded read-only verification: inspect `git status --short` and HEAD, open the active plan section, and inspect only the evidence references material to the user's task. Do not load the full history or rediscover the whole repository. If tools or evidence are unavailable, state that limitation rather than trusting the checkpoint as verified.

Then report in this format, distinguishing observed facts from historical or unverified claims:

---

## Current Phase
[phase and pause/approval state checked against the relevant plan]

## Last Session Summary
[concise checkpoint summary; identify historical evidence and any missing revision binding]

## Evidence And Limits
[environment, revision or UNKNOWN, report reference and scope; missing evidence is unavailable, not PASS; flag conflicts without silently resolving them]

## Pending Next Actions
[next task from the active plan/checkpoint; preserve pause and approval boundaries]

## Key Files for This Phase
[only relevant plan, code or evidence paths; report missing references explicitly]

## Ready
Await a scoped task or approval. Do not automatically start a phase or technical workstream.

---

Day Start is read-only: no file edits, automatic full builds/tests, Git writes, database queries/mutations, Docker lifecycle operations, provider calls, or Azure operations. A historical PASS proves only its recorded environment/scope/revision; do not present it as current-candidate or Azure acceptance. Any needed consequential revalidation requires a separate approved task.
