// Test fixture: run the production post-build pipeline on the database app.
import '../../hook/build/trim_web_deploy_artifact.dart';
import '../../hook/build/versioned_web_assets.dart';
import '../../hook/build/wasm_preload_artifacts.dart';
import '../../hook/build/web_build_version.dart';

void main(List<String> args) {
  final directory = args.single;
  final version = resolveWebBuildVersion(buildId: 'database-url-browser');
  trimWebDeployArtifact(buildWebDir: directory);
  applyVersionedWebAssets(buildWebDir: directory, version: version);
  generateWasmPreloadArtifacts(buildWebDir: directory, version: version);
}
