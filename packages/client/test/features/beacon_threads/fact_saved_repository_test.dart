// A reader's saved facts through the real BeaconFactCardRepository over the
// real RemoteApiService and Ferry link chain; only HTTP is stubbed. Pins the
// operations and variables on the wire, the savedByMe mapping of the fact
// list, the saved list mapping, and the typed error for the saved-fact limit.
// Methods the repository must expose are invoked through `dynamic` so each
// test fails on its own assertion.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_card_exceptions.dart';

typedef _Sent = ({
  String operationName,
  String query,
  Map<String, dynamic> variables,
});

Map<String, dynamic> _factRow(String id, {required bool savedByMe}) => {
  '__typename': 'v2_BeaconFactCardRow',
  'id': id,
  'beaconId': 'B1',
  'factText': 'Meet at 10:00',
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
  'originBeaconKind': null,
  'savedByMe': savedByMe,
};

Map<String, dynamic> _savedRow(String id) => {
  '__typename': 'v2_BeaconFactCardSavedRow',
  'factCardId': id,
  'available': true,
  'beaconId': 'B1',
  'beaconKind': 0,
  'factText': 'Saved text $id',
  'attachmentsJson': '[]',
};

/// Runs [body] against the real repository; [responses] maps an operation
/// name to its `data`; [errorCodes] maps an operation name to a GraphQL
/// error code the server answers with instead.
Future<List<_Sent>> _withRepository(
  Map<String, Object> responses,
  Future<void> Function(BeaconFactCardRepository repository) body, {
  Map<String, int> errorCodes = const {},
}) async {
  final sent = <_Sent>[];
  await http.runWithClient(
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
      http.Response json(Object b) => http.Response(
        jsonEncode(b),
        200,
        headers: {'content-type': 'application/json'},
      );
      if (request.url.path.endsWith('/session/access-token')) {
        return json({
          'subject': 'Uviewer000001',
          'access_token': 'test-token',
          'expires_in': 3600,
        });
      }
      final b = jsonDecode(request.body) as Map<String, dynamic>;
      final name = b['operationName'] as String;
      sent.add((
        operationName: name,
        query: b['query'] as String,
        variables: (b['variables'] as Map).cast<String, dynamic>(),
      ));
      final code = errorCodes[name];
      if (code != null) {
        return json({
          'data': null,
          'errors': [
            {
              'message': 'server error',
              'extensions': {'code': code},
            },
          ],
        });
      }
      return json({'data': responses[name]});
    }),
  );
  return sent;
}

void main() {
  group('fact list', () {
    test('maps savedByMe true and false from the GraphQL row', () async {
      final sent = await _withRepository(
        {
          'BeaconFactCardList': {
            '__typename': 'query_root',
            'BeaconFactCardList': [
              _factRow('Fsaved', savedByMe: true),
              _factRow('Fplain', savedByMe: false),
            ],
          },
        },
        (repository) async {
          final facts = await repository.list(beaconId: 'B1');
          final byId = {for (final f in facts) f.id: f};
          expect((byId['Fsaved']! as dynamic).savedByMe, isTrue);
          expect((byId['Fplain']! as dynamic).savedByMe, isFalse);
        },
      );
      expect(sent.single.operationName, 'BeaconFactCardList');
      expect(sent.single.query, contains(RegExp(r'\bsavedByMe\b')));
    });
  });

  group('save', () {
    test('sends BeaconFactCardSave with beaconId and factCardId and '
        'completes, also when repeated (idempotent)', () async {
      final sent = await _withRepository(
        {
          'BeaconFactCardSave': {
            '__typename': 'mutation_root',
            'BeaconFactCardSave': true,
          },
        },
        (repository) async {
          await (repository as dynamic).save(
            beaconId: 'B1',
            factCardId: 'F1',
          );
          await (repository as dynamic).save(
            beaconId: 'B1',
            factCardId: 'F1',
          );
        },
      );
      expect(sent.map((s) => s.operationName), [
        'BeaconFactCardSave',
        'BeaconFactCardSave',
      ]);
      expect(sent.map((s) => s.variables), [
        {'beaconId': 'B1', 'factCardId': 'F1'},
        {'beaconId': 'B1', 'factCardId': 'F1'},
      ]);
    });

    test('the saved-fact limit error (1353) surfaces as a typed fact-card '
        'exception', () async {
      Object? caught;
      await _withRepository(
        const {},
        (repository) async {
          try {
            await (repository as dynamic).save(
              beaconId: 'B1',
              factCardId: 'F1',
            );
          } on Object catch (e) {
            caught = e;
          }
        },
        errorCodes: {'BeaconFactCardSave': 1353},
      );
      expect(caught, isA<BeaconFactCardException>());
      Object? mapped;
      try {
        throwIfBeaconFactCardError(1353, null);
      } on Object catch (e) {
        mapped = e;
      }
      expect(caught.runtimeType, mapped.runtimeType);
    });
  });

  group('unsave', () {
    test('sends BeaconFactCardUnsave with only factCardId and completes, '
        'also for a fact that was not saved', () async {
      final sent = await _withRepository(
        {
          'BeaconFactCardUnsave': {
            '__typename': 'mutation_root',
            'BeaconFactCardUnsave': true,
          },
        },
        (repository) async {
          await (repository as dynamic).unsave(factCardId: 'F1');
          await (repository as dynamic).unsave(factCardId: 'F1');
        },
      );
      expect(sent.map((s) => s.operationName), [
        'BeaconFactCardUnsave',
        'BeaconFactCardUnsave',
      ]);
      expect(sent.map((s) => s.variables), [
        {'factCardId': 'F1'},
        {'factCardId': 'F1'},
      ]);
    });
  });

  group('saved list', () {
    test('BeaconFactCardSavedList maps rows in server order on the existing '
        'repository', () async {
      final sent = await _withRepository(
        {
          'BeaconFactCardSavedList': {
            '__typename': 'query_root',
            'BeaconFactCardSavedList': [_savedRow('Fb'), _savedRow('Fa')],
          },
        },
        (repository) async {
          final rows = await (repository as dynamic).savedList() as List;
          expect(rows.map((r) => (r as dynamic).factCardId), ['Fb', 'Fa']);
        },
      );
      expect(sent.single.operationName, 'BeaconFactCardSavedList');
    });
  });

  group('saved-fact limit error mapping', () {
    test('code 1353 throws a new typed exception under the sealed '
        'BeaconFactCardException; 1352 keeps its mapping', () {
      Object? limit;
      try {
        throwIfBeaconFactCardError(1353, null);
      } on Object catch (e) {
        limit = e;
      }
      expect(limit, isA<BeaconFactCardException>());
      expect(limit, isNot(isA<BeaconFactCopySourceUnavailableException>()));
      expect(limit, isNot(isA<BeaconFactRemovedException>()));
      expect(limit, isNot(isA<BeaconFactRateLimitedException>()));
      expect(limit, isNot(isA<BeaconFactEditConflictException>()));

      expect(
        () => throwIfBeaconFactCardError(1352, null),
        throwsA(isA<BeaconFactCopySourceUnavailableException>()),
      );
    });
  });
}
