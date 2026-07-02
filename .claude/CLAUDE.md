# CLAUDE.md — Tentura

Follow [`AGENTS.md`](../AGENTS.md) (always-on index + invariants) and the scoped rules under [`.cursor/rules/`](../.cursor/rules/). This file holds only Claude-specific notes.

## Search & exploration

Use the token-minimizing ladder in [`.cursor/rules/search-tools.mdc`](../.cursor/rules/search-tools.mdc): known path → `Read`; semantic → `ollama_explore.py`; symbols/refs → Serena MCP; then Grep/Glob.

## UI work

Client UI must go through the Material 3 design system — invoke the `material-3-flutter` skill (`.claude/skills/material-3-flutter/SKILL.md`) and see [`.cursor/rules/tentura-design-system.mdc`](../.cursor/rules/tentura-design-system.mdc). The design-system invariants and lints are listed in `AGENTS.md`.

**Terminology:** users see **Request** / **Chat**; code paths stay `beacon_view`, `beacon_room`, etc. See [`.cursor/rules/terminology.mdc`](../.cursor/rules/terminology.mdc).

## Claude-specific tooling

- **RAG index debugging only** (normal flow runs via `ollama_explore.py`):
  ```bash
  source $CLAUDE_PROJECT_DIR/rag_env/bin/activate && python3 rag_query.py "your question"
  ```
- **Serena MCP:** call `activate_project` with `tentura` if no project is active; use `list_memories` / `read_memory` / `write_memory` for durable cross-session notes.
