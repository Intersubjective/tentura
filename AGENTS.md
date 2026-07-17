# AGENTS.md — Tentura

Cross-tool entry point for AI coding agents (Claude Code, Cursor, Copilot, etc.).
This is the always-on index; depth lives in the linked rules/docs — read them only when the trigger matches.

## Project shape

Pub workspace with three packages: `packages/client` (Flutter app, package
`tentura`), `packages/server` (Dart), `packages/tentura_lints` (custom analyzer
plugin). See `DEVELOPMENT.md` and `DEV_GUIDELINES.md`.

## Rules index (read depth only when the trigger matches)

| When | Read |
|------|------|
| Exploring / "how does X work" | `.cursor/rules/search-tools.mdc` |
| Editing Dart (domain/data/ui/features) | `.cursor/rules/architecture.mdc` (+ `advanced-patterns.mdc` for base/platform/exception/mock) |
| Client UI (features/ui, design_system) | `.cursor/rules/tentura-design-system.mdc` + `docs/tentura-design-system.md` |
| GraphQL / codegen / build / DI | `.cursor/rules/codegen.mdc` |
| Procedures (real-time invalidation, V2 routing, invite, read-state, ferry scalars) | `DEV_GUIDELINES.md` |
| Product behavior / vocabulary | `docs/README.md`, `CONTEXT.md`, `.cursor/rules/terminology.mdc` |
| Verifying changes | `.cursor/rules/lint-after-changes.mdc` |
| Versioning / `MIN_CLIENT_VERSION` | `.cursor/rules/versioning.mdc` |

## Invariants (always true; most are lint-enforced)

- **Dependency direction is inward:** domain stays pure; data implements domain ports; ui → domain/data. (lints: `no_domain_to_data_or_ui_import`, `no_cubit_to_data_service_import`)
- **Repositories return domain entities**, never Ferry/Drift types. Cubits coordinating ≥2 repos inject a `*Case`. (lint: `cubit_requires_use_case_for_multi_repos`)
- **Client UI uses the design system:** no raw `Color`/`Colors.*`, `TextStyle(…)`, inline `fontSize:`, or `EdgeInsets`/`BorderRadius` from raw numbers in `features/**` / `ui/**`; use `context.tt` tokens and `TenturaText.*`. (lints: `no_inline_font_size`, `no_operational_raw_color`, `no_raw_edge_insets`, `no_raw_border_radius`)
- **Never edit generated files** (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, `*.schema.dart`); run codegen instead.
- **Search ladder:** known path → Read; semantic → Serena MCP; then Grep/Glob.
- **Terminology alias:** user-facing **Request** / **Chat**; internal **Beacon** (`Request (internally: Beacon)` in docs). Never introduce a `Request` domain entity. See `.cursor/rules/terminology.mdc` and `bash scripts/check-user-facing-terminology.sh`.

## Product docs

Orientation and feature specs live under [`docs/`](docs/) — start at [`docs/README.md`](docs/README.md). High-signal: [`docs/Tentura_current_status_quo.md`](docs/Tentura_current_status_quo.md), [`docs/features/beacon_room.md`](docs/features/beacon_room.md).

## Verify

```bash
cd packages/tentura_lints && dart test                                   # custom lint rules
cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos
cd packages/client && flutter test
cd packages/client && flutter test --update-goldens <path>               # regenerate a golden intentionally
```

CI (`.github/workflows/pipeline.yml`) runs the lint tests, `flutter analyze`,
`bash scripts/check-user-facing-terminology.sh`, and `flutter test` on every push to `main`.
