// A19: every closure `.graphql` document must be valid against the fetched
// `schema.graphql` (root field, argument names/types, required arguments,
// selected fields), and the schema must carry the Arch §7 contract exactly as
// the server `custom_types.dart` / `mutation_closure.dart` declare it
// (Hasura stitching: `v2_` prefix, alphabetical fields and arguments).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'graphql_contract_support.dart';

const _documents = {
  'closure_state': 'ClosureState',
  'closure_result_for_viewer': 'ClosureResultForViewer',
  'closure_save_outcome': 'ClosureSaveOutcome',
  'closure_save_author_split': 'ClosureSaveAuthorSplit',
  'closure_toggle_support': 'ClosureToggleSupport',
  'closure_done': 'ClosureDone',
  'closure_skip': 'ClosureSkip',
  'closure_set_mark': 'ClosureSetMark',
  'closure_save_story': 'ClosureSaveStory',
  'beacon_close': 'BeaconClose',
  'beacon_close_now': 'BeaconCloseNow',
  'beacon_extend_closure': 'BeaconExtendClosure',
  'beacon_reopen': 'BeaconReopen',
};

/// Root field -> exact stitched signature line.
const _signatures = {
  'closureState': 'closureState(beaconId: String!): v2_ClosureState!',
  'closureResultForViewer':
      'closureResultForViewer(beaconId: String!): v2_ClosureResult',
  'beaconClose': 'beaconClose(beaconId: String!): Boolean!',
  'beaconCloseNow':
      'beaconCloseNow(beaconId: String!, expectedEpoch: Int!): Boolean!',
  'beaconExtendClosure':
      'beaconExtendClosure(beaconId: String!, expectedEpoch: Int!): Boolean!',
  'beaconReopen':
      'beaconReopen(beaconId: String!, expectedEpoch: Int!): Boolean!',
  'closureSaveOutcome':
      'closureSaveOutcome(beaconId: String!, expectedEpoch: Int!, '
      'helperId: String!, outcome: v2_ClosureOutcome): Boolean!',
  'closureSaveAuthorSplit':
      'closureSaveAuthorSplit(beaconId: String!, expectedEpoch: Int!, '
      'split: [v2_ClosureSplitEntryInput!]): Boolean!',
  'closureToggleSupport':
      'closureToggleSupport(beaconId: String!, expectedEpoch: Int!, '
      'on: Boolean!, targetId: String!): v2_ClosureToggleResult!',
  'closureDone': 'closureDone(beaconId: String!, expectedEpoch: Int!): Boolean!',
  'closureSkip': 'closureSkip(beaconId: String!, expectedEpoch: Int!): Boolean!',
  'closureSetMark':
      'closureSetMark(beaconId: String!, expectedEpoch: Int!, on: Boolean!, '
      'targetId: String!): Boolean!',
  'closureSaveStory':
      'closureSaveStory(beaconId: String!, body: String!, '
      'expectedEpoch: Int!): Boolean!',
};

const _types = {
  'v2_ClosureState': [
    'canCloseNow: Boolean',
    'canReopen: Boolean',
    'closesAt: String!',
    'earlyCloseAt: String',
    'epoch: Int!',
    'extensionsUsed: Int',
    'inCalcText: String',
    'members: [v2_ClosureMember!]!',
    'myMarks: [String!]',
    'mySupport: [String!]',
    'outcomes: [v2_ClosureOutcomeEntry!]',
    'role: v2_ClosureRole!',
    'split: [v2_ClosureSplitEntry!]',
    'status: Int!',
    'story: String',
  ],
  'v2_ClosureMember': [
    'avatarId: String',
    'departure: String',
    'displayName: String',
    'helpTypes: [String!]',
    'id: String!',
    'notInRequest: Boolean!',
    'offerText: String',
  ],
  'v2_ClosureOutcomeEntry': ['helperId: String!', 'outcome: v2_ClosureOutcome!'],
  'v2_ClosureSplitEntry': ['helperId: String!', 'pct: Int!'],
  'v2_ClosureResult': [
    'band: v2_ClosureBand!',
    'draftFlag: v2_ClosureDraftFlag!',
    'marks: [String!]',
    'outcome: v2_ClosureOutcome!',
    'story: String',
  ],
  'v2_ClosureToggleResult': ['released: String'],
};

const _enums = {
  'v2_ClosureOutcome': ['done', 'notDone', 'cantJudge'],
  'v2_ClosureBand': ['raised', 'asIfSilent', 'lowered', 'none'],
  'v2_ClosureDraftFlag': ['none', 'notCounted', 'lastEditNotCounted'],
  'v2_ClosureRole': ['author', 'voter', 'member'],
};

void main() {
  late GqlSchema schema;

  setUpAll(() {
    schema = GqlSchema(File('lib/data/gql/schema.graphql').readAsStringSync());
  });

  group('documents validate against the fetched schema', () {
    for (final e in _documents.entries) {
      test('${e.key}.graphql', () {
        final file = File('lib/features/closure/data/gql/${e.key}.graphql');
        expect(file.existsSync(), isTrue, reason: '${e.key}.graphql missing');
        final op = GqlOperation.parse(file.readAsStringSync());
        expect(op.name, e.value);
        expect(schema.validateOperation(op), isEmpty);
      });
    }

    test('mutation documents select a root field per Arch §7', () {
      final roots = {
        for (final e in _documents.entries)
          e.value: GqlOperation.parse(
            File(
              'lib/features/closure/data/gql/${e.key}.graphql',
            ).readAsStringSync(),
          ).rootField,
      };
      expect(roots, {
        'ClosureState': 'closureState',
        'ClosureResultForViewer': 'closureResultForViewer',
        'ClosureSaveOutcome': 'closureSaveOutcome',
        'ClosureSaveAuthorSplit': 'closureSaveAuthorSplit',
        'ClosureToggleSupport': 'closureToggleSupport',
        'ClosureDone': 'closureDone',
        'ClosureSkip': 'closureSkip',
        'ClosureSetMark': 'closureSetMark',
        'ClosureSaveStory': 'closureSaveStory',
        'BeaconClose': 'beaconClose',
        'BeaconCloseNow': 'beaconCloseNow',
        'BeaconExtendClosure': 'beaconExtendClosure',
        'BeaconReopen': 'beaconReopen',
      });
    });

    test('closure_state selects every ClosureState field the UI needs', () {
      final op = GqlOperation.parse(
        File(
          'lib/features/closure/data/gql/closure_state.graphql',
        ).readAsStringSync(),
      );
      final top = op.selection!.map((f) => f.name).toSet();
      expect(top, {
        'epoch',
        'status',
        'role',
        'members',
        'outcomes',
        'split',
        'mySupport',
        'inCalcText',
        'myMarks',
        'closesAt',
        'earlyCloseAt',
        'canCloseNow',
        'canReopen',
        'extensionsUsed',
        'story',
      });
      final members = op.selection!.firstWhere((f) => f.name == 'members');
      expect(members.sub!.map((f) => f.name).toSet(), {
        'id',
        'displayName',
        'avatarId',
        'helpTypes',
        'offerText',
        'notInRequest',
        'departure',
      });
    });

    test('closure_result_for_viewer selects every ClosureResult field', () {
      final op = GqlOperation.parse(
        File(
          'lib/features/closure/data/gql/closure_result_for_viewer.graphql',
        ).readAsStringSync(),
      );
      expect(op.selection!.map((f) => f.name).toSet(), {
        'outcome',
        'band',
        'draftFlag',
        'marks',
        'story',
      });
    });
  });

  group('schema carries the Arch §7 contract', () {
    for (final e in _signatures.entries) {
      test('${e.key} signature', () {
        final root = e.value.contains(': Boolean!') ||
                e.key == 'closureToggleSupport'
            ? 'mutation_root'
            : 'query_root';
        final fields = schema.fields(root)!;
        final def = fields[e.key];
        expect(def, isNotNull, reason: '$root.${e.key} is missing');
        final line = def!.$1 == null
            ? '${e.key}: ${def.$2}'
            : '${e.key}(${def.$1}): ${def.$2}';
        expect(line, e.value);
      });
    }

    for (final e in _types.entries) {
      test('${e.key} fields', () {
        final fields = schema.fields(e.key);
        expect(fields, isNotNull, reason: 'type ${e.key} is missing');
        final lines = fields!.entries
            .map((f) => '${f.key}: ${f.value.$2}')
            .toList()
          ..sort();
        expect(lines, e.value);
      });
    }

    for (final e in _enums.entries) {
      test('${e.key} values', () {
        final start = schema.sdl.indexOf('enum ${e.key} {');
        expect(start, isNonNegative, reason: 'enum ${e.key} is missing');
        final body = schema.sdl.substring(
          start,
          schema.sdl.indexOf('\n}', start),
        );
        final values = body
            .split('\n')
            .skip(1)
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toSet();
        expect(values, e.value.toSet());
      });
    }

    test('v2_ClosureSplitEntryInput', () {
      final start = schema.sdl.indexOf('input v2_ClosureSplitEntryInput {');
      expect(start, isNonNegative);
      final body = schema.sdl.substring(
        start,
        schema.sdl.indexOf('\n}', start),
      );
      expect(body, contains('helperId: String!'));
      expect(body, contains('pct: Int!'));
    });

    test('review-extension contract is gone', () {
      expect(schema.sdl, isNot(contains('beaconExtendReview(')));
    });
  });
}
