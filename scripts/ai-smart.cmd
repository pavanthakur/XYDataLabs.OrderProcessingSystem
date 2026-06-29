@echo off
cd /d Q:\GIT\TestAppXY_OrderProcessingSystem
echo Delegating to ai-runtime\run.ps1 (architect smart)
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\run-aider.ps1 -Mode architect
