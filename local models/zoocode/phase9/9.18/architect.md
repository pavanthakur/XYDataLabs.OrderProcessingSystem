# Phase 9.18 Architect

Scope: API finalization.

Task:
- Define the smallest contract surface that closes the remaining service boundary gaps for Phase 9.
- Keep the model at `qwen2.5-coder:7b`.
- Keep context as small as possible for the slice.
- Do not request the whole repo.
- Keep the existing Entity Framework data access flow as-is; do not introduce MediatR or a repository layer.
- Name the exact C# contract files to create or normalize.

Output:
- One concise API closure slice.
- One stop condition.

This slice should focus on contract alignment for Orders, Inventory, Notifications, and Payments.

Command shape:
```powershell
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Slice 9.18 -Step architect
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Slice 9.18 -Step developer
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Slice 9.18 -Step review
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Slice 9.18 -Step automation
```

