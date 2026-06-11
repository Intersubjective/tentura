// Regenerate wasm-preload-manifest.json + tentura-app-cache-sw.js from the
// finished build/web. Must run AFTER `flutter build web`: as a build hook the
// generator executed during compilation, scanning a half-populated build/web
// (fresh CI checkouts produced a manifest without main.dart.wasm, so the
// landing preload warmed almost nothing).
import '../hook/build/wasm_preload_artifacts.dart';

void main() => generateWasmPreloadArtifacts();
