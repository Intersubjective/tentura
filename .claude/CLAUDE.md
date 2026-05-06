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

3. **vexp `run_pipeline`** → for impact analysis, refactoring, debugging, or when Ollama is unavailable. One call covers context + impact + memory.

4. **Grep/Glob fallback** → only when vexp reports `status: "degraded"` or index is empty.

> `ollama_explore.py` shells out to RAG and file I/O internally — the vexp-guard PreToolUse hook does **not** intercept these calls.

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




## vexp — Context-Aware AI Coding <!-- vexp v2.0.12 -->

### MANDATORY: use vexp pipeline — do NOT grep or glob the codebase
For every task — bug fixes, features, refactors, debugging:
**call `run_pipeline` FIRST**. It executes context search + impact analysis +
memory recall in a single call, returning compressed results.

Do NOT use grep, glob, Bash, or cat to search/explore the codebase.
vexp returns pre-indexed, graph-ranked context that is more relevant and
uses fewer tokens than manual searching. Prefer `get_skeleton` over Read to
inspect files (detail: minimal/standard/detailed, 70-90% token savings).
Only use Read when you need exact raw content to edit a specific line.

### Primary Tool
- `run_pipeline` — **USE THIS FOR EVERYTHING**. Single call that runs
  capsule + impact + memory server-side. Returns compressed results.
  Auto-detects intent (debug/modify/refactor/explore) from your task.
  Includes full file content for pivots.
  Examples:
  - `run_pipeline({ "task": "fix JWT validation bug" })` — auto-detect
  - `run_pipeline({ "task": "refactor db layer", "preset": "refactor" })` — explicit
  - `run_pipeline({ "task": "add auth", "observation": "using JWT" })` — save insight in same call

### Other MCP tools (use only when run_pipeline is insufficient)
- `get_skeleton` — **preferred over Read** for inspecting files (minimal/standard/detailed detail levels, 70-90% token savings)
- `index_status` — indexing status and health check
- `expand_vexp_ref` — expand V-REF hash placeholders in v2 compact output

### Skip vexp when location is already known
If an error stack trace, test failure, or other output already names the exact file and line, go straight to `Read`/`Edit`. Calling `run_pipeline` when you already know where to look wastes daily quota with no benefit.

### Workflow
1. `run_pipeline("your task")` — ALWAYS FIRST (unless location is already known — see above). Returns pivots + impact + memories in 1 call
2. Need more detail on a file? Use `get_skeleton({ files: [...], detail: "detailed" })` — avoid Read unless editing
3. Make targeted changes based on the context returned
4. `run_pipeline` again ONLY if you need more context during implementation
5. Do NOT chain multiple vexp calls — one `run_pipeline` replaces capsule + impact + memory + observation

### Subagent / Explore / Plan mode
- Subagents CAN and MUST call `run_pipeline` — always include the task description
- The PreToolUse hook blocks Grep/Glob when vexp daemon is running
- Do NOT spawn Agent(Explore) to freely search — call `run_pipeline` first,
  then pass the returned context into the agent prompt if needed
- Always: `run_pipeline` → get context → spawn agent with context

### Smart Features (automatic — no action needed)
- **Intent Detection**: auto-detects from your task keywords. "fix bug" → Debug, "refactor" → blast-radius, "add" → Modify
- **Hybrid Search**: keyword + semantic + graph centrality ranking
- **Session Memory**: auto-captures observations; memories auto-surfaced in results
- **LSP Bridge**: VS Code captures type-resolved call edges
- **Change Coupling**: co-changed files included as related context

### Advanced Parameters
- `preset: "debug"` — forces debug mode (capsule+tests+impact+memory)
- `preset: "refactor"` — deep impact analysis (depth 5)
- `max_tokens: 12000` — increase total budget for complex tasks
- `include_tests: true` — include test files in results
- `include_file_content: false` — omit full file content (lighter response)

### Fallback
If `run_pipeline` returns `status: "degraded"` or 0 pivots with an INDEX EMPTY warning,
the index is empty or rebuilding. Use Grep, Glob, and Read directly until the index is ready.

### Multi-Repo Workspaces
`run_pipeline` auto-queries all indexed repos. Use `repos: ["alias"]` to scope.
Use `index_status` to discover available repo aliases.
<!-- /vexp -->
