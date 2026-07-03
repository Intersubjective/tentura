# Tentura

Social network based on MeritRank

## Architecture (short)

- **`analysis_server_plugin`:** repo package **`packages/tentura_lints`** (see root **`DEV_GUIDELINES.md`** § *Layer boundaries*; enabled in root **`analysis_options.yaml`**).
- **Orchestration:** prefer `**lib/features/*/domain/use_case/*_case.dart*`* for multi-repo flows; cubits avoid `**data/service/**` imports.
- **Analyze:** match CI — `flutter analyze --no-fatal-warnings --no-fatal-infos` before opening a PR.

## How to build

Tentura uses codegen. So, before building the project as usual set .env, run the codegenerator:

```bash
flutter gen-l10n

dart run build_runner build -d

flutter build web --wasm --pwa-strategy=none --source-maps --dart-define-from-file=.env

dart run tool/apply_google_maps_web_key.dart
dart run tool/trim_web_deploy_artifact.dart
dart run tool/generate_wasm_preload_artifacts.dart
dart run tool/verify_web_version_consistency.dart
```

Set `GOOGLE_MAPS_API_KEY` in the same `.env` used for Dart defines. For
Android local builds, also put it in `android/local.properties`; for iOS local
builds, create `ios/Flutter/MapsKeys.xcconfig` with
`GOOGLE_MAPS_API_KEY=<restricted key>`.

To make database migration:

- increment `schemaVersion` at Database
- then run:

```bash
dart run drift_dev make-migrations
```
