import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../hook/build/versioned_web_assets.dart' as assets;
import '../../hook/build/wasm_preload_artifacts.dart' as preload;
import '../../hook/build/web_build_version.dart';

void main() {
  test(
    'versioned database assets are packaged and root worker leftovers are rejected',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'tentura_versioned_web_test',
      );
      try {
        const buildId = 'database-assets';
        final version = resolveWebBuildVersion(buildId: buildId);
        _writeBuildFixture(dir);

        assets.applyVersionedWebAssets(buildWebDir: dir.path, version: version);
        preload.generateWasmPreloadArtifacts(
          buildWebDir: dir.path,
          version: version,
        );

        final prefix = '/app-assets/$version/';
        expect(Directory('${dir.path}/assets').existsSync(), isFalse);
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
        // #808: skwasm runs single-threaded until the upstream FreeType lock
        // fix ships (see kForceSingleThreadedSkwasm).
        expect(bootstrap, contains('forceSingleThreadedSkwasm:true'));

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

        for (final name in ['sqlite3.wasm', 'drift_worker.js']) {
          final url = '${prefix}assets/packages/$name';
          expect(File('${dir.path}$url').existsSync(), isTrue);
          expect(wasmManifest['sharedPreload'] as List, contains(url));
          expect(sw, contains(url));
        }
        Future<ProcessResult> verify() => Process.run(
          'dart',
          ['run', 'tool/verify_web_version_consistency.dart', dir.path],
          environment: {'WEB_BUILD_ID': buildId},
        );
        final valid = await verify();
        expect(valid.exitCode, 0, reason: '${valid.stdout}\n${valid.stderr}');

        // A leftover is a real file, so checking existence alone accepts the
        // stale worker that the browser used before this deployment.
        const rootWorker = '/assets/packages/drift_worker.js';
        File('${dir.path}$rootWorker')
          ..createSync(recursive: true)
          ..writeAsStringSync('old worker');
        final paths = wasmManifest['sharedPreload'] as List;
        paths[paths.indexOf('${prefix}assets/packages/drift_worker.js')] =
            rootWorker;
        File(
          '${dir.path}/wasm-preload-manifest.json',
        ).writeAsStringSync(jsonEncode(wasmManifest));
        final invalid = await verify();
        expect(
          invalid.exitCode,
          1,
          reason:
              'Root worker URLs must fail even when the leftover exists.\n'
              '${invalid.stdout}\n${invalid.stderr}',
        );
        expect(invalid.stderr, contains(rootWorker));
      } finally {
        dir.deleteSync(recursive: true);
      }
    },
  );

  test(
    'keeps root PWA icons at origin and does not prefix absolute icon URLs',
    () {
      final dir = Directory.systemTemp.createTempSync(
        'tentura_versioned_pwa_icon_test',
      );
      try {
        const version = '4.0.0-deadbeef1234';
        _writeBuildFixture(dir);
        File('${dir.path}/tentura-icon-192.png').writeAsStringSync('icon');
        File('${dir.path}/index.html').writeAsStringSync(
          '<link rel="apple-touch-icon" href="/tentura-icon-192.png">'
          ' <link rel="icon" type="image/png" href="favicon.png">',
        );
        File('${dir.path}/manifest.json').writeAsStringSync(
          jsonEncode({
            'name': 'Tentura',
            'icons': [
              {'src': '/tentura-icon-192.png', 'sizes': '192x192'},
              {'src': 'icons/Icon-192.png', 'sizes': '192x192'},
            ],
          }),
        );

        assets.applyVersionedWebAssets(buildWebDir: dir.path, version: version);

        const prefix = '/app-assets/$version/';
        expect(File('${dir.path}/tentura-icon-192.png').existsSync(), isTrue);
        expect(
          File(
            '${dir.path}/app-assets/$version/tentura-icon-192.png',
          ).existsSync(),
          isFalse,
        );

        final index = File('${dir.path}/index.html').readAsStringSync();
        expect(index, contains('href="/tentura-icon-192.png"'));
        expect(index, isNot(contains('${prefix}tentura-icon-192.png')));

        final icons =
            (jsonDecode(File('${dir.path}/manifest.json').readAsStringSync())
                    as Map<String, dynamic>)['icons']
                as List;
        expect(icons[0]['src'], '/tentura-icon-192.png');
        expect(icons[1]['src'], '${prefix}icons/Icon-192.png');
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
