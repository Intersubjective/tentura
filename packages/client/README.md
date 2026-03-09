# Tentura

Social network based on MeritRank

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
