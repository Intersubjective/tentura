#!/bin/bash
set -euo pipefail

# Compress large shell outputs via local Ollama (opt-in).
# This mirrors `~/.claude/commands/ollama_compress.sh`, but for Cursor hooks.
#
# Opt-in flag:
#   touch ".enable-ollama-compress"   # enable
#   rm ".enable-ollama-compress"      # disable
#
# Cursor hook payloads vary by version; this script tries multiple common keys.

FLAG_FILE="$(pwd)/.enable-ollama-compress"
[ -f "$FLAG_FILE" ] || exit 0

THRESHOLD="${OLLAMA_COMPRESS_THRESHOLD:-15000}"

input="$(cat)"

cmd="$(echo "$input" | jq -r '.command // .tool_input.command // empty' 2>/dev/null | head -c 200)"
out="$(echo "$input" | jq -r '.output // .stdout // .result // .tool_result // empty' 2>/dev/null)"

[ -n "$out" ] || exit 0

len=${#out}
[ "$len" -ge "$THRESHOLD" ] || exit 0

orig="/tmp/cursor_ollama_orig_$(date +%s%3N).txt"
echo "$out" > "$orig"

prompt="Command: ${cmd}

Summarize the key information from this shell output. Rules:
- Preserve errors and warnings verbatim
- Include important file paths, line numbers, identifiers
- State operation result/status clearly
- Omit repetitive or boilerplate lines
- Max 300 words

Output (${len} chars):
$(echo "$out" | head -c 12000)"

summary="$(echo "$prompt" | OLLAMA_MAX_TOKENS=400 ~/.claude/commands/ollama_query.sh 2>/dev/null || true)"
[ -n "$summary" ] || exit 0

# Best-effort rewrite output for hook systems that support it.
# Fallback: provide `additional_context` which at least keeps the model from
# needing the raw output again.
cat <<JSON
{
  "additional_context": "[OLLAMA-COMPRESSED from ${len} chars]\n${summary}\n\n[Full output saved to: ${orig} — read it only if exact content needed]"
}
JSON

