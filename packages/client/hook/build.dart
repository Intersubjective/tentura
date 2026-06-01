import 'package:hooks/hooks.dart';

import 'build/version_update.dart';
import 'build/wasm_preload_artifacts.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    versionUpdate();
    generateWasmPreloadArtifacts();
  });
}
