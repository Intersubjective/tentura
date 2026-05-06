#!/bin/bash
set -euo pipefail

# Re-index edited Dart files into the local project RAG index (best-effort).
# Mirrors the Claude PostToolUse Edit/Write hook.
#
# Cursor hook payloads vary; try common keys.

input="$(cat)"

path="$(
  echo "$input" | jq -r '
    .file_path // .path // .tool_input.file_path // .tool_input.path // empty
  ' 2>/dev/null
)"

[ -n "$path" ] || exit 0
[[ "$path" == *.dart ]] || exit 0

if [ -x "rag_env/bin/python3" ]; then
  ./rag_env/bin/python3 rag_index.py --single "$path" 2>/dev/null || true
else
  python3 rag_index.py --single "$path" 2>/dev/null || true
fi

exit 0

