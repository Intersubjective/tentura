// Move cacheable Flutter web build outputs under /app-assets/<version>/.
import '../hook/build/versioned_web_assets.dart';
import '../hook/build/web_build_version.dart';

void main() => applyVersionedWebAssets(version: resolveWebBuildVersion());
