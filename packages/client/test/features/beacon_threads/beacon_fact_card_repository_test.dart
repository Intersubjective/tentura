// Issue #181 plan §8.11 / §14.2 (tentura-617.23): the real
// `BeaconFactCardRepository` over the real `RemoteApiService` and Ferry link
// chain. Only the HTTP transport is stubbed (via `http.runWithClient`), so
// the test also pins V2 routing (`_tenturaDirectOperationNames`) and the
// exact variables sent.
//
// `correct(baseRevisionSeq)`, `restore` and `revisions` do not exist yet, so
// they are invoked through `dynamic`: each test fails on its own (a
// NoSuchMethodError or an assertion) instead of the file failing to compile.
// The same goes for the history event entry, which the domain has no type
// for yet (plan §14.2: the client union mirrors the server one — revision
// entries plus an event entry, both with `actorTitle`).
//
// `BeaconFactCardRevisions` (plan §8.11): `(beaconId, factCardId, before)` →
// `{entries, nextCursor}`. The server has no GraphQL entry type yet, so each
// fixture entry is a *superset* row: the plan §8.4 history projection
// (`entry`, `entryKey`, one `kind` column for both kinds) plus the server
// entity's names (`type` for events). Ferry ignores keys the client
// document does not select, so any flat selection drawn from those names
// parses. `nextCursor` is opaque and passed back as `before` untouched.

// Dynamic calls reach API the repository and domain do not declare yet.
// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';

const _beaconId = 'Bfacthistory1';
const _factCardId = 'Ffacthistory1';

/// A GraphQL request as it went over the wire.
typedef _SentOperation = ({
  Uri url,
  String operationName,
  String query,
  Map<String, dynamic> variables,
});

/// Runs [body] against a real, session-authenticated [RemoteApiService]
/// whose HTTP transport answers GraphQL operations from [responses] (keyed by
/// operation name; a list is served one element per call) and records them
/// in [sent].
Future<void> _withRepository(
  Map<String, Object> responses,
  List<_SentOperation> sent,
  Future<void> Function(BeaconFactCardRepository repository) body,
) {
  final served = <String, int>{};
  return http.runWithClient(
    () async {
      final remote = RemoteApiService(
        const Env(),
        const WebSocketClientRealtimeSocketFactory(),
      );
      try {
        await remote.setSessionAuth();
        await body(BeaconFactCardRepository(remote));
      } finally {
        await remote.close();
      }
    },
    () => MockClient((request) async {
      if (request.url.path.endsWith('/session/access-token')) {
        return http.Response(
          jsonEncode({
            'subject': 'Ueditor000001',
            'access_token': 'test-token',
            'expires_in': 3600,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final json = jsonDecode(request.body) as Map<String, dynamic>;
      final name = json['operationName'] as String;
      sent.add((
        url: request.url,
        operationName: name,
        query: json['query'] as String,
        variables: (json['variables'] as Map).cast<String, dynamic>(),
      ));
      final configured = responses[name];
      final index = served.update(name, (i) => i + 1, ifAbsent: () => 0);
      final data = configured is List ? configured[index] : configured;
      if (data == null) {
        return http.Response(
          '{"errors":[{"message":"unexpected $name"}]}',
          200,
        );
      }
      return http.Response(
        jsonEncode({'data': data}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

Map<String, dynamic> _factRow({
  required String id,
  required int revisionSeq,
  required int otherEditorCount,
  required bool historyTruncated,
  String? lastEditedBy,
  String? lastEditedByTitle,
  String? lastEditedAt,
}) => {
  '__typename': 'v2_BeaconFactCardRow',
  'id': id,
  'beaconId': _beaconId,
  'factText': 'Meet at 10:00',
  'visibility': BeaconFactCardVisibilityBits.public,
  'pinnedBy': 'Upinner000001',
  'pinnedByTitle': 'Pinner',
  'sourceMessageId': null,
  'status': BeaconFactCardStatusBits.active,
  'createdAt': '2026-09-01T08:00:00.000Z',
  'updatedAt': null,
  'attachmentsJson': '[]',
  'revisionSeq': revisionSeq,
  'lastEditedBy': lastEditedBy,
  'lastEditedByTitle': lastEditedByTitle,
  'lastEditedAt': lastEditedAt,
  'otherEditorCount': otherEditorCount,
  'historyTruncated': historyTruncated,
};

Map<String, dynamic> _revisionRow({
  required int seq,
  required int kind,
  required String factText,
  required String createdAt,
  String? actorId,
  String actorTitle = '',
  int? restoredFromSeq,
}) => {
  '__typename': 'v2_BeaconFactHistoryEntryRow',
  'entry': 'revision',
  'entryKey': 'r${seq.toString().padLeft(10, '0')}',
  'id': null,
  'seq': seq,
  'kind': kind,
  'type': null,
  'factText': factText,
  'restoredFromSeq': restoredFromSeq,
  'visibilityFrom': null,
  'visibilityTo': null,
  'actorId': actorId,
  'actorTitle': actorTitle,
  'createdAt': createdAt,
};

/// Event rows carry explicit nulls in every revision-only field.
Map<String, dynamic> _eventRow({
  required String eventId,
  required int type,
  required String createdAt,
  String? actorId,
  String actorTitle = '',
  int? visibilityFrom,
  int? visibilityTo,
}) => {
  '__typename': 'v2_BeaconFactHistoryEntryRow',
  'entry': 'event',
  'entryKey': 'e$eventId',
  'id': eventId,
  'seq': null,
  'kind': type,
  'type': type,
  'factText': null,
  'restoredFromSeq': null,
  'visibilityFrom': visibilityFrom,
  'visibilityTo': visibilityTo,
  'actorId': actorId,
  'actorTitle': actorTitle,
  'createdAt': createdAt,
};

Map<String, dynamic> _revisionsPage(
  List<Map<String, dynamic>> entries, {
  String? nextCursor,
}) => {
  '__typename': 'query_root',
  'BeaconFactCardRevisions': {
    '__typename': 'v2_BeaconFactCardRevisionsPage',
    'entries': entries,
    'nextCursor': nextCursor,
  },
};

bool _isRevisionEntry(Object? e) =>
    e is BeaconFactHistoryCreated ||
    e is BeaconFactHistoryEdited ||
    e is BeaconFactHistoryRestored ||
    e is BeaconFactHistoryImported;

/// Reads [name] off [e] dynamically (fields the domain does not have yet).
Object? _get(Object? e, String name) {
  final d = e as dynamic;
  return switch (name) {
    'actorTitle' => d.actorTitle,
    'type' => d.type,
    'visibilityFrom' => d.visibilityFrom,
    'visibilityTo' => d.visibilityTo,
    'id' => d.id,
    'actorId' => d.actorId,
    'createdAt' => d.createdAt,
    _ => throw ArgumentError(name),
  };
}

/// A revision entry of subtype [T] with every mapped field.
Matcher _isRevision<T extends BeaconFactHistoryEntry>({
  required int seq,
  required int kind,
  required String factText,
  required String? actorId,
  required String actorTitle,
  required DateTime createdAt,
  int? restoredFromSeq,
}) {
  var m = isA<T>()
      .having((e) => e.id, 'id', isNotEmpty)
      .having((e) => e.factCardId, 'factCardId', _factCardId)
      .having((e) => e.seq, 'seq', seq)
      .having((e) => e.kind, 'kind', kind)
      .having((e) => e.factText, 'factText', factText)
      .having((e) => e.actorId, 'actorId', actorId)
      .having((e) => e.createdAt, 'createdAt', createdAt)
      .having((e) => e.createdAt.isUtc, 'createdAt.isUtc', isTrue)
      .having((e) => _get(e, 'actorTitle'), 'actorTitle', actorTitle);
  if (restoredFromSeq != null) {
    m = m.having(
      (e) => (e as BeaconFactHistoryRestored).restoredFromSeq,
      'restoredFromSeq',
      restoredFromSeq,
    );
  }
  return m;
}

/// A fact event entry (no domain type yet): not a revision, and every event
/// field mapped, nullable ones included.
Matcher _isEvent({
  required int type,
  required int? visibilityFrom,
  required int? visibilityTo,
  required String? actorId,
  required String actorTitle,
  required DateTime createdAt,
}) => isA<Object>()
    .having(_isRevisionEntry, 'is a revision entry', isFalse)
    .having((e) => _get(e, 'id'), 'id', allOf(isA<String>(), isNotEmpty))
    .having((e) => _get(e, 'type'), 'type', type)
    .having((e) => _get(e, 'visibilityFrom'), 'visibilityFrom', visibilityFrom)
    .having((e) => _get(e, 'visibilityTo'), 'visibilityTo', visibilityTo)
    .having((e) => _get(e, 'actorId'), 'actorId', actorId)
    .having((e) => _get(e, 'actorTitle'), 'actorTitle', actorTitle)
    .having((e) => _get(e, 'createdAt'), 'createdAt', createdAt)
    .having(
      (e) => (_get(e, 'createdAt')! as DateTime).isUtc,
      'createdAt.isUtc',
      isTrue,
    );

void main() {
  group('list', () {
    test('requests and maps revisionSeq, lastEditedBy/Title/At, '
        'otherEditorCount and historyTruncated', () async {
      final sent = <_SentOperation>[];
      await _withRepository(
        {
          'BeaconFactCardList': {
            '__typename': 'query_root',
            'BeaconFactCardList': [
              _factRow(
                id: 'Fedited000001',
                revisionSeq: 3,
                lastEditedBy: 'Ueditor000001',
                lastEditedByTitle: 'Editor',
                lastEditedAt: '2026-09-02T09:30:00.000Z',
                otherEditorCount: 2,
                historyTruncated: true,
              ),
              _factRow(
                id: 'Fpristine0001',
                revisionSeq: 1,
                otherEditorCount: 0,
                historyTruncated: false,
              ),
            ],
          },
        },
        sent,
        (repository) async {
          final facts = await repository.list(beaconId: _beaconId);

          expect(facts, hasLength(2));
          final edited = facts.firstWhere((f) => f.id == 'Fedited000001');
          expect(edited.revisionSeq, 3);
          expect(edited.lastEditedBy, 'Ueditor000001');
          expect(edited.lastEditedByTitle, 'Editor');
          expect(edited.lastEditedAt, DateTime.utc(2026, 9, 2, 9, 30));
          expect(edited.otherEditorCount, 2);
          expect(edited.historyTruncated, isTrue);

          final pristine = facts.firstWhere((f) => f.id == 'Fpristine0001');
          expect(pristine.revisionSeq, 1);
          expect(pristine.lastEditedBy, isNull);
          expect(pristine.lastEditedByTitle, isEmpty);
          expect(pristine.lastEditedAt, isNull);
          expect(pristine.otherEditorCount, 0);
          expect(pristine.historyTruncated, isFalse);
        },
      );

      final query = sent.single.query;
      for (final field in const [
        'revisionSeq',
        'lastEditedBy',
        'lastEditedByTitle',
        'lastEditedAt',
        'otherEditorCount',
        'historyTruncated',
      ]) {
        expect(query, contains(RegExp('\\b$field\\b')), reason: field);
      }
    });
  });

  group('correct', () {
    test('sends baseRevisionSeq to V2 and returns the server seq', () async {
      final sent = <_SentOperation>[];
      Object? newSeq;
      await _withRepository(
        {
          'BeaconFactCardCorrect': {
            '__typename': 'mutation_root',
            'BeaconFactCardCorrect': 3,
          },
        },
        sent,
        (repository) async {
          final dynamic repo = repository;
          newSeq = await repo.correct(
            beaconId: _beaconId,
            factCardId: _factCardId,
            newText: 'Meet at 11:00',
            baseRevisionSeq: 2,
          );
        },
      );

      expect(newSeq, 3);
      final op = sent.single;
      expect(op.operationName, 'BeaconFactCardCorrect');
      expect(op.url.path, '/api/v2/graphql');
      expect(op.variables, {
        'beaconId': _beaconId,
        'factCardId': _factCardId,
        'newText': 'Meet at 11:00',
        'baseRevisionSeq': 2,
      });
    });
  });

  group('restore', () {
    test('sends fromSeq + baseRevisionSeq to V2 and returns the new head '
        'seq', () async {
      final sent = <_SentOperation>[];
      Object? newSeq;
      await _withRepository(
        {
          'BeaconFactCardRestore': {
            '__typename': 'mutation_root',
            'BeaconFactCardRestore': 4,
          },
        },
        sent,
        (repository) async {
          final dynamic repo = repository;
          newSeq = await repo.restore(
            beaconId: _beaconId,
            factCardId: _factCardId,
            fromSeq: 1,
            baseRevisionSeq: 3,
          );
        },
      );

      expect(newSeq, 4);
      final op = sent.single;
      expect(op.operationName, 'BeaconFactCardRestore');
      expect(op.url.path, '/api/v2/graphql');
      expect(op.variables, {
        'beaconId': _beaconId,
        'factCardId': _factCardId,
        'fromSeq': 1,
        'baseRevisionSeq': 3,
      });
    });
  });

  group('revisions', () {
    test('maps revision and event entries (nullable fields included), '
        'nextCursor, and pages with the opaque before cursor', () async {
      final sent = <_SentOperation>[];
      await _withRepository(
        {
          'BeaconFactCardRevisions': [
            _revisionsPage(
              [
                _eventRow(
                  eventId: 'Eremoved00001',
                  type: BeaconActivityEventTypeBits.factRemoved,
                  createdAt: '2026-09-04T10:00:00.000Z',
                ),
                _revisionRow(
                  seq: 3,
                  kind: BeaconFactCardRevisionKindBits.restored,
                  factText: 'Meet at 10:00',
                  restoredFromSeq: 1,
                  actorId: 'Ueditor000001',
                  actorTitle: 'Editor',
                  createdAt: '2026-09-03T10:00:00.000Z',
                ),
                _eventRow(
                  eventId: 'Evis000000001',
                  type: BeaconActivityEventTypeBits.factVisibilityChanged,
                  visibilityFrom: BeaconFactCardVisibilityBits.public,
                  visibilityTo: BeaconFactCardVisibilityBits.room,
                  actorId: 'Upinner000001',
                  actorTitle: 'Pinner',
                  createdAt: '2026-09-02T12:00:00.000Z',
                ),
                _revisionRow(
                  seq: 2,
                  kind: BeaconFactCardRevisionKindBits.edited,
                  factText: 'Meet at 11:00',
                  actorId: 'Ueditor000001',
                  actorTitle: 'Editor',
                  createdAt: '2026-09-02T09:30:00.000Z',
                ),
              ],
              nextCursor: '2026-09-02T09:30:00.000Z|r0000000002',
            ),
            _revisionsPage([
              _eventRow(
                eventId: 'Epinned00001',
                type: BeaconActivityEventTypeBits.factPinned,
                actorId: 'Upinner000001',
                actorTitle: 'Pinner',
                createdAt: '2026-09-01T08:00:00.000Z',
              ),
              _revisionRow(
                seq: 1,
                kind: BeaconFactCardRevisionKindBits.created,
                factText: 'Meet at 10:00',
                actorId: 'Upinner000001',
                actorTitle: 'Pinner',
                createdAt: '2026-09-01T08:00:00.000Z',
              ),
              _revisionRow(
                seq: 0,
                kind: BeaconFactCardRevisionKindBits.imported,
                factText: 'Meet at 9:00',
                createdAt: '2026-08-31T08:00:00.000Z',
              ),
            ]),
          ],
        },
        sent,
        (repository) async {
          final dynamic repo = repository;
          final dynamic first = await repo.revisions(
            beaconId: _beaconId,
            factCardId: _factCardId,
          );

          expect(first.nextCursor, '2026-09-02T09:30:00.000Z|r0000000002');
          final firstEntries = (first.entries as Iterable).toList();
          expect(firstEntries, <Matcher>[
            _isEvent(
              type: BeaconActivityEventTypeBits.factRemoved,
              visibilityFrom: null,
              visibilityTo: null,
              actorId: null,
              actorTitle: '',
              createdAt: DateTime.utc(2026, 9, 4, 10),
            ),
            _isRevision<BeaconFactHistoryRestored>(
              seq: 3,
              kind: BeaconFactCardRevisionKindBits.restored,
              factText: 'Meet at 10:00',
              restoredFromSeq: 1,
              actorId: 'Ueditor000001',
              actorTitle: 'Editor',
              createdAt: DateTime.utc(2026, 9, 3, 10),
            ),
            _isEvent(
              type: BeaconActivityEventTypeBits.factVisibilityChanged,
              visibilityFrom: BeaconFactCardVisibilityBits.public,
              visibilityTo: BeaconFactCardVisibilityBits.room,
              actorId: 'Upinner000001',
              actorTitle: 'Pinner',
              createdAt: DateTime.utc(2026, 9, 2, 12),
            ),
            _isRevision<BeaconFactHistoryEdited>(
              seq: 2,
              kind: BeaconFactCardRevisionKindBits.edited,
              factText: 'Meet at 11:00',
              actorId: 'Ueditor000001',
              actorTitle: 'Editor',
              createdAt: DateTime.utc(2026, 9, 2, 9, 30),
            ),
          ]);

          final dynamic second = await repo.revisions(
            beaconId: _beaconId,
            factCardId: _factCardId,
            before: first.nextCursor,
          );

          expect(second.nextCursor, isNull);
          final secondEntries = (second.entries as Iterable).toList();
          expect(secondEntries, <Matcher>[
            _isEvent(
              type: BeaconActivityEventTypeBits.factPinned,
              visibilityFrom: null,
              visibilityTo: null,
              actorId: 'Upinner000001',
              actorTitle: 'Pinner',
              createdAt: DateTime.utc(2026, 9, 1, 8),
            ),
            _isRevision<BeaconFactHistoryCreated>(
              seq: 1,
              kind: BeaconFactCardRevisionKindBits.created,
              factText: 'Meet at 10:00',
              actorId: 'Upinner000001',
              actorTitle: 'Pinner',
              createdAt: DateTime.utc(2026, 9, 1, 8),
            ),
            _isRevision<BeaconFactHistoryImported>(
              seq: 0,
              kind: BeaconFactCardRevisionKindBits.imported,
              factText: 'Meet at 9:00',
              actorId: null,
              actorTitle: '',
              createdAt: DateTime.utc(2026, 8, 31, 8),
            ),
          ]);

          // Every timeline entry needs a distinct id (list keys in the sheet).
          final ids = [
            ...firstEntries,
            ...secondEntries,
          ].map((e) => _get(e, 'id')).toList();
          expect(ids.toSet(), hasLength(ids.length));
        },
      );

      expect(sent, hasLength(2));
      for (final op in sent) {
        expect(op.operationName, 'BeaconFactCardRevisions');
        expect(op.url.path, '/api/v2/graphql');
        expect(op.variables['beaconId'], _beaconId);
        expect(op.variables['factCardId'], _factCardId);
      }
      expect(sent.first.variables['before'], isNull);
      expect(
        sent.last.variables['before'],
        '2026-09-02T09:30:00.000Z|r0000000002',
      );
    });
  });
}
