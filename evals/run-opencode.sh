#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_HINT="${QA_EVAL_MODEL:-}"
for ((i = 1; i <= $#; i++)); do
  arg="${!i}"
  if [ "$arg" = "--model" ]; then
    next=$((i + 1))
    MODEL_HINT="${!next:-}"
  elif [[ "$arg" == --model=* ]]; then
    MODEL_HINT="${arg#--model=}"
  fi
done
if [[ "$MODEL_HINT" == openrouter/* ]] && [ -f "$HERE/.env.openrouter" ]; then
  set -a
  . "$HERE/.env.openrouter"
  set +a
fi
exec python3 "$HERE/lib/runner_policy.py" --harness opencode "$@"
