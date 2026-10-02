// tentura-sae: `beacon_fact_card_gql_test.dart` used to decide whether the
// generated `_g/*.gql.dart` output was current by comparing file mtimes.
// build_runner deliberately leaves an output untouched when its content is
// unchanged, and a git checkout does not preserve mtimes, so an unrelated
// `schema.graphql` edit or a fresh clone made it fail on correct output.
//
// The replacement is a content-based check, `findStaleGqlCodegen` in
// `test/support/gql_codegen_freshness.dart`. It compares what the generated
// files say with what the `.graphql` documents and `schema.graphql` say
// (operation/variable/field names and variable types in `*.ast.gql.dart`,
// variable names in `*.var.gql.dart`, the selected fields exposed by
// `*.data.gql.dart`, the operation name in `*.req.gql.dart`, root field +
// arguments against the schema; all four outputs must exist) and returns one problem string per stale or missing output, empty
// when everything is current. These tests pin both directions:
//   * correct output is accepted whatever the mtimes are, and
//   * output that no longer matches the documents/schema is rejected even
//     when its mtime looks fresh.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/gql_codegen_freshness.dart';

const _gqlDir = 'lib/features/beacon_threads/data/gql';
const _schemaPath = 'lib/data/gql/schema.graphql';
const _gqlTestPath =
    'test/features/beacon_threads/beacon_fact_card_gql_test.dart';

const _doc = 'beacon_fact_card_pin';
const _suffixes = ['ast', 'data', 'req', 'var'];

/// Minimal schema that matches `beacon_fact_card_pin.graphql`.
const _matchingSchema = '''
schema {
  query: query_root
  mutation: mutation_root
}

type query_root {
  ping: Boolean
}

type mutation_root {
  BeaconFactCardPin(beaconId: String!, factText: String!, sourceMessageId: String, visibility: Int!): Boolean!
}
''';

class _Fixture {
  _Fixture(this.root)
    : gqlDir = Directory('${root.path}/gql')..createSync(recursive: true),
      schema = File('${root.path}/schema.graphql')
        ..writeAsStringSync(_matchingSchema) {
    Directory('${gqlDir.path}/_g').createSync();
    File(
      '$_gqlDir/$_doc.graphql',
    ).copySync('${gqlDir.path}/$_doc.graphql');
    for (final suffix in _suffixes) {
      File(
        '$_gqlDir/_g/$_doc.$suffix.gql.dart',
      ).copySync('${gqlDir.path}/_g/$_doc.$suffix.gql.dart');
    }
  }

  final Directory root;
  final Directory gqlDir;
  final File schema;

  File get document => File('${gqlDir.path}/$_doc.graphql');

  File generated(String suffix) =>
      File('${gqlDir.path}/_g/$_doc.$suffix.gql.dart');

  List<String> problems() => findStaleGqlCodegen(
    gqlDir: gqlDir,
    schema: schema,
    documents: const [_doc],
  );

  void rewrite(File file, String Function(String) edit) {
    final before = file.readAsStringSync();
    final after = edit(before);
    expect(after, isNot(before), reason: 'fixture edit changed nothing');
    file.writeAsStringSync(after);
  }
}

void main() {
  late _Fixture fx;

  setUp(() {
    fx = _Fixture(Directory.systemTemp.createTempSync('gql_freshness_'));
    addTearDown(() => fx.root.deleteSync(recursive: true));
  });

  group('accepts correct generated output', () {
    test('unchanged documents + generated files + schema are fresh', () {
      expect(fx.problems(), isEmpty);
    });

    test('document and schema newer than the output (no-op build_runner '
        'run, unrelated schema edit)', () {
      final future = DateTime.now().add(const Duration(hours: 1));
      fx.document.setLastModifiedSync(future);
      fx.schema.setLastModifiedSync(future);
      for (final suffix in _suffixes) {
        fx
            .generated(suffix)
            .setLastModifiedSync(DateTime.utc(2020));
      }
      expect(fx.problems(), isEmpty);
    });

    test('an unrelated schema edit does not make the output stale', () {
      fx.schema.writeAsStringSync(
        '${_matchingSchema}type unrelated_type { id: String! }\n',
      );
      expect(fx.problems(), isEmpty);
    });
  });

  group('rejects stale or missing output even when mtimes look fresh', () {
    void freshMtimes() {
      final future = DateTime.now().add(const Duration(hours: 1));
      for (final suffix in _suffixes) {
        fx.generated(suffix).setLastModifiedSync(future);
      }
    }

    test('operation renamed in the document', () {
      fx.rewrite(
        fx.document,
        (s) => s.replaceFirst(
          'mutation BeaconFactCardPin(',
          'mutation BeaconFactCardPinned(',
        ),
      );
      freshMtimes();
      expect(fx.problems(), isNotEmpty);
    });

    test('variable renamed in the document', () {
      fx.rewrite(fx.document, (s) => s.replaceAll(r'$visibility', r'$vis'));
      freshMtimes();
      expect(fx.problems(), isNotEmpty);
    });

    test('variable type changed in the document', () {
      fx.rewrite(
        fx.document,
        (s) => s.replaceFirst(r'$visibility: Int!', r'$visibility: Int'),
      );
      freshMtimes();
      expect(fx.problems(), isNotEmpty);
    });

    test('generated ast no longer matches the document', () {
      fx.rewrite(
        fx.generated('ast'),
        (s) => s.replaceAll("value: 'factText'", "value: 'factTextOld'"),
      );
      freshMtimes();
      final problems = fx.problems();
      expect(problems, isNotEmpty);
      expect(problems.join('\n'), contains(_doc));
    });

    test('generated vars no longer match the document', () {
      fx.rewrite(
        fx.generated('var'),
        (s) => s.replaceAll('factText', 'factTextOld'),
      );
      freshMtimes();
      final problems = fx.problems();
      expect(problems, isNotEmpty);
      expect(problems.join('\n'), contains(_doc));
    });

    test('generated data no longer matches the document', () {
      fx.rewrite(
        fx.generated('data'),
        (s) => s.replaceAll(
          'bool get BeaconFactCardPin;',
          'bool get BeaconFactCardPinOld;',
        ),
      );
      freshMtimes();
      final problems = fx.problems();
      expect(problems, isNotEmpty);
      expect(problems.join('\n'), contains(_doc));
    });

    test('generated req no longer matches the document', () {
      fx.rewrite(
        fx.generated('req'),
        (s) => s.replaceAll(
          "operationName: 'BeaconFactCardPin'",
          "operationName: 'BeaconFactCardPinOld'",
        ),
      );
      freshMtimes();
      final problems = fx.problems();
      expect(problems, isNotEmpty);
      expect(problems.join('\n'), contains(_doc));
    });

    test('schema dropped the root field the document selects', () {
      fx.schema.writeAsStringSync(
        _matchingSchema.replaceFirst('BeaconFactCardPin(', 'BeaconFactCardPut('),
      );
      freshMtimes();
      expect(fx.problems(), isNotEmpty);
    });

    test('schema renamed an argument the document passes', () {
      fx.schema.writeAsStringSync(
        _matchingSchema.replaceFirst('visibility: Int!', 'visible: Int!'),
      );
      freshMtimes();
      expect(fx.problems(), isNotEmpty);
    });

    for (final suffix in _suffixes) {
      test('a missing $suffix output is reported by name', () {
        fx.generated(suffix).deleteSync();
        final problems = fx.problems();
        expect(problems, isNotEmpty);
        expect(problems.join('\n'), contains('$_doc.$suffix.gql.dart'));
      });
    }

    test('a missing document is reported by name', () {
      fx.document.deleteSync();
      final problems = fx.problems();
      expect(problems, isNotEmpty);
      expect(problems.join('\n'), contains(_doc));
    });
  });

  test('beacon_fact_card_gql_test.dart uses the content check, not mtimes '
      '(tentura-sae)', () {
    final source = File(_gqlTestPath).readAsStringSync();
    expect(source, contains('findStaleGqlCodegen'));
    expect(source, isNot(contains('lastModifiedSync')));
  });

  test(
    'beacon_fact_card_gql_test.dart stays green when schema.graphql and a '
    'fact document are newer than the generated output (tentura-sae)',
    () async {
      final schema = File(_schemaPath);
      final document = File('$_gqlDir/$_doc.graphql');
      final schemaModified = schema.lastModifiedSync();
      final documentModified = document.lastModifiedSync();
      addTearDown(() {
        schema.setLastModifiedSync(schemaModified);
        document.setLastModifiedSync(documentModified);
      });

      final future = DateTime.now().add(const Duration(hours: 1));
      schema.setLastModifiedSync(future);
      document.setLastModifiedSync(future);

      final result = await Process.run('flutter', const [
        'test',
        _gqlTestPath,
        '--no-pub',
      ]);

      expect(
        result.exitCode,
        0,
        reason:
            'beacon_fact_card_gql_test.dart failed with newer schema/ '
            'document mtimes:\n${result.stdout}\n${result.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
