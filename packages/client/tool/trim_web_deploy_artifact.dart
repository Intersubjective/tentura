// Remove dead-weight from build/web after `flutter build web --wasm`.
// Run BEFORE generate_wasm_preload_artifacts.dart.
import '../hook/build/trim_web_deploy_artifact.dart';

void main() => trimWebDeployArtifact();
