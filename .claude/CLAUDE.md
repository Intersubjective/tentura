## Search & Exploration Precedence

Follow this order exactly — skip ahead only if the earlier step is inapplicable:

1. **Location already known** (stack trace or error names exact file+line) → `Read`/`Edit` directly. Skip all search tools.

2. **Semantic exploration** ("how does X work", "where is Y", "what handles Z") → Ollama+RAG:
   ```bash
   python3 ~/.claude/commands/ollama_explore.py "your question"
   # More results for broad topics:
   python3 ~/.claude/commands/ollama_explore.py "your question" --results 8
   ```
   Returns a ~400-word summary with file paths. Claude only receives the summary, not raw file contents — major token savings.
   If output begins with `[ollama_explore: RAG returned no results...]`, go to step 3.

3. **Serena MCP** → for symbol lookup, file structure, references, and impact analysis (LSP-accurate).

4. **Grep/Glob fallback** → only when Serena MCP is unavailable or you need a quick exact string match.

---

## Generated Files — Do Not Read or Edit

The following Dart file patterns are **code-generated** (by freezed, build_runner, auto_route, injectable, etc.).
**Never read, edit, or reference them** — always work with the source files instead.

| Pattern | Generator |
|---|---|
| `**.g.dart` | build_runner / freezed |
| `**.freezed.dart` | freezed |
| `**.gr.dart` | auto_route |
| `**.config.dart` | injectable |
| `**.schema.dart` | schema generator |

If you need to understand a type or class, find the non-generated source (e.g. `foo.dart`, not `foo.g.dart`).

---

## RAG (via ollama_explore.py)

RAG is now called automatically by `ollama_explore.py` (step 2 in Search Precedence above). You do **not** need to invoke `rag_query.py` directly — `ollama_explore.py` runs it, reads the matched files, and returns a synthesized summary.

Direct RAG invocation is only needed for debugging the RAG index itself:
```bash
source $CLAUDE_PROJECT_DIR/rag_env/bin/activate && python3 rag_query.py "your question"
```

---

## Serena — LSP-backed code navigation (MCP)

Serena is enabled via `.mcp.json` / `.cursor/mcp.json`. Project config: `.serena/project.yml` (languages: dart, python).

### When to use Serena

Use Serena when RAG is insufficient or you need precise symbol navigation:

- **`get_symbols_overview`** — file structure without reading the whole file
- **`find_symbol`** — locate a symbol by name
- **`find_declaration`** — go to definition
- **`find_referencing_symbols`** — blast radius / reverse dependencies
- **`find_implementations`** — interface implementations
- **`search_for_pattern`** — regex search across the project
- **`find_file`** — locate files by path/name

### Workflow

1. Call **`activate_project`** with `tentura` if no project is active.
2. Use **`get_symbols_overview`** or **`find_symbol`** before broad file reads.
3. Use **`find_referencing_symbols`** before refactors or API changes.
4. Fall back to Grep/Glob only if Serena is unavailable.

### Skip Serena when location is already known

If an error stack trace, test failure, or other output already names the exact file and line, go straight to `Read`/`Edit`.

### Project memories

Use Serena memory tools (`list_memories`, `read_memory`, `write_memory`) for durable project notes that should persist across sessions.
