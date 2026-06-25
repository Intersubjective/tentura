---
name: ollama-rag
description: Use local Ollama + project RAG (rag_query.py via ollama_explore.py) and Serena MCP to explore codebases with minimal reads/tokens.
---

# Ollama + RAG + Serena (Cursor)

Follow the token-minimizing exploration ladder in [`.cursor/rules/search-tools.mdc`](../../rules/search-tools.mdc):

- **Semantic "how/where/what"** → `python3 ~/.claude/commands/ollama_explore.py "question" [--results 8]` (RAG + synthesized answer with file paths). If it prints `[ollama_explore: RAG returned no results...]`, switch to Serena.
- **Symbols / references / blast radius** → Serena MCP (`get_symbols_overview`, `find_symbol`, `find_referencing_symbols`, …); read each tool's descriptor first and `activate_project` with `tentura` if none is active.
- **Known exact path** → `Read` directly and work surgically.
- **Long logs / outputs** → `cat big_output.txt | ~/.claude/commands/ollama_query.sh "Summarize key errors/warnings. Preserve file paths and line numbers. Max 300 words."`
