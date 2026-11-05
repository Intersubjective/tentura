import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // Web versions and wasm preload artifacts are generated after compilation
    // into build/web, leaving source web/ files unchanged. Build hooks run during
    // compilation, before build/web is complete, which produced manifests
    // without main.dart.wasm on fresh checkouts (CI). Run
    // `dart run tool/trim_web_deploy_artifact.dart` then
    // `dart run tool/generate_wasm_preload_artifacts.dart` after
    // `flutter build web` instead (wired into pipeline.yml).
  });
}
