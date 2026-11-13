// Fact copy / origin / destinations on the real `BeaconFactCardRepository`
// over the real `RemoteApiService` and Ferry link chain; only HTTP is
// stubbed. New repository members are called through `dynamic` so each test
// fails on its own (missing behaviour) instead of the file not compiling.

// Dynamic calls: the new members are invoked before they exist.
// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_card_exceptions.dart';

const _beaconId = 'Bfactcopy0001';
const _factCardId = 'Ffactcopy0001';

typedef _Sent = ({
  Uri url,
  String operationName,
  Map<String, dynamic> variables,
});

/// [errorCodes] answers the named operation with a GraphQL error carrying
/// that `extensions.code`.
Future<void> _withRepository(
  Map<String, Object> responses,
  List<_Sent> sent,
  Future<void> Function(BeaconFactCardRepository repository) body, {
  Map<String, int> errorCodes = const {},
}) => http.runWithClient(
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
      variables: (json['variables'] as Map).cast<String, dynamic>(),
    ));
    final code = errorCodes[name];
    if (code != null) {
      return http.Response(
        jsonEncode({
          'data': null,
          'errors': [
            {
              'message': 'failed',
              'extensions': {'code': code},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    final data = responses[name];
    if (data == null) {
      return http.Response('{"errors":[{"message":"unexpected $name"}]}', 200);
    }
    return http.Response(
      jsonEncode({'data': data}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

Map<String, dynamic> _factRow({Object? originBeaconKind = 'absent'}) => {
  '__typename': 'v2_BeaconFactCardRow',
  'id': _factCardId,
  'beaconId': _beaconId,
  'factText': 'Key is under the mat',
  'visibility': BeaconFactCardVisibilityBits.public,
  'pinnedBy': 'Upinner000001',
  'pinnedByTitle': 'Pinner',
  'sourceMessageId': null,
  'status': BeaconFactCardStatusBits.active,
  'createdAt': '2026-09-01T08:00:00.000Z',
  'updatedAt': null,
  'attachmentsJson': '[]',
  'revisionSeq': 1,
  'lastEditedBy': null,
  'lastEditedByTitle': null,
  'lastEditedAt': null,
  'otherEditorCount': 0,
  'historyTruncated': false,
  if (originBeaconKind != 'absent') 'originBeaconKind': originBeaconKind,
};

Future<List<dynamic>> _list(Map<String, dynamic> row) async {
  late List<dynamic> facts;
  await _withRepository(
    {
      'BeaconFactCardList': {
        '__typename': 'query_root',
        'BeaconFactCardList': [row],
      },
    },
    [],
    (repository) async => facts = await repository.list(beaconId: _beaconId),
  );
  return facts;
}

Map<String, dynamic> _revisionRow({required int seq, required int kind}) => {
  '__typename': 'v2_BeaconFactHistoryEntryRow',
  'entry': 'revision',
  'entryKey': 'r${seq.toString().padLeft(10, '0')}',
  'id': null,
  'seq': seq,
  'kind': kind,
  'type': null,
  'factText': 'Key is under the mat',
  'restoredFromSeq': kind == 2 ? 1 : null,
  'visibilityFrom': null,
  'visibilityTo': null,
  'actorId': 'Uactor0000001',
  'actorTitle': 'Actor',
  'createdAt': '2026-09-02T09:30:00.000Z',
};

void main() {
  group('list originBeaconKind', () {
    test('maps kind 0 and kind 1 through', () async {
      for (final kind in [0, 1]) {
        final facts = await _list(_factRow(originBeaconKind: kind));
        expect((facts.single as dynamic).originBeaconKind, kind);
      }
    });

    test('is null when the server sends null or omits the field', () async {
      expect(
        ((await _list(_factRow(originBeaconKind: null))).single as dynamic)
            .originBeaconKind,
        isNull,
      );
      expect(
        ((await _list(_factRow())).single as dynamic).originBeaconKind,
        isNull,
      );
    });
  });

  group('copy', () {
    Future<(dynamic, List<_Sent>)> copyWith(String wire) async {
      final sent = <_Sent>[];
      late dynamic result;
      await _withRepository(
        {
          'BeaconFactCardCopy': {
            '__typename': 'mutation_root',
            'BeaconFactCardCopy': {
              '__typename': 'v2_BeaconFactCardCopyResult',
              'factCardId': 'Fnew00000001',
              'outcome': wire,
            },
          },
        },
        sent,
        (repository) async {
          final dynamic repo = repository;
          result = await repo.copy(
            sourceFactCardId: _factCardId,
            destinationBeaconId: 'Bdest00000001',
          );
        },
      );
      return (result, sent);
    }

    test('returns the id and a typed outcome that tells created from '
        'alreadyThere; sends exact variables to V2', () async {
      final (created, sent) = await copyWith('created');
      final (created2, _) = await copyWith('created');
      final (there, _) = await copyWith('alreadyThere');

      expect(created.factCardId, 'Fnew00000001');
      expect(there.factCardId, 'Fnew00000001');
      expect(created.outcome, isNotNull);
      expect(created.outcome, isNot(isA<String>()));
      expect(created.outcome, created2.outcome);
      expect(created.outcome, isNot(there.outcome));

      final op = sent.single;
      expect(op.operationName, 'BeaconFactCardCopy');
      expect(op.url.path, '/api/v2/graphql');
      expect(op.variables, {
        'sourceFactCardId': _factCardId,
        'destinationBeaconId': 'Bdest00000001',
      });
    });
  });

  group('origin', () {
    test('maps an available origin with all seven values', () async {
      final sent = <_Sent>[];
      late dynamic r;
      await _withRepository(
        {
          'BeaconFactCardOrigin': {
            '__typename': 'query_root',
            'BeaconFactCardOrigin': {
              '__typename': 'v2_BeaconFactCardOriginResult',
              'available': true,
              'beaconId': 'B1',
              'factCardId': 'F1',
              'beaconKind': 0,
              'changedSinceCopy': true,
              'canSeeCopiedRevision': true,
              'copiedRevisionSeq': 3,
            },
          },
        },
        sent,
        (repository) async {
          final dynamic repo = repository;
          r = await repo.origin(beaconId: _beaconId, factCardId: _factCardId);
        },
      );
      expect(r.available, isTrue);
      expect(r.beaconId, 'B1');
      expect(r.factCardId, 'F1');
      expect(r.beaconKind, 0);
      expect(r.changedSinceCopy, isTrue);
      expect(r.canSeeCopiedRevision, isTrue);
      expect(r.copiedRevisionSeq, 3);
      expect(sent.single.operationName, 'BeaconFactCardOrigin');
      expect(sent.single.url.path, '/api/v2/graphql');
      expect(sent.single.variables, {
        'beaconId': _beaconId,
        'factCardId': _factCardId,
      });
    });

    test('maps an unavailable origin without throwing', () async {
      late dynamic r;
      await _withRepository(
        {
          'BeaconFactCardOrigin': {
            '__typename': 'query_root',
            'BeaconFactCardOrigin': {
              '__typename': 'v2_BeaconFactCardOriginResult',
              'available': false,
              'beaconId': null,
              'factCardId': null,
              'beaconKind': null,
              'changedSinceCopy': null,
              'canSeeCopiedRevision': null,
              'copiedRevisionSeq': null,
            },
          },
        },
        [],
        (repository) async {
          final dynamic repo = repository;
          r = await repo.origin(beaconId: _beaconId, factCardId: _factCardId);
        },
      );
      expect(r.available, isFalse);
      expect(r.beaconId, isNull);
      expect(r.factCardId, isNull);
      expect(r.beaconKind, isNull);
      expect(r.changedSinceCopy, isNull);
      expect(r.canSeeCopiedRevision, isNull);
      expect(r.copiedRevisionSeq, isNull);
    });
  });

  group('destinations', () {
    test('maps rows in server order with parsed expiresAt', () async {
      final sent = <_Sent>[];
      late List<dynamic> rows;
      await _withRepository(
        {
          'BeaconFactCopyDestinations': {
            '__typename': 'query_root',
            'BeaconFactCopyDestinations': [
              {
                '__typename': 'v2_BeaconFactCopyDestinationRow',
                'id': 'Bone',
                'kind': 0,
                'title': 'Garden help',
                'isDraft': false,
                'expiresAt': null,
              },
              {
                '__typename': 'v2_BeaconFactCopyDestinationRow',
                'id': 'Btwo',
                'kind': 1,
                'title': 'A post',
                'isDraft': true,
                'expiresAt': '2026-10-01T12:00:00.000Z',
              },
            ],
          },
        },
        sent,
        (repository) async {
          final dynamic repo = repository;
          rows = List<dynamic>.of(
            await repo.destinations(sourceFactCardId: _factCardId) as List,
          );
        },
      );
      expect(rows, hasLength(2));
      expect(rows[0].id, 'Bone');
      expect(rows[0].kind, 0);
      expect(rows[0].title, 'Garden help');
      expect(rows[0].isDraft, isFalse);
      expect(rows[0].expiresAt, isNull);
      expect(rows[1].id, 'Btwo');
      expect(rows[1].kind, 1);
      expect(rows[1].isDraft, isTrue);
      expect(rows[1].expiresAt, DateTime.utc(2026, 10, 1, 12));
      expect(sent.single.operationName, 'BeaconFactCopyDestinations');
      expect(sent.single.url.path, '/api/v2/graphql');
      expect(sent.single.variables, {'sourceFactCardId': _factCardId});
    });

    for (final (label, answer) in <(String, List<Object?>?)>[
      ('null', null),
      ('empty', <Object?>[]),
    ]) {
      test('a $label list answer gives an empty list', () async {
        late dynamic rows;
        await _withRepository(
          {
            'BeaconFactCopyDestinations': {
              '__typename': 'query_root',
              'BeaconFactCopyDestinations': answer,
            },
          },
          [],
          (repository) async {
            final dynamic repo = repository;
            rows = await repo.destinations(sourceFactCardId: _factCardId);
          },
        );
        expect(rows, isA<List<dynamic>>());
        expect(rows, isEmpty);
      });
    }
  });

  group('source unavailable error 1352', () {
    // The class name is not fixed; it must be a BeaconFactCardException that
    // none of the existing subclasses is, and all three operations agree.
    final seen = <Type>{};
    Matcher typed() => isA<BeaconFactCardException>()
        .having((e) => e is BeaconFactEditConflictException, 'conflict', false)
        .having((e) => e is BeaconFactRemovedException, 'removed', false)
        .having((e) => e is BeaconFactRateLimitedException, 'limited', false);

    Future<void> run(
      String operation,
      Future<void> Function(dynamic repo) call,
    ) async {
      await _withRepository(
        const {},
        [],
        (repository) async {
          Object? thrown;
          try {
            await call(repository as dynamic);
          } on Object catch (e) {
            thrown = e;
          }
          expect(thrown, typed());
          seen.add(thrown.runtimeType);
          expect(seen, hasLength(1), reason: 'same class for every operation');
        },
        errorCodes: {operation: 1352},
      );
    }

    test('copy throws the typed exception', () {
      return run(
        'BeaconFactCardCopy',
        (repo) => repo.copy(
          sourceFactCardId: _factCardId,
          destinationBeaconId: 'Bdest00000001',
        ) as Future<void>,
      );
    });

    test('origin throws the typed exception', () {
      return run(
        'BeaconFactCardOrigin',
        (repo) => repo.origin(beaconId: _beaconId, factCardId: _factCardId)
            as Future<void>,
      );
    });

    test('destinations throws the typed exception', () {
      return run(
        'BeaconFactCopyDestinations',
        (repo) => repo.destinations(sourceFactCardId: _factCardId)
            as Future<void>,
      );
    });
  });

  group('revisions copied kind', () {
    test('kind 4 maps to a copied entry, not created; 0-3 unchanged', () async {
      late BeaconFactHistoryPage page;
      await _withRepository(
        {
          'BeaconFactCardRevisions': {
            '__typename': 'query_root',
            'BeaconFactCardRevisions': {
              '__typename': 'v2_BeaconFactCardRevisionsPage',
              'entries': [
                for (var k = 0; k <= 4; k++) _revisionRow(seq: k + 1, kind: k),
              ],
              'nextCursor': null,
            },
          },
        },
        [],
        (repository) async => page = await repository.revisions(
          beaconId: _beaconId,
          factCardId: _factCardId,
        ),
      );
      final e = page.entries;
      expect(e[0], isA<BeaconFactHistoryCreated>());
      expect(e[1], isA<BeaconFactHistoryEdited>());
      expect(e[2], isA<BeaconFactHistoryRestored>());
      expect(e[3], isA<BeaconFactHistoryImported>());
      final copied = e[4];
      expect(copied, isNot(isA<BeaconFactHistoryCreated>()));
      expect(copied, isNot(isA<BeaconFactHistoryEdited>()));
      expect(copied, isNot(isA<BeaconFactHistoryRestored>()));
      expect(copied, isNot(isA<BeaconFactHistoryImported>()));
      expect(
        {for (final x in e.take(4)) x.runtimeType}.contains(copied.runtimeType),
        isFalse,
        reason: 'copied is its own subclass',
      );
      final dynamic c = copied;
      expect(c.seq, 5);
      expect(c.factText, 'Key is under the mat');
      expect(c.actorId, 'Uactor0000001');
      expect(c.actorTitle, 'Actor');
      expect(c.createdAt, DateTime.utc(2026, 9, 2, 9, 30));
      expect(c.createdAt.isUtc, isTrue);
    });
  });
}
