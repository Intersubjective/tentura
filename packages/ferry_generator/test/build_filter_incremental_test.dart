@TestOn('vm')
@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// End-to-end regression for tentura-cz0, using the real `build_runner` and
/// the Tentura client's own `beacon_fact_card_list` setup.
///
/// The fixture package is named `tentura`, lays out the client's real
/// `lib/data/gql/schema.graphql`, `beacon_fact_card_list.graphql` and custom
/// serializers at the client's paths, and takes its
/// `ferry_generator|graphql_builder` / `serializer_builder` options verbatim
/// from `packages/client/build.yaml` (`schema: tentura|...`, `output_dir: _g`,
/// type overrides, custom serializers). Nothing in the client checkout is
/// touched: all edits happen on the temp copy.
///
/// After a schema-only change, a build narrowed with `--build-filter` to the
/// operation's `.graphql` source must refresh every operation output, not only
/// the build that is filtered to an output path.
void main() {
  const operationDir = 'lib/features/beacon_threads/data/gql';
  const schemaPath = 'lib/data/gql/schema.graphql';
  const operationName = 'beacon_fact_card_list';
  const generatedExtensions = [
    'ast.gql.dart',
    'data.gql.dart',
    'data.gql.g.dart',
    'var.gql.dart',
    'var.gql.g.dart',
    'req.gql.dart',
    'req.gql.g.dart',
  ];

  // `packages/ferry_generator` is the working directory under `dart test`.
  final clientDir = p.normalize(p.join(Directory.current.path, '..', 'client'));
  late Directory workDir;

  File inWork(String relative) => File(p.join(workDir.path, relative));

  File generated(String extension) =>
      inWork('$operationDir/_g/$operationName.$extension');

  Future<ProcessResult> dart(List<String> args) => Process.run(
        Platform.resolvedExecutable,
        args,
        workingDirectory: workDir.path,
      );

  Future<String> buildRunner(List<String> args) async {
    final result = await dart(['run', 'build_runner', 'build', ...args]);
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    return output;
  }

  Map<String, String> snapshotOperationOutputs() => {
        for (final extension in generatedExtensions)
          extension: generated(extension).readAsStringSync(),
      };

  // The report's timestamps: schema.graphql is newer than the operation
  // outputs, and it is not touched again after the outputs went stale.
  final schemaModified = DateTime.utc(2026, 9, 28);
  final outputsModified = DateTime.utc(2026, 9, 27);
  const staleMarker = '// STALE: generated before the schema change';
  const staleOutputs = [
    'ast.gql.dart',
    'data.gql.dart',
    'var.gql.dart',
    'req.gql.dart',
  ];

  /// Changes `v2_BeaconFactCardRow.revisionSeq` in the schema (the field
  /// `BeaconFactCardList` selects) and leaves every operation output stale:
  /// each `graphql_builder` output (ast/data/var/req) gets a marker that a
  /// regeneration would drop, and is dated before `schema.graphql`, which keeps
  /// the newer date. The operation document is not touched.
  void makeOperationOutputsStaleBySchemaChange(String to) {
    final schemaFile = inWork(schemaPath);
    final source = schemaFile.readAsStringSync();
    final updated = source.replaceFirstMapped(
      RegExp(r'(type v2_BeaconFactCardRow \{[^}]*?\brevisionSeq: )\w+!'),
      (match) => '${match[1]}$to!',
    );
    expect(updated, isNot(source), reason: 'schema.graphql was not changed');
    schemaFile
      ..writeAsStringSync(updated)
      ..setLastModifiedSync(schemaModified);
    for (final extension in staleOutputs) {
      generated(extension)
        ..writeAsStringSync(
          '${generated(extension).readAsStringSync()}\n$staleMarker\n',
        )
        ..setLastModifiedSync(outputsModified);
    }
  }

  void expectNotStale(String extension) {
    expect(
      generated(extension).readAsStringSync(),
      isNot(contains(staleMarker)),
      reason: '$operationName.$extension was not regenerated after the '
          'schema change',
    );
  }

  setUpAll(() async {
    workDir = await Directory.systemTemp.createTemp('ferry_generator_cz0_');

    // Real client sources, copied to the client's own relative paths.
    for (final relative in [
      schemaPath,
      '$operationDir/$operationName.graphql',
      'lib/data/gql/timestamptz_serializer.dart',
      'lib/data/gql/tentura_v2_upload.dart',
      'lib/data/gql/tentura_v2_upload_serializer.dart',
      'lib/data/gql/float8_serializer.dart',
      'lib/data/gql/smallint_serializer.dart',
    ]) {
      inWork(relative)
        ..createSync(recursive: true)
        ..writeAsStringSync(
            File(p.join(clientDir, relative)).readAsStringSync());
    }

    // Builder options come straight from the client's build.yaml.
    final clientBuilders =
        (loadYaml(File(p.join(clientDir, 'build.yaml')).readAsStringSync())
            as YamlMap)['targets']['\$default']['builders'] as YamlMap;
    inWork('build.yaml').writeAsStringSync(
      jsonEncode({
        'targets': {
          r'$default': {
            'builders': {
              for (final key in [
                'ferry_generator|graphql_builder',
                'ferry_generator|serializer_builder',
              ])
                key: clientBuilders[key],
            },
          },
        },
      }),
    );

    inWork('pubspec.yaml').writeAsStringSync('''
name: tentura
publish_to: none
environment:
  sdk: ">=3.6.0 <4.0.0"
dependencies:
  built_collection: ^5.1.1
  built_value: ^8.12.6
  ferry: any
  ferry_exec: any
  gql: any
  gql_code_builder_serializers: any
  gql_tristate_value: any
dev_dependencies:
  build_runner: 2.16.0
  built_value_generator: ^8.12.6
  ferry_generator:
    path: ${Directory.current.absolute.path}
''');

    final pubGet = await dart(['pub', 'get', '--offline']);
    expect(pubGet.exitCode, 0, reason: '${pubGet.stdout}\n${pubGet.stderr}');

    await buildRunner([]);
    expect(
      generated('data.gql.dart').readAsStringSync(),
      contains('int get revisionSeq'),
    );
  });

  tearDownAll(() async {
    if (workDir.existsSync()) await workDir.delete(recursive: true);
  });

  group('schema-only change to the BeaconFactCardList result type', () {
    test(
      'is picked up under a filter on the output path (control)',
      () async {
        makeOperationOutputsStaleBySchemaChange('String');
        expect(
          generated('data.gql.dart').readAsStringSync(),
          isNot(contains('String get revisionSeq')),
          reason: 'precondition: the data output must be stale',
        );

        await buildRunner([
          '--build-filter=$operationDir/_g/$operationName.data.gql.dart',
        ]);

        expectNotStale('data.gql.dart');
        expect(
          generated('data.gql.dart').readAsStringSync(),
          allOf(
            contains('String get revisionSeq'),
            isNot(contains('int get revisionSeq')),
          ),
        );
      },
    );

    test(
      'refreshes every operation output under a filter on the .graphql source',
      () async {
        // Which type the earlier control test left behind depends on test
        // order, so the precondition below checks staleness explicitly.
        makeOperationOutputsStaleBySchemaChange('Boolean');
        final staleData = generated('data.gql.dart').readAsStringSync();
        expect(
          staleData,
          isNot(contains('bool get revisionSeq')),
          reason: 'precondition: the data output must be stale',
        );
        expect(staleData, contains(staleMarker));

        final output = await buildRunner([
          '--build-filter=$operationDir/$operationName.graphql',
        ]);

        expect(
          output,
          isNot(contains('wrote 0 outputs')),
          reason: 'build_runner skipped the operation builder entirely',
        );

        // Every graphql_builder output was rewritten, AST included ...
        for (final extension in staleOutputs) {
          expectNotStale(extension);
        }
        final afterFilteredBuild = snapshotOperationOutputs();
        expect(
          afterFilteredBuild['ast.gql.dart'],
          contains('BeaconFactCardList'),
        );
        // ... and the schema-dependent ones reflect the changed type.
        expect(
          afterFilteredBuild['data.gql.dart'],
          allOf(
            contains('bool get revisionSeq'),
            isNot(contains('int get revisionSeq')),
          ),
          reason: '$operationName.data.gql.dart is stale vs schema.graphql',
        );
        expect(
          afterFilteredBuild['data.gql.g.dart'],
          matches(RegExp(r"case 'revisionSeq':[^;]*?FullType\(bool\)")),
          reason: '$operationName.data.gql.g.dart is stale vs schema.graphql',
        );

        // Cross-check: nothing is left for an unfiltered build to change.
        await buildRunner([]);
        final afterFullBuild = snapshotOperationOutputs();
        for (final extension in generatedExtensions) {
          expect(
            afterFilteredBuild[extension],
            afterFullBuild[extension],
            reason: '$operationName.$extension was not current after the '
                'filtered build',
          );
        }
      },
    );
  });
}
