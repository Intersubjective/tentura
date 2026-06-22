# AGENTS.md — Tentura

Cross-tool entry point for AI coding agents (Claude Code, Cursor, Copilot, etc.).
This is a pointer index; the detailed rules live in the linked files.

## Project shape

Pub workspace with three packages: `packages/client` (Flutter app, package
`tentura`), `packages/server` (Dart), `packages/tentura_lints` (custom analyzer
plugin). See `DEVELOPMENT.md` and `DEV_GUIDELINES.md`.

## UI work → Material Design 3 + the design system

The client already uses Material 3 (`TenturaTheme`, `useMaterial3: true`,
`ColorScheme.fromSeed`) and a design system under
`packages/client/lib/design_system/`. When touching any UI:

- **Read first:** [`docs/tentura-design-system.md`](docs/tentura-design-system.md)
  and the skill [`.claude/skills/material-3-flutter/SKILL.md`](.claude/skills/material-3-flutter/SKILL.md)
  (Cursor: [`.cursor/rules/tentura-design-system.mdc`](.cursor/rules/tentura-design-system.mdc)).
- **Use** `import 'package:tentura/design_system/tentura_design_system.dart';`,
  `context.tt` density tokens, `TenturaText.*` / `textTheme` typography, semantic
  `ColorScheme` roles, and the `Tentura*` components.
- **Do not** put raw `Color(0x…)` / `Colors.*`, `TextStyle(…)`, inline
  `fontSize:`, `EdgeInsets`-from-numbers, or `BorderRadius`/`Radius`-from-numbers
  in feature / shared UI. If a token is missing, add it to the design system
  first. These are enforced by `tentura_lints` (see the SKILL for the table).

## Architecture & codegen

- Layer boundaries (domain ← data, ui ← domain) and other rules:
  `DEV_GUIDELINES.md` and `.cursor/rules/*.mdc`, enforced by `tentura_lints`.
- Generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`,
  `*.schema.dart`) — never edit; run codegen instead.

## Verify

```bash
# custom lint rules
cd packages/tentura_lints && dart test

# client analysis (CI flags) + tests + goldens
cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos
cd packages/client && flutter test
cd packages/client && flutter test --update-goldens <path>   # regenerate a golden intentionally
```

CI (`.github/workflows/pipeline.yml`) runs the lint tests, `flutter analyze`,
and `flutter test` on every push to `main`.
