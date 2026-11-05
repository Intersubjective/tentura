@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';

const _sourceVersion = '0.0.0-dev';
final _clientRoot = Directory.current.absolute;
final _sourcePubspec = File('${_clientRoot.path}/pubspec.yaml');
final _sourceIndex = File('${_clientRoot.path}/web/index.html');

void main() {
  late Directory work;

  setUp(() {
    work = Directory.systemTemp.createTempSync('tentura_bootstrap_version_');
  });
  tearDown(() => work.deleteSync(recursive: true));

  group('web bootstrap versions are assigned at build time', () {
    test(
      'the source entry point carries a release-independent placeholder',
      () {
        expect(
          _bootstrapVersion(_sourceIndex.readAsStringSync()),
          _sourceVersion,
          reason:
              'A package release must not require another version edit in '
              'web/index.html.',
        );
      },
    );

    for (final buildId in ['', 'abcdef1234567890']) {
      final buildKind = buildId.isEmpty ? 'local' : 'CI';
      test(
        '$buildKind builds version deployed entry points and leave source bytes unchanged',
        () async {
          final fixture = _WebBuildFixture.create(
            work,
            buildKind,
            version: _nextPackageVersion(1),
            usePlaceholder: true,
          );
          final sourceBytes = fixture.index.readAsBytesSync();
          final manifestBytes = fixture
              .file('web/manifest.json')
              .readAsBytesSync();
          final packageVersion = Pubspec.parse(
            fixture.file('pubspec.yaml').readAsStringSync(),
          ).version.toString();
          final expected = buildId.isEmpty
              ? packageVersion
              : '$packageVersion-${buildId.substring(0, 12)}';

          await fixture.compileWebApp(buildId: buildId);
          expect(
            fixture.file('build/web/index.html').existsSync(),
            isTrue,
            reason:
                'The entry point must come from the real Flutter web build.',
          );
          for (final tool in [
            'trim_web_deploy_artifact',
            'apply_versioned_web_assets',
            'generate_wasm_preload_artifacts',
          ]) {
            final result = await fixture.runDart(
              ['tool/$tool.dart'],
              buildId: buildId,
            );
            _expectSuccess(result);
          }

          final verified = await fixture.runDart(
            ['tool/verify_web_version_consistency.dart', 'build/web'],
            buildId: buildId,
          );
          _expectSuccess(verified);
          expect(
            _bootstrapVersion(
              fixture.file('build/web/index.html').readAsStringSync(),
            ),
            expected,
          );
          final manifest =
              jsonDecode(
                    fixture.file('build/web/manifest.json').readAsStringSync(),
                  )
                  as Map<String, dynamic>;
          final preload =
              jsonDecode(
                    fixture
                        .file('build/web/wasm-preload-manifest.json')
                        .readAsStringSync(),
                  )
                  as Map<String, dynamic>;
          expect(manifest['version'], expected);
          expect(preload['version'], expected);
          expect(
            preload['sharedPreload'] as List,
            contains('/flutter_bootstrap.js?v=$expected'),
          );
          expect(
            fixture
                .file('build/web/tentura-app-cache-sw.js')
                .readAsStringSync(),
            contains("CACHE_VERSION = '$expected'"),
          );
          for (final deployment in ['dev', 'prod']) {
            final published = await Process.run('bash', [
              '${_clientRoot.parent.parent.path}/scripts/test_deploy_web_asset_publication.sh',
              deployment,
              'all',
              '${fixture.root.path}/build/web',
              expected,
            ]);
            _expectSuccess(published);
            expect(
              published.stdout,
              contains(
                'OK: $deployment deployment 2 serves the expected bootstrap version',
              ),
            );
          }
          expect(
            fixture.file('web/manifest.json').readAsBytesSync(),
            manifestBytes,
          );
          expect(
            fixture.index.readAsBytesSync(),
            sourceBytes,
            reason:
                'Building $expected must stamp only build/web; source '
                'web/index.html must remain byte-identical.',
          );
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    }

    test('independent built package bumps conflict only in pubspec', () async {
      // All three sides are explicit fixtures. They model independent bumps
      // from one checkout, regardless of the current branch or HEAD.
      final base = _WebBuildFixture.create(
        work,
        'base',
        version: '12.34.5',
        usePlaceholder: true,
      );
      final branches = [
        for (final patch in [6, 7])
          base.fork(
            work,
            'branch-$patch',
            version: '12.34.$patch',
          ),
      ];
      for (final branch in branches) {
        expect(branch.index.readAsBytesSync(), base.index.readAsBytesSync());
        expect(
          branch.file('pubspec.yaml').readAsStringSync(),
          isNot(base.file('pubspec.yaml').readAsStringSync()),
        );
        await branch.runBuildHook();
      }

      // merge-file exercises Git's three-way merge without creating commits
      // or consulting a branch that may already contain the work under test.
      final conflicts = <String>[];
      for (final path in [
        'pubspec.yaml',
        'web/index.html',
        'web/manifest.json',
      ]) {
        final result = await Process.run('git', [
          'merge-file',
          '-p',
          branches[0].file(path).path,
          base.file(path).path,
          branches[1].file(path).path,
        ]);
        expect(
          result.exitCode,
          anyOf(0, 1),
          reason: '${result.stdout}\n${result.stderr}',
        );
        if (result.exitCode == 1) conflicts.add('packages/client/$path');
      }
      expect(
        conflicts,
        ['packages/client/pubspec.yaml'],
        reason:
            'Two releases must leave only the package version for a lander '
            'to reconcile, even when both branches have run the build hook.',
      );
    });

    for (final step in [1, 2]) {
      final version = _nextPackageVersion(step);
      test(
        'source verification accepts the unchanged placeholder with pubspec $version',
        () async {
          final fixture = _WebBuildFixture.create(
            work,
            'source-$step',
            version: version,
            usePlaceholder: true,
          );
          final original = fixture.index.readAsBytesSync();
          expect(fixture.file('build/web/index.html').existsSync(), isFalse);

          final result = await fixture.runDart([
            'tool/verify_web_version_consistency.dart',
          ]);

          _expectSuccess(result);
          expect(
            result.stdout,
            contains(version),
            reason: 'The verifier must report the package version it checked.',
          );
          expect(fixture.index.readAsBytesSync(), original);
          expect(
            _bootstrapVersion(fixture.index.readAsStringSync()),
            _sourceVersion,
          );
        },
      );
    }
  });
}

String _nextPackageVersion(int step) {
  final version = Pubspec.parse(_sourcePubspec.readAsStringSync()).version!;
  return '${version.major}.${version.minor}.${version.patch + step}';
}

String? _bootstrapVersion(String html) {
  final scripts = RegExp(
    r'''<script\b[^>]*\bsrc=["']([^"']*flutter_bootstrap\.js[^"']*)["']''',
  ).allMatches(html).toList();
  expect(scripts, hasLength(1));
  return Uri.parse(scripts.single.group(1)!).queryParameters['v'];
}

void _expectSuccess(ProcessResult result) {
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
}

class _WebBuildFixture {
  _WebBuildFixture(this.root);

  factory _WebBuildFixture.create(
    Directory work,
    String name, {
    required String version,
    bool usePlaceholder = false,
  }) {
    final fixture = _WebBuildFixture(
      Directory('${work.path}/$name')..createSync(recursive: true),
    );
    for (final directory in ['hook', 'tool']) {
      for (final entry in Directory('${_clientRoot.path}/$directory').listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is! File || !entry.path.endsWith('.dart')) continue;
        final relative = entry.path.substring(_clientRoot.path.length + 1);
        fixture.file(relative)
          ..createSync(recursive: true)
          ..writeAsBytesSync(entry.readAsBytesSync());
      }
    }
    fixture
        .file('pubspec.yaml')
        .writeAsStringSync(
          _sourcePubspec.readAsStringSync().replaceFirst(
            RegExp(r'^version:.*$', multiLine: true),
            'version: $version',
          ),
        );
    fixture.index
      ..createSync(recursive: true)
      ..writeAsStringSync(
        usePlaceholder
            ? _sourceIndex.readAsStringSync().replaceFirst(
                RegExp(r'''flutter_bootstrap\.js\?v=[^"']+'''),
                'flutter_bootstrap.js?v=$_sourceVersion',
              )
            : _sourceIndex.readAsStringSync(),
      );
    fixture
        .file('web/manifest.json')
        .writeAsBytesSync(
          File('${_clientRoot.path}/web/manifest.json').readAsBytesSync(),
        );
    return fixture;
  }

  final Directory root;

  File file(String path) => File('${root.path}/$path');
  File get index => file('web/index.html');

  _WebBuildFixture fork(
    Directory work,
    String name, {
    required String version,
  }) {
    final branch = _WebBuildFixture(
      Directory('${work.path}/$name')..createSync(recursive: true),
    );
    for (final entry in root.listSync(recursive: true, followLinks: false)) {
      if (entry is! File) continue;
      final relative = entry.path.substring(root.path.length + 1);
      branch.file(relative)
        ..createSync(recursive: true)
        ..writeAsBytesSync(entry.readAsBytesSync());
    }
    final pubspec = branch.file('pubspec.yaml');
    pubspec.writeAsStringSync(
      pubspec.readAsStringSync().replaceFirst(
        RegExp(r'^version:.*$', multiLine: true),
        'version: $version',
      ),
    );
    return branch;
  }

  Future<ProcessResult> runDart(
    List<String> arguments, {
    String buildId = '',
  }) {
    var configRoot = root;
    if (!File('${root.path}/.dart_tool/package_config.json').existsSync()) {
      configRoot = _clientRoot;
    }
    while (!File(
      '${configRoot.path}/.dart_tool/package_config.json',
    ).existsSync()) {
      if (configRoot.parent.path == configRoot.path) {
        throw StateError(
          'No resolved package configuration above ${_clientRoot.path}',
        );
      }
      configRoot = configRoot.parent;
    }
    return Process.run(
      'dart',
      [
        '--packages=${configRoot.path}/.dart_tool/package_config.json',
        ...arguments,
      ],
      workingDirectory: root.path,
      environment: {'WEB_BUILD_ID': buildId},
    );
  }

  Future<void> runBuildHook({String buildId = ''}) async {
    final shared = Directory('${root.path}/hook-output/shared')
      ..createSync(recursive: true);
    final builder = BuildInputBuilder()
      ..setupShared(
        packageRoot: root.uri,
        packageName: 'tentura',
        outputFile: file('hook-output/output.json').uri,
        outputDirectoryShared: shared.uri,
      )
      ..setupBuildInput();
    builder.config.setupBuild(linkingEnabled: false);
    final config = file('hook-output/input.json')
      ..writeAsStringSync(jsonEncode(builder.build().json));
    final result = await runDart(
      ['hook/build.dart', '--config=${config.path}'],
      buildId: buildId,
    );
    _expectSuccess(result);
    expect(file('hook-output/output.json').existsSync(), isTrue);
  }

  Future<void> compileWebApp({required String buildId}) async {
    final version = Pubspec.parse(
      file('pubspec.yaml').readAsStringSync(),
    ).version;
    // Keep the real Tentura hook and web sources, with a small Flutter app so
    // this integration check does not compile unrelated product features.
    file('pubspec.yaml').writeAsStringSync('''
name: tentura
version: $version
environment:
  sdk: '>=3.12.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  hooks: 2.1.0
  pubspec_parse: 1.5.0
''');
    file('lib/main.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
import 'package:flutter/widgets.dart';
void main() => runApp(const Directionality(
  textDirection: TextDirection.ltr,
  child: Text('Release build'),
));
''');
    file('lib/config/build_id.dart')
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        File('${_clientRoot.path}/lib/config/build_id.dart').readAsBytesSync(),
      );
    // Static web inputs used by the publication test. Flutter itself must
    // produce index.html, flutter_bootstrap.js and all compiled entry points.
    for (final asset in [
      'assets/packages/sqlite3.wasm',
      'assets/packages/drift_worker.js',
    ]) {
      file('web/$asset')
        ..createSync(recursive: true)
        ..writeAsStringSync('static publication fixture');
    }
    File('${_clientRoot.path}/web/tentura-icon-192.png').copySync(
      file('web/tentura-icon-192.png').path,
    );

    final originalConfig = File(
      '${_clientRoot.parent.parent.path}/.dart_tool/package_config.json',
    );
    final config =
        jsonDecode(originalConfig.readAsStringSync()) as Map<String, dynamic>;
    final packages = (config['packages'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final flutter = packages.singleWhere(
      (entry) => entry['name'] == 'flutter',
    );
    final sdk = Directory.fromUri(
      originalConfig.uri.resolve(flutter['rootUri'] as String),
    ).parent.parent;
    final writableSdk = Directory('${root.path}/flutter-sdk')..createSync();
    // SDK installations are read-only in the agent sandbox. Give the real
    // Flutter CLI writable stamp/lock files, sharing its immutable artifacts.
    for (final entry in sdk.listSync(followLinks: false)) {
      final name = entry.path.split(Platform.pathSeparator).last;
      if (name == 'bin') continue;
      Link('${writableSdk.path}/$name').createSync(entry.path);
    }
    Directory('${writableSdk.path}/bin').createSync();
    for (final name in ['flutter', 'dart']) {
      File('${sdk.path}/bin/$name').copySync('${writableSdk.path}/bin/$name');
    }
    final internalCopy = await Process.run('cp', [
      '-a',
      '${sdk.path}/bin/internal',
      '${writableSdk.path}/bin/internal',
    ]);
    _expectSuccess(internalCopy);
    final cache = Directory('${writableSdk.path}/bin/cache')..createSync();
    for (final entry in Directory(
      '${sdk.path}/bin/cache',
    ).listSync(followLinks: false)) {
      final name = entry.path.split(Platform.pathSeparator).last;
      if (entry is File) {
        entry.copySync('${cache.path}/$name');
      } else {
        Link('${cache.path}/$name').createSync(entry.path);
      }
    }
    final pubCache = Directory('${root.path}/pub-cache')..createSync();
    final sharedPubCache = Directory.fromUri(
      originalConfig.uri.resolve(
        packages.singleWhere(
              (entry) => entry['name'] == 'hooks',
            )['rootUri']
            as String,
      ),
    ).parent.parent.parent;
    for (final entry in sharedPubCache.listSync(followLinks: false)) {
      final name = entry.path.split(Platform.pathSeparator).last;
      if (['active_roots', 'log', '_temp'].contains(name)) continue;
      Link('${pubCache.path}/$name').createSync(entry.path);
    }
    final environment = {
      'FLUTTER_ROOT': writableSdk.path,
      'PUB_CACHE': pubCache.path,
      'FLUTTER_SUPPRESS_ANALYTICS': 'true',
      'DASH__SUPPRESS_ANALYTICS': 'true',
      'WEB_BUILD_ID': buildId,
    };
    final pub = await Process.run(
      '${writableSdk.path}/bin/flutter',
      ['pub', 'get', '--offline'],
      workingDirectory: root.path,
      environment: environment,
    );
    _expectSuccess(pub);
    final built = await Process.run(
      '${writableSdk.path}/bin/flutter',
      ['build', 'web', '--release', '--wasm', '--no-pub'],
      workingDirectory: root.path,
      environment: environment,
    );
    _expectSuccess(built);
  }
}
