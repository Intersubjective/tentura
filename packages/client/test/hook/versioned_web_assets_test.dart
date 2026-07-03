import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../hook/build/versioned_web_assets.dart' as assets;
import '../../hook/build/wasm_preload_artifacts.dart' as preload;

void main() {
  test(
    'moves app assets under immutable version prefix and rewrites entries',
    () {
      final dir = Directory.systemTemp.createTempSync(
        'tentura_versioned_web_test',
      );
      try {
        const version = '4.0.0-deadbeef1234';
        _writeBuildFixture(dir);

        assets.applyVersionedWebAssets(buildWebDir: dir.path, version: version);
        preload.generateWasmPreloadArtifacts(
          buildWebDir: dir.path,
          version: version,
        );

        const prefix = '/app-assets/$version/';
        expect(File('${dir.path}/main.dart.wasm').existsSync(), isFalse);
        expect(
          File('${dir.path}/app-assets/$version/main.dart.wasm').existsSync(),
          isTrue,
        );
        expect(
          File(
            '${dir.path}/app-assets/$version/assets/packages/sqlite3.wasm',
          ).existsSync(),
          isTrue,
        );
        expect(File('${dir.path}/index.html').existsSync(), isTrue);
        expect(File('${dir.path}/flutter_bootstrap.js').existsSync(), isTrue);
        expect(File('${dir.path}/manifest.json').existsSync(), isTrue);
        expect(
          File('${dir.path}/google_maps_config.js').existsSync(),
          isTrue,
        );
        expect(
          File(
            '${dir.path}/app-assets/$version/google_maps_config.js',
          ).existsSync(),
          isFalse,
        );

        final bootstrap = File(
          '${dir.path}/flutter_bootstrap.js',
        ).readAsStringSync();
        expect(
          bootstrap,
          contains('entrypointBaseUrl:new URL("$prefix",document.baseURI)'),
        );
        expect(
          bootstrap,
          contains(
            'canvasKitBaseUrl:new URL("${prefix}canvaskit/",document.baseURI)',
          ),
        );
        expect(
          bootstrap,
          contains('assetBase:new URL("$prefix",document.baseURI)'),
        );
        expect(bootstrap, isNot(contains('_flutter.loader.load();')));

        final index = File('${dir.path}/index.html').readAsStringSync();
        expect(index, contains('href="${prefix}icons/Icon-192.png"'));
        expect(index, contains('href="${prefix}favicon.png"'));
        expect(index, contains('srcset="${prefix}splash/img/light-1x.png 1x'));
        expect(index, contains(', ${prefix}splash/img/light-2x.png 2x'));
        expect(index, contains('src="${prefix}splash/img/light-1x.png"'));

        final pwaManifest =
            jsonDecode(
                  File('${dir.path}/manifest.json').readAsStringSync(),
                )
                as Map<String, dynamic>;
        final icons = (pwaManifest['icons'] as List)
            .cast<Map<String, dynamic>>();
        expect(icons.first['src'], '${prefix}icons/Icon-192.png');

        final wasmManifest =
            jsonDecode(
                  File(
                    '${dir.path}/wasm-preload-manifest.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        expect(wasmManifest['mainWasm'], '${prefix}main.dart.wasm');
        expect(
          (wasmManifest['sharedPreload'] as List).cast<String>(),
          contains('${prefix}assets/packages/sqlite3.wasm'),
        );
        expect(
          (wasmManifest['wasmPreload'] as List).cast<String>(),
          contains('${prefix}main.dart.mjs'),
        );
        expect(
          (wasmManifest['jsPreload'] as List).cast<String>(),
          contains('${prefix}main.dart.js'),
        );

        final sw = File(
          '${dir.path}/tentura-app-cache-sw.js',
        ).readAsStringSync();
        expect(sw, contains('${prefix}main.dart.wasm'));
        expect(sw, contains('${prefix}main.dart.js'));
        expect(sw.contains('"/"') || sw.contains("'/'"), isFalse);
      } finally {
        dir.deleteSync(recursive: true);
      }
    },
  );
}

void _writeBuildFixture(Directory dir) {
  File('${dir.path}/main.dart.wasm').writeAsStringSync('');
  File('${dir.path}/main.dart.mjs').writeAsStringSync('');
  File('${dir.path}/main.dart.js').writeAsStringSync('');
  File('${dir.path}/main.dart.js.map').writeAsStringSync('');
  File('${dir.path}/flutter_bootstrap.js').writeAsStringSync(
    '_flutter.buildConfig = {};_flutter.loader.load();',
  );
  File('${dir.path}/index.html').writeAsStringSync(
    '<link rel="apple-touch-icon" href="icons/Icon-192.png">'
    ' <link rel="icon" type="image/png" href="favicon.png">'
    ' <script src="flutter_bootstrap.js?v=0.0.1"></script>'
    ' <source srcset="splash/img/light-1x.png 1x, splash/img/light-2x.png 2x">'
    ' <img src="splash/img/light-1x.png">',
  );
  File('${dir.path}/manifest.json').writeAsStringSync(
    jsonEncode({
      'name': 'Tentura',
      'version': '0.0.1',
      'icons': [
        {'src': 'icons/Icon-192.png', 'sizes': '192x192'},
      ],
    }),
  );
  File('${dir.path}/version.json').writeAsStringSync('{}');
  File('${dir.path}/firebase-messaging-sw.js').writeAsStringSync('');
  File(
    '${dir.path}/google_maps_config.js',
  ).writeAsStringSync('window.tenturaGoogleMapsApiKey = "test-key";\n');

  Directory('${dir.path}/assets/packages').createSync(recursive: true);
  File('${dir.path}/assets/packages/sqlite3.wasm').writeAsStringSync('');
  File('${dir.path}/assets/packages/drift_worker.js').writeAsStringSync('');
  Directory('${dir.path}/canvaskit').createSync();
  File('${dir.path}/canvaskit/canvaskit.js').writeAsStringSync('');
  Directory('${dir.path}/icons').createSync();
  File('${dir.path}/icons/Icon-192.png').writeAsStringSync('');
  Directory('${dir.path}/splash/img').createSync(recursive: true);
  File('${dir.path}/splash/img/light-1x.png').writeAsStringSync('');
  File('${dir.path}/splash/img/light-2x.png').writeAsStringSync('');
}
