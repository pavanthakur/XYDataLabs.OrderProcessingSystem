---
agent: agent
description: "Session start: reads active-work.md and orients the AI with current phase, last session summary, pending actions, and key file entry points — zero exploration needed"
---

# Day Start

Read the file `/memories/repo/active-work.md` using the memory tool.

Then report back in this exact format — no prose, no re-exploration:

---

## Current Phase
[phase number and name from active-work.md]

## Last Session Summary
[what was done — commits, gate results, files changed — directly from active-work.md]

## Pending Next Actions
[numbered list from active-work.md, verbatim]

## Key Files for This Phase
[file paths from active-work.md — if not listed yet, say "not populated yet — will be added at phase kickoff"]

## Ready
Type a task or say "start Phase X.Y" to begin.

---

Do NOT run `git status`, `dotnet build`, or any terminal command unless the user explicitly asks.
Do NOT search the codebase to verify or supplement what is in active-work.md.
active-work.md is the authoritative source — trust it.
