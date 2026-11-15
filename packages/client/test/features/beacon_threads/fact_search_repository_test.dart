// Searching facts available to the reader: the real BeaconFactCardRepository
// and BeaconThreadsCase over the real RemoteApiService, only HTTP stubbed.
// Pins the operation and variables on the wire, the six-field hit mapping,
// and the typed errors.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show GraphQLError;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_client/build_client.dart'
    show throwGraphQLErrors;
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_card_exceptions.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';

import '../../support/test_realtime_sync.dart';

class _FakeThreadsRepository extends Fake implements BeaconThreadsRepository {}

class _FakeHints extends Fake implements BeaconRoomHintsRepository {}

class _FakePolling extends Fake implements PollingRepository {}

/// Records `search` calls and throws [thrown].
class _ThrowingRepository extends Fake implements BeaconFactCardRepository {
  _ThrowingRepository(this.thrown);

  final BeaconFactRateLimitedException thrown;
  final calls = <Map<String, Object?>>[];

  @override
  Future<List<BeaconFactSearchHit>> search({
    required String query,
    String? excludeBeaconId,
  }) async {
    calls.add({'query': query, 'excludeBeaconId': excludeBeaconId});
    throw thrown;
  }
}

typedef _Sent = ({
  String operationName,
  String path,
  String query,
  Map<String, dynamic> variables,
});

Map<String, dynamic> _row(
  String id,
  String beaconId,
  int kind,
  String text,
  String attachments, {
  required bool saved,
}) => {
  '__typename': 'v2_BeaconFactCardSearchRow',
  'factCardId': id,
  'beaconId': beaconId,
  'beaconKind': kind,
  'factText': text,
  'attachmentsJson': attachments,
  'saved': saved,
};

Future<List<_Sent>> _run(
  Object? rows,
  Future<void> Function(BeaconFactCardRepository repo, BeaconThreadsCase case_)
  body, {
  int? errorCode,
}) async {
  final sent = <_Sent>[];
  await http.runWithClient(
    () async {
      final remote = RemoteApiService(
        const Env(),
        const WebSocketClientRealtimeSocketFactory(),
      );
      final watermark = RoomReadWatermarkStore.testing();
      try {
        await remote.setSessionAuth();
        final repo = BeaconFactCardRepository(remote);
        await body(
          repo,
          BeaconThreadsCase(
            _FakeThreadsRepository(),
            repo,
            _FakePolling(),
            _FakeHints(),
            watermark,
            buildTestRealtimeSync().case_,
            env: const Env(),
            logger: Logger('test'),
          ),
        );
      } finally {
        await watermark.dispose();
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
        path: request.url.path,
        query: b['query'] as String,
        variables: ((b['variables'] ?? <String, dynamic>{}) as Map)
            .cast<String, dynamic>(),
      ));
      if (errorCode != null) {
        return json({
          'data': null,
          'errors': [
            {
              'message': 'server error',
              'extensions': {'code': errorCode},
            },
          ],
        });
      }
      return json({
        'data': {'__typename': 'query_root', 'BeaconFactCardSearch': rows},
      });
    }),
  );
  return sent;
}

void main() {
  final twoRows = [
    _row('F1', 'B1', 0, 'Meet at 10:00', '[]', saved: true),
    _row('F2', 'B2', 1, 'Meet in the park', '[{"id":"a1"}]', saved: false),
  ];

  group('search request', () {
    test(
      'sends one BeaconFactCardSearch with query and excludeBeaconId',
      () async {
        final sent = await _run(twoRows, (repo, _) async {
          await repo.search(query: 'meet', excludeBeaconId: 'B9');
        });
        expect(sent, hasLength(1));
        expect(sent.single.operationName, 'BeaconFactCardSearch');
        expect(sent.single.path, '/api/v2/graphql');
        expect(sent.single.variables, {
          'query': 'meet',
          'excludeBeaconId': 'B9',
        });
        final q = sent.single.query;
        final open = q.lastIndexOf('{');
        final selection = q.substring(open, q.indexOf('}', open));
        for (final f in [
          'factCardId',
          'beaconId',
          'beaconKind',
          'factText',
          'attachmentsJson',
          'saved',
        ]) {
          expect(RegExp('\\b$f\\b').hasMatch(selection), isTrue, reason: f);
        }
      },
    );

    test('without excludeBeaconId sends only the query', () async {
      final sent = await _run(twoRows, (repo, _) async {
        await repo.search(query: 'meet');
      });
      expect(sent.single.operationName, 'BeaconFactCardSearch');
      expect(sent.single.variables['query'], 'meet');
      expect(sent.single.variables['excludeBeaconId'], isNull);
      expect(
        sent.single.variables.keys.toSet().difference({
          'query',
          'excludeBeaconId',
        }),
        isEmpty,
      );
    });
  });

  group('search result mapping', () {
    test('maps every row to a hit with six fields, in server order', () async {
      late List<BeaconFactSearchHit> hits;
      await _run(twoRows, (repo, _) async {
        hits = await repo.search(query: 'meet');
      });
      expect(hits, hasLength(2));
      final a = hits[0];
      final b = hits[1];
      expect(
        [
          a.factCardId,
          a.beaconId,
          a.beaconKind,
          a.factText,
          a.attachmentsJson,
          a.saved,
        ],
        ['F1', 'B1', 0, 'Meet at 10:00', '[]', true],
      );
      expect(
        [
          b.factCardId,
          b.beaconId,
          b.beaconKind,
          b.factText,
          b.attachmentsJson,
          b.saved,
        ],
        ['F2', 'B2', 1, 'Meet in the park', '[{"id":"a1"}]', false],
      );
    });

    test('an empty answer is an empty list, not an error', () async {
      late List<BeaconFactSearchHit> hits;
      final sent = await _run(const <Object>[], (repo, _) async {
        hits = await repo.search(query: 'zzz');
      });
      expect(sent.single.operationName, 'BeaconFactCardSearch');
      expect(hits, isEmpty);
    });
  });

  group('search errors', () {
    test(
      'rate limit code 1320 throws BeaconFactRateLimitedException',
      () async {
        Object? caught;
        await _run(null, (repo, _) async {
          try {
            await repo.search(query: 'meet');
          } on Object catch (e) {
            caught = e;
          }
        }, errorCode: 1320);
        expect(caught, isA<BeaconFactRateLimitedException>());
      },
    );

    test('a non fact-card error is thrown as a mapped client exception, '
        'not a list', () async {
      Object? caught;
      await _run(null, (repo, _) async {
        try {
          await repo.search(query: 'meet');
          fail('search must throw');
        } on TestFailure {
          rethrow;
        } on Object catch (e) {
          caught = e;
        }
      }, errorCode: 401);
      Object? expected;
      try {
        throwGraphQLErrors([
          const GraphQLError(
            message: 'server error',
            extensions: {'code': 401},
          ),
        ]);
      } on Object catch (e) {
        expected = e;
      }
      expect(caught, isA<Exception>());
      expect(caught, isNot(isA<BeaconFactCardException>()));
      expect(caught.runtimeType, expected.runtimeType);
    });
  });

  group('BeaconThreadsCase.searchAvailableFacts', () {
    test('rethrows the very exception the repository threw', () async {
      const thrown = BeaconFactRateLimitedException(
        'thrown by the repository',
      );
      Object? caught;
      final repo = _ThrowingRepository(thrown);
      final watermark = RoomReadWatermarkStore.testing();
      try {
        final case_ = BeaconThreadsCase(
          _FakeThreadsRepository(),
          repo,
          _FakePolling(),
          _FakeHints(),
          watermark,
          buildTestRealtimeSync().case_,
          env: const Env(),
          logger: Logger('test'),
        );
        try {
          await case_.searchAvailableFacts(
            query: 'meet',
            excludeBeaconId: 'B9',
          );
        } on Object catch (e) {
          caught = e;
        }
      } finally {
        await watermark.dispose();
      }
      expect(repo.calls, [
        {'query': 'meet', 'excludeBeaconId': 'B9'},
      ]);
      expect(caught, same(thrown));
    });
  });
}
