import 'package:hooks/hooks.dart';

import 'build/version_update.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    versionUpdate();
    // wasm preload artifacts are NOT generated here: build hooks run during
    // compilation, before build/web is complete, which produced manifests
    // without main.dart.wasm on fresh checkouts (CI). Run
    // `dart run tool/generate_wasm_preload_artifacts.dart` after
    // `flutter build web` instead (wired into pipeline.yml).
  });
}
