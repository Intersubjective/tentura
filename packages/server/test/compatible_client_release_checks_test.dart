@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final repo = Directory.current.absolute.parent.parent;
  final sourcePackages = repo.uri.resolve('packages/');
  late Directory release;
  late File packageConfig;
  late Uri testRunner;

  setUp(() {
    release = Directory.systemTemp.createTempSync('tentura_client_release_');
    addTearDown(() => release.deleteSync(recursive: true));

    final sourceConfig = File.fromUri(
      repo.uri.resolve('.dart_tool/package_config.json'),
    );
    final config = jsonDecode(sourceConfig.readAsStringSync());
    final packages = switch (config) {
      {'packages': final List<Object?> packages} => packages,
      _ => fail('The workspace package configuration must list packages.'),
    };
    for (final entry in packages) {
      final (package, rootUri) = switch (entry) {
        final Map<String, Object?> package && {'rootUri': final String uri} => (
          package,
          uri,
        ),
        _ => fail('Each workspace package must have a root URI.'),
      };
      final root = Directory.fromUri(sourceConfig.uri.resolve(rootUri)).uri;
      package['rootUri'] = root.toString();
      if (package['name'] == 'test') {
        testRunner = root.resolve('bin/test.dart');
      }
    }
    packageConfig =
        File.fromUri(
            release.uri.resolve('.dart_tool/package_config.json'),
          )
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode(config));

    final pubspec = File.fromUri(
      sourcePackages.resolve('client/pubspec.yaml'),
    ).readAsStringSync();
    final version = RegExp(r'^version: (\d+\.\d+\.)(\d+)$', multiLine: true);
    final match = version.allMatches(pubspec).single;
    final nextVersion = '${match[1]}${int.parse(match[2]!) + 1}';
    File.fromUri(release.uri.resolve('packages/client/pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        pubspec.replaceRange(
          match.start,
          match.end,
          'version: $nextVersion',
        ),
      );

    // Only the client release changes. The server and its sample override
    // continue to describe the deployed compatibility floor.
    for (final path in [
      'packages/client/dart_test.yaml',
      'packages/client/hook',
      'packages/client/l10n',
      'packages/client/lib',
      'packages/client/tool',
      'packages/client/web',
      'packages/server/dart_test.yaml',
      'packages/server/lib',
      'packages/server/test/support/shipped_client_version.dart',
      '.env.example',
    ]) {
      Link.fromUri(release.uri.resolve(path)).createSync(
        File.fromUri(repo.uri.resolve(path)).path,
        recursive: true,
      );
    }
  });

  Future<void> expectReleaseCheckPasses(
    String package,
    String testPath, {
    String? testName,
  }) async {
    final releasePackage = release.uri.resolve('packages/$package/');
    final testFile = 'test/$testPath';
    final fixtureTest = File.fromUri(releasePackage.resolve(testFile));
    fixtureTest.parent.createSync(recursive: true);
    File.fromUri(sourcePackages.resolve('$package/$testFile')).copySync(
      fixtureTest.path,
    );

    // Both the test entry point and its working directory are in the fixture.
    // Relative reads such as ../client/pubspec.yaml use the staged release.
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        '--packages=${packageConfig.path}',
        File.fromUri(testRunner).path,
        testFile,
        if (testName != null) '--plain-name=$testName',
      ],
      workingDirectory: releasePackage.toFilePath(),
      environment: Map.of(Platform.environment)
        ..remove('MIN_CLIENT_VERSION')
        ..remove('WEB_BUILD_ID'),
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  group('a compatible client patch release keeps the existing server floor', () {
    test('the web release check accepts the newer deployed version', () async {
      await expectReleaseCheckPasses(
        'client',
        'hook/web_bootstrap_build_time_version_test.dart',
        testName:
            'the deployed web release stamps the supported client version into its entry points',
      );
    }, timeout: const Timeout(Duration(minutes: 6)));

    test(
      'the current release check accepts the newer client version',
      () async {
        await expectReleaseCheckPasses(
          'server',
          'current_client_release_test.dart',
        );
      },
    );

    test('the coordinated release check accepts the existing floor', () async {
      await expectReleaseCheckPasses(
        'server',
        'coordinated_client_release_test.dart',
      );
    });
  });
}
