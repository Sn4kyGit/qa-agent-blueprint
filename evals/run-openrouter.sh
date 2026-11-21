#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HERE/.env.openrouter" ]; then
  . "$HERE/.env.openrouter"
fi
: "${OPENROUTER_API_KEY:?evals/.env.openrouter is missing or OPENROUTER_API_KEY is unset}"
PORT="${OR_SHIM_PORT:-$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')}"
python3 "$HERE/openrouter-shim.py" "$PORT" >/dev/null 2>&1 &
SHIM_PID=$!
cleanup() {
  kill "$SHIM_PID" 2>/dev/null || true
  wait "$SHIM_PID" 2>/dev/null || true
}
trap cleanup EXIT
ready=0
for _ in $(seq 1 50); do
  if curl -sf "http://127.0.0.1:$PORT/v1/models/probe" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
if [ "$ready" -ne 1 ]; then
  echo "INFRA_ERROR: OpenRouter shim did not start" >&2
  exit 2
fi
export ANTHROPIC_BASE_URL="http://127.0.0.1:$PORT"
export ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="${OR_MODEL:-deepseek/deepseek-v4-pro}"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$ANTHROPIC_DEFAULT_HAIKU_MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$ANTHROPIC_DEFAULT_HAIKU_MODEL"
export CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1
OR_MODEL="${OR_MODEL:-deepseek/deepseek-v4-pro}"
OR_JUDGE_MODEL="${OR_JUDGE_MODEL:-$OR_MODEL}"
has_answer_model=0
has_judge_model=0
for arg in "$@"; do
  case "$arg" in
    --model) has_answer_model=1 ;;
    --judge-model) has_judge_model=1 ;;
  esac
done
if [ "$has_answer_model" -eq 0 ]; then
  set -- --model "$OR_MODEL" "$@"
fi
if [ "$has_judge_model" -eq 0 ]; then
  set -- --judge-model "$OR_JUDGE_MODEL" "$@"
fi
echo "OpenRouter gate: model=$OR_MODEL judge=$OR_JUDGE_MODEL (per-token billing)"
set +e
bash "$HERE/run.sh" "$@"
rc=$?
set -e
exit "$rc"
