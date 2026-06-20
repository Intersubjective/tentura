import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../hook/build/wasm_preload_artifacts.dart' as hook;

void main() {
  test('generateWasmPreloadArtifacts writes manifest and service worker', () {
    final dir = Directory.systemTemp.createTempSync('tentura_web_test');
    try {
      File('${dir.path}/main.dart.wasm').writeAsStringSync('');
      File('${dir.path}/flutter_bootstrap.js').writeAsStringSync('');
      File('${dir.path}/index.html').writeAsStringSync(
        '<script src="flutter_bootstrap.js?v=9.9.9"></script>',
      );
      if (!File('pubspec.yaml').existsSync()) {
        return;
      }
      hook.generateWasmPreloadArtifacts(buildWebDir: dir.path);

      final manifest = File('${dir.path}/wasm-preload-manifest.json');
      final sw = File('${dir.path}/tentura-app-cache-sw.js');
      expect(manifest.existsSync(), isTrue);
      expect(sw.existsSync(), isTrue);
      expect(manifest.readAsStringSync(), contains('main.dart.wasm'));
      expect(sw.readAsStringSync(), contains('tentura-app-assets-'));
      expect(sw.readAsStringSync(), contains("'/invite/'"));
      final swBody = sw.readAsStringSync();
      expect(swBody.contains('"/"') || swBody.contains("'/'"), isFalse);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('all entry points agree on the explicit build version', () {
    final dir = Directory.systemTemp.createTempSync('tentura_web_test');
    try {
      const buildVersion = '7.7.7-deadbeef';
      File('${dir.path}/main.dart.wasm').writeAsStringSync('');
      File('${dir.path}/flutter_bootstrap.js').writeAsStringSync('');
      // Stale cache-busting query that must be corrected to [buildVersion].
      File('${dir.path}/index.html').writeAsStringSync(
        '<script src="flutter_bootstrap.js?v=0.0.1" async=""></script>',
      );
      File('${dir.path}/manifest.json').writeAsStringSync(
        jsonEncode({'name': 'Tentura', 'version': '0.0.1'}),
      );

      hook.generateWasmPreloadArtifacts(
        buildWebDir: dir.path,
        version: buildVersion,
      );

      final index = File('${dir.path}/index.html').readAsStringSync();
      final pwaManifest = jsonDecode(
        File('${dir.path}/manifest.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final preload = jsonDecode(
        File('${dir.path}/wasm-preload-manifest.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final sw = File('${dir.path}/tentura-app-cache-sw.js').readAsStringSync();

      expect(index, contains('flutter_bootstrap.js?v=$buildVersion'));
      expect(index, isNot(contains('?v=0.0.1')));
      expect(pwaManifest['version'], buildVersion);
      expect(preload['version'], buildVersion);
      expect(sw, contains("CACHE_VERSION = '$buildVersion'"));
      // Preload list keeps the versioned bootstrap so the SW caches it.
      expect(
        (preload['preload'] as List).cast<String>(),
        contains('/flutter_bootstrap.js?v=$buildVersion'),
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
