---
name: ollama-rag
description: Use local Ollama + project RAG (rag_query.py via ollama_explore.py) and Serena MCP to explore codebases with minimal reads/tokens.
---

# Ollama + RAG + Serena (Cursor)

Use these tools to **minimize token usage** and **minimize raw file reads**, especially during planning / large info gathers.

## Primary: semantic exploration without reading files

Use `ollama_explore.py` for \"how/where/what\" questions. It runs RAG, reads only relevant windows, then synthesizes a short answer with file paths.

```bash
python3 ~/.claude/commands/ollama_explore.py "how does WebSocket session auth work"
python3 ~/.claude/commands/ollama_explore.py "where is beacon room polling handled" --results 8
```

If output begins with `[ollama_explore: RAG returned no results...]`, switch to Serena (below).

## Summarize long logs / outputs (avoid context bloat)

When you already have large text (logs, build output, stack traces), compress it with Ollama:

```bash
cat big_output.txt | ~/.claude/commands/ollama_query.sh "Summarize key errors/warnings. Preserve file paths and line numbers. Max 300 words."
```

## Serena: symbol navigation + impact analysis (MCP)

When RAG misses or you need LSP-accurate results:

- Read tool schemas from the `serena` MCP server descriptors before calling
- **`get_symbols_overview`** — inspect file structure token-efficiently
- **`find_symbol`** / **`find_declaration`** — locate definitions
- **`find_referencing_symbols`** — blast radius / reverse deps
- **`find_implementations`** — interface implementations
- **`search_for_pattern`** — project-wide regex search

Call **`activate_project`** with `tentura` if Serena has no active project.

Use Cursor `Read` only when editing specific lines.

## Hard rule: location known → read directly

If you already know the exact file (stack trace or explicit path), go straight to `Read` and work surgically.
