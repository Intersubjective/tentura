---
name: ollama-rag
description: Use local Ollama + project RAG (rag_query.py via ollama_explore.py) and vexp to explore codebases with minimal reads/tokens.
---

# Ollama + RAG + vexp (Cursor)

Use these tools to **minimize token usage** and **minimize raw file reads**, especially during planning / large info gathers.

## Primary: semantic exploration without reading files

Use `ollama_explore.py` for \"how/where/what\" questions. It runs RAG, reads only relevant windows, then synthesizes a short answer with file paths.

```bash
python3 ~/.claude/commands/ollama_explore.py "how does WebSocket session auth work"
python3 ~/.claude/commands/ollama_explore.py "where is beacon room polling handled" --results 8
```

If output begins with `[ollama_explore: RAG returned no results...]`, switch to vexp (below).

## Summarize long logs / outputs (avoid context bloat)

When you already have large text (logs, build output, stack traces), compress it with Ollama:

```bash
cat big_output.txt | ~/.claude/commands/ollama_query.sh "Summarize key errors/warnings. Preserve file paths and line numbers. Max 300 words."
```

## vexp: context + impact analysis (native MCP preferred)

When you need blast radius (refactor/debug/modify) or RAG misses:

- Prefer MCP tools: `run_pipeline`, `get_skeleton`, `index_status`, `expand_vexp_ref`
- Use `get_skeleton` to inspect files token-efficiently; use `Read` only when editing specific lines

CLI fallback if MCP is unavailable:

```bash
vexp capsule "your task"
vexp skeleton packages/client/lib/features/beacon_room/ui/widget/room_poll_card.dart
```

## Hard rule: location known → read directly

If you already know the exact file (stack trace or explicit path), go straight to `Read` and work surgically.

