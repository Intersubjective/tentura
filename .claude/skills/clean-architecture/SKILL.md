---
name: clean-architecture
description: >
  Enforce Tentura's Clean Architecture + SOLID layer rules. Activate for ANY
  Dart work touching domain/, data/, or ui/ layers, features/** modules, use
  cases (*_case.dart), repositories (*_repository.dart), cubits/states, ports,
  entities, or DI wiring (di.dart, Injectable) — in both packages/client and
  packages/server. Dependency direction is inward: UI → Data → Domain →
  nothing; domain stays pure.
---

# Clean Architecture (Tentura)

**Canonical source:** [`.cursor/rules/architecture.mdc`](../../../.cursor/rules/architecture.mdc)
— Read it before non-trivial layer/DI work; this skill is the condensed
contract. Base classes, exception hierarchy, and platform abstraction live in
[`.cursor/rules/advanced-patterns.mdc`](../../../.cursor/rules/advanced-patterns.mdc);
codegen (Freezed, Ferry, Auto Route, Injectable) in
[`.cursor/rules/codegen.mdc`](../../../.cursor/rules/codegen.mdc).

## Dependency direction (never reverse)

```
UI  →  Data  →  Domain  →  (nothing, pure)
```

Outer layers depend on inner **abstractions**; data **implements** domain
contracts. It is *not* "domain depends on data".

## Layers

Each feature: `features/<name>/{data,domain,ui}`. Shared domain in
`lib/domain/` (entities like `Beacon`, `Profile`; enums; exceptions;
`UseCaseBase`).

- **Domain** — Freezed entities, use cases (extend `UseCaseBase`), ports
  (`*_repository_port.dart` on server), domain exceptions. No I/O, no
  framework types, no imports from `data/` or `ui/`.
- **Data** — repositories (`@lazySingleton`, return domain entities via
  `toEntity()`), extension-type models wrapping Ferry types, services.
  Ferry/Drift/plugin types never leak out; expose domain DTOs (e.g.
  `ImagePicked`) at repository boundaries.
- **UI** — Cubits with Freezed states extending `StateBase`
  (`ScreenState` in `ui/bloc/screen_state.dart`), `@RoutePage()` screens.
  Only `emit(state.copyWith(...))` with **new** `List`/`Map` instances —
  never mutate collections held in state.

## Forbidden (most are lint/CI-enforced)

- ❌ Domain importing `data/` or `ui/` (client: `tentura_lints`; server:
  `rg "package:tentura_server/data/repository" packages/server/lib/domain`
  must stay empty — use cases import `domain/port/` only, repos register
  `@Injectable(as: …Port)` / `@Singleton(as: …Port)`)
- ❌ Data importing UI
- ❌ Ferry types in UI — use domain entities
- ❌ Cubit importing `data/service/` (lint: `no_cubit_to_data_service_import`)
  — go through repositories or use cases

## Orchestration rule

Cubit coordinating **multiple repos**, streams, or non-trivial workflows →
inject a `features/*/domain/use_case/*_case.dart`. Thin single-repo cubits
may inject the repository directly. Business logic lives in use cases, not
repositories.

## DI (Injectable)

- Use cases `@singleton`; repositories `@lazySingleton`; services per usage.
- Prod repos are env-scoped `env: [Environment.dev, Environment.prod]`;
  Mockito stubs in `packages/client/lib/data/repository/mock/client_repository_mocks.dart`
  register with `env: [Environment.test], order: 1`.
- Constructor injection preferred; `@FactoryMethod()` for async init.
- After DI changes: run build_runner; client tests need
  `flutter test --dart-define=ENV=test`.

## Canonical examples (read, don't copy)

- Use case: `packages/client/lib/features/beacon_view/domain/use_case/beacon_view_case.dart`
- Repository: `packages/client/lib/features/beacon_view/data/repository/coordination_repository.dart`
- Cubit: `packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart`

## Checks before final answer

1. Layer-boundary greps clean (server ports rule above; no new domain→data/ui
   imports).
2. `dart analyze` (server) / `flutter analyze --no-fatal-warnings
   --no-fatal-infos` (client) — note: `tentura_lints` custom rules don't fire
   under CLI analyze; the real gate is `cd packages/tentura_lints && dart test`.
3. If you spot codebase patterns consistently diverging from these rules,
   tell the user and suggest updating `architecture.mdc` — don't silently
   fork the convention.
