// Issue #181 plan §8.11 / §14.2 (tentura-617.23): the fact GraphQL
// documents, their Ferry codegen and V2 routing. `beacon_fact_card_repository
// _test.dart` covers the runtime mapping; this file guards the acceptance
// criterion "build_runner succeeds": every fact document has up-to-date
// generated output (compared by content, not mtime, so a failed or skipped
// `dart run build_runner build -d` after a .graphql or schema edit is caught)
// with the variables the operations need.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/build_client.dart';

import '../../support/gql_codegen_freshness.dart';

const _gqlDir = 'lib/features/beacon_threads/data/gql';
const _schemaPath = 'lib/data/gql/schema.graphql';

const _factDocuments = [
  'beacon_fact_card_list',
  'beacon_fact_card_pin',
  'beacon_fact_card_correct',
  'beacon_fact_card_restore',
  'beacon_fact_card_remove',
  'beacon_fact_card_set_visibility',
  'beacon_fact_card_revisions',
];

/// Strips `#` comments so a commented-out field does not count.
String _document(String name) {
  final file = File('$_gqlDir/$name.graphql');
  expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
  return file
      .readAsStringSync()
      .split('\n')
      .map((l) => l.split('#').first)
      .join('\n');
}

/// Whitespace-insensitive variable declaration, e.g. `$fromSeq: Int!`.
Matcher _declaresVar(String name, String type) => contains(
  RegExp('\\\$$name\\s*:\\s*${RegExp.escape(type)}(?![!\\w])'),
);

/// Argument passed through to the root field, e.g. `fromSeq: $fromSeq`.
Matcher _passesArg(String name) =>
    contains(RegExp('\\b$name\\s*:\\s*\\\$$name\\b'));

Matcher _selects(String field) => contains(RegExp('\\b$field\\b'));

void main() {
  group('documents', () {
    test('BeaconFactCardList selects the provenance fields', () {
      final doc = _document('beacon_fact_card_list');
      for (final field in const [
        'revisionSeq',
        'lastEditedBy',
        'lastEditedByTitle',
        'lastEditedAt',
        'otherEditorCount',
        'historyTruncated',
      ]) {
        expect(doc, _selects(field), reason: field);
      }
    });

    test('BeaconFactCardCorrect declares and passes baseRevisionSeq', () {
      final doc = _document('beacon_fact_card_correct');
      expect(doc, contains('mutation BeaconFactCardCorrect('));
      expect(doc, _declaresVar('baseRevisionSeq', 'Int!'));
      expect(doc, _passesArg('baseRevisionSeq'));
    });

    test('BeaconFactCardRestore declares and passes fromSeq + '
        'baseRevisionSeq', () {
      final doc = _document('beacon_fact_card_restore');
      expect(doc, contains('mutation BeaconFactCardRestore('));
      for (final (name, type) in const [
        ('beaconId', 'String!'),
        ('factCardId', 'String!'),
        ('fromSeq', 'Int!'),
        ('baseRevisionSeq', 'Int!'),
      ]) {
        expect(doc, _declaresVar(name, type), reason: name);
        expect(doc, _passesArg(name), reason: name);
      }
    });

    test('BeaconFactCardRevisions takes (beaconId, factCardId, before) and '
        'selects entries + nextCursor', () {
      final doc = _document('beacon_fact_card_revisions');
      expect(doc, contains('query BeaconFactCardRevisions('));
      for (final (name, type) in const [
        ('beaconId', 'String!'),
        ('factCardId', 'String!'),
        ('before', 'String'),
      ]) {
        expect(doc, _declaresVar(name, type), reason: name);
        expect(doc, _passesArg(name), reason: name);
      }
      expect(doc, _selects('entries'));
      expect(doc, _selects('nextCursor'));
    });
  });

  group('codegen (build_runner)', () {
    test('every fact document has generated output matching the document '
        'and schema.graphql', () {
      expect(
        findStaleGqlCodegen(
          gqlDir: Directory(_gqlDir),
          schema: File(_schemaPath),
          documents: _factDocuments,
        ),
        isEmpty,
        reason: 'stale generated output: run build_runner',
      );
    });

    test('generated vars carry baseRevisionSeq / fromSeq / before', () {
      String vars(String name) =>
          File('$_gqlDir/_g/$name.var.gql.dart').readAsStringSync();

      expect(vars('beacon_fact_card_correct'), contains('baseRevisionSeq'));
      expect(vars('beacon_fact_card_restore'), contains('fromSeq'));
      expect(vars('beacon_fact_card_restore'), contains('baseRevisionSeq'));
      expect(vars('beacon_fact_card_revisions'), contains('before'));
    });
  });

  group('routing', () {
    test('BeaconFactCardRestore and BeaconFactCardRevisions go straight to '
        'Tentura V2', () {
      expect(isTenturaDirectOperation('BeaconFactCardRestore'), isTrue);
      expect(isTenturaDirectOperation('BeaconFactCardRevisions'), isTrue);
      expect(isTenturaDirectOperation('BeaconFactCardCorrect'), isTrue);
      expect(isTenturaDirectOperation('BeaconFactCardList'), isTrue);
    });
  });
}
