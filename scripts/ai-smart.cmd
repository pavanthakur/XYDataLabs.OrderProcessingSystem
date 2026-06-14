@echo off
cd /d Q:\GIT\TestAppXY_OrderProcessingSystem
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start-ollama.ps1
call .venv\Scripts\activate.bat

set OLLAMA_API_BASE=http://localhost:11434

aider --model ollama/deepseek-coder-v2 ^
      --map-tokens 1024 ^
      --max-chat-history-tokens 2048 ^
      --subtree-only
