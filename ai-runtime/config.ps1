# Centralized AI runtime configuration
$AI_RUNTIME_ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROMPT_RUNS_DIR = Join-Path $AI_RUNTIME_ROOT 'prompt-runs'
$PROMPT_RUNS_FILE = Join-Path $PROMPT_RUNS_DIR 'prompt_runs.jsonl'

# Model defaults
$DEFAULT_MODEL_DEVELOPER = 'qwen2.5-coder:7b'
$DEFAULT_MODEL_ARCHITECT = 'qwen3-8b-64k:latest'

# Timeouts and limits
$OLLAMA_FALLBACK_TIMEOUT_SECONDS = 120
