# Tentura

Social network based on MeritRank

## Architecture (short)

- **`custom_lint`:** repo package **`packages/tentura_lints`** (see root **`DEV_GUIDELINES.md`** § *Layer boundaries*).
- **Orchestration:** prefer **`lib/features/*/domain/use_case/*_case.dart`** for multi-repo flows; cubits avoid **`data/service/`** imports.
- **Analyze:** match CI — `flutter analyze --fatal-infos` before opening a PR.

## How to build

Tentura uses codegen. So, before building the project as usual set .env, run the codegenerator:

```bash
flutter gen-l10n

dart run build_runner build -d

flutter build web --wasm --pwa-strategy=none --source-maps --dart-define-from-file=.env
```

To make database migration:
 - increment `schemaVersion` at Database
 - then run:

```bash
dart run drift_dev make-migrations
```
