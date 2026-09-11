#!/usr/bin/env bash
#
# run-openrouter.sh — evals/run.sh, aber abgerechnet ueber OpenRouter
# (pro Token) statt ueber die Claude-Subscription-Quota.
#
# Warum das geht: run.sh ruft `claude -p` auf und erbt die Umgebung. Claude
# Code akzeptiert ein Anthropic-kompatibles Gateway per ANTHROPIC_BASE_URL +
# ANTHROPIC_AUTH_TOKEN; OpenRouter stellt genau so einen /v1/messages-
# Endpunkt bereit. Kein Patch an run.sh noetig.
#
# Harte Regeln (siehe evals/README.md — das Gate misst die Production-
# Modellklasse):
#   - IMMER ein anthropic/* Modell. GPT/Gemini/Llama ueber OpenRouter macht
#     das Gate wertlos (misst dann ein anderes Produkt).
#   - Modell-Aliase ("sonnet") funktionieren NICHT ueber ein Gateway — volle
#     OpenRouter-IDs, fuer --model UND --judge-model.
#
# Der Key liegt in evals/.env.openrouter (gitignored via .env.*) — nie in
# dieses Skript, nie in einen Commit. openrouter-shim.py sieht den Key auch
# nicht: die CLI schickt ihn als Bearer-Header, der Shim reicht ihn durch.
#
# Warum der Shim: OpenRouter 404t /v1/messages/count_tokens und
# /v1/models/<id> — Claude Code bricht dann mit "issue with the selected
# model" ab (live verifiziert 2026-09-11). Der Shim beantwortet beide lokal,
# der Rest geht unveraendert durch.
#
# Usage (alle Args werden an run.sh durchgereicht):
#   bash evals/run-openrouter.sh routing-absent            # ein Case, 1 Run
#   bash evals/run-openrouter.sh --runs 3                  # volles Gate
#   OR_MODEL=anthropic/claude-opus-4.5 bash evals/run-openrouter.sh ...
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$HERE/.env.openrouter" ]; then
  # shellcheck disable=SC1091
  . "$HERE/.env.openrouter"
fi
: "${OPENROUTER_API_KEY:?evals/.env.openrouter fehlt oder OPENROUTER_API_KEY ist nicht gesetzt}"

# Shim starten: beantwortet count_tokens + models lokal, proxied den Rest
# zu OpenRouter (127.0.0.1 only). Laueft nur fuer die Dauer dieses Runs.
PORT="${OR_SHIM_PORT:-8799}"
python3 "$HERE/openrouter-shim.py" "$PORT" >/dev/null 2>&1 &
SHIM_PID=$!
trap 'kill "$SHIM_PID" 2>/dev/null || true' EXIT
ready=0
for _ in $(seq 1 50); do
  curl -sf "http://127.0.0.1:$PORT/v1/models/probe" >/dev/null 2>&1 && { ready=1; break; }
  sleep 0.1
done
[ "$ready" -eq 1 ] || { echo "shim did not come up on port $PORT" >&2; exit 1; }

export ANTHROPIC_BASE_URL="http://127.0.0.1:$PORT"  # OHNE /v1 — die CLI haengt /v1/messages selbst an
export ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY"
# Hintergrund-/Hilfsaufrufe der CLI (haiku-Klasse) muessen auch auf eine
# OpenRouter-ID zeigen, sonst schlaegt der Alias-Lookup am Gateway fehl.
export ANTHROPIC_DEFAULT_HAIKU_MODEL="anthropic/claude-haiku-4.5"
export ANTHROPIC_DEFAULT_SONNET_MODEL="anthropic/claude-sonnet-4.5"
export ANTHROPIC_DEFAULT_OPUS_MODEL="anthropic/claude-opus-4.5"

OR_MODEL="${OR_MODEL:-anthropic/claude-sonnet-4.5}"
OR_JUDGE_MODEL="${OR_JUDGE_MODEL:-$OR_MODEL}"

# Durchreichen, aber Modell-Flags nicht doppeln: wer selbst --model uebergibt,
# hat Vorrang.
has_model_flag=0
for a in "$@"; do
  case "$a" in --model|--judge-model) has_model_flag=1 ;; esac
done
if [ "$has_model_flag" -eq 0 ]; then
  set -- --model "$OR_MODEL" --judge-model "$OR_JUDGE_MODEL" "$@"
fi

echo "OpenRouter gate: model=$OR_MODEL judge=$OR_JUDGE_MODEL (billing: per-token, nicht Subscription)"
exec bash "$HERE/run.sh" "$@"
