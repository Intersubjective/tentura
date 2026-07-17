# CLAUDE.md — Tentura

Follow [`AGENTS.md`](../AGENTS.md) (always-on index + invariants) and the scoped rules under [`.cursor/rules/`](../.cursor/rules/). This file holds only Claude-specific notes.

## Search & exploration

Use the token-minimizing ladder in [`.cursor/rules/search-tools.mdc`](../.cursor/rules/search-tools.mdc): known path → `Read`; semantic/structure/symbols/refs → Serena MCP; then Grep/Glob.

## Architecture work

Layer/DI work (domain, data, ui layers, use cases, repositories, cubits, ports, Injectable) goes through the `clean-architecture` skill (`.claude/skills/clean-architecture/SKILL.md`) — a condensed contract over [`.cursor/rules/architecture.mdc`](../.cursor/rules/architecture.mdc).

## UI work

Client UI must go through the Material 3 design system — invoke the `material-3-flutter` skill (`.claude/skills/material-3-flutter/SKILL.md`) and see [`.cursor/rules/tentura-design-system.mdc`](../.cursor/rules/tentura-design-system.mdc). The design-system invariants and lints are listed in `AGENTS.md`.

**Terminology:** users see **Request** / **Chat**; code paths stay `beacon_view`, `beacon_room`, etc. See [`.cursor/rules/terminology.mdc`](../.cursor/rules/terminology.mdc).

## Claude-specific tooling

- **Serena MCP:** call `activate_project` with `tentura` if no project is active; use `list_memories` / `read_memory` / `write_memory` for durable cross-session notes.
