// Regenerate wasm-preload-manifest.json + tentura-app-cache-sw.js from the
// finished build/web. Must run AFTER trim_web_deploy_artifact.dart and
// `flutter build web`: as a build hook the generator executed during
// generator executed during compilation, scanning a half-populated build/web
// (fresh CI checkouts produced a manifest without main.dart.wasm, so the
// landing preload warmed almost nothing).
//
// The cache version embeds a per-deploy build id (WEB_BUILD_ID, set to the
// commit SHA in CI) so every deploy gets a unique SW cache, forcing returning
// clients to pick up new assets on a normal refresh.
import '../hook/build/wasm_preload_artifacts.dart';
import '../hook/build/web_build_version.dart';

void main() =>
    generateWasmPreloadArtifacts(version: resolveWebBuildVersion());
