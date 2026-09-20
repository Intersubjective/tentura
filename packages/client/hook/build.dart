import 'package:hooks/hooks.dart';

import 'build/version_update.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // Source tree only: the PWA manifest is deliberately left alone here and
    // stamped into build/web by the post-build tool instead. See versionUpdate.
    versionUpdate(includeManifest: false);
    // wasm preload artifacts are NOT generated here: build hooks run during
    // compilation, before build/web is complete, which produced manifests
    // without main.dart.wasm on fresh checkouts (CI). Run
    // `dart run tool/trim_web_deploy_artifact.dart` then
    // `dart run tool/generate_wasm_preload_artifacts.dart` after
    // `flutter build web` instead (wired into pipeline.yml).
  });
}
