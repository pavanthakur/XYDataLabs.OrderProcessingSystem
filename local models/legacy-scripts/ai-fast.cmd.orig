@echo off
cd /d Q:\GIT\TestAppXY_OrderProcessingSystem
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start-ollama.ps1
call .venv\Scripts\activate.bat

set OLLAMA_API_BASE=http://localhost:11434

aider --model ollama/qwen2.5-coder:3b ^
      --map-tokens 512 ^
      --max-chat-history-tokens 1024 ^
      --subtree-only
