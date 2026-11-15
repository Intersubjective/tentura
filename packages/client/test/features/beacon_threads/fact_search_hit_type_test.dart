// The typed contract of fact search: `search` returns
// `List<BeaconFactSearchHit>` (a public typedef of the repository file) whose
// six fields are non-null String/int/bool, and BeaconThreadsCase passes the
// same typed list through. Real repository over real RemoteApiService, only
// HTTP stubbed.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';

import '../../support/test_realtime_sync.dart';

class _FakeThreadsRepository extends Fake implements BeaconThreadsRepository {}

class _FakeHints extends Fake implements BeaconRoomHintsRepository {}

class _FakePolling extends Fake implements PollingRepository {}

Future<void> _run(
  Future<void> Function(BeaconFactCardRepository repo, BeaconThreadsCase c)
  body,
) => http.runWithClient(
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
    return json({
      'data': {
        '__typename': 'query_root',
        'BeaconFactCardSearch': [
          {
            '__typename': 'v2_BeaconFactCardSearchRow',
            'factCardId': 'F1',
            'beaconId': 'B1',
            'beaconKind': 1,
            'factText': 'Meet at 10:00',
            'attachmentsJson': '[{"id":"a1"}]',
            'saved': true,
          },
        ],
      },
    });
  }),
);

void main() {
  group('fact search typed result', () {
    test('repository.search returns List<BeaconFactSearchHit> with '
        'non-null String/int/bool fields', () async {
      await _run((repo, _) async {
        final hits = await repo.search(
          query: 'meet',
          excludeBeaconId: 'B9',
        );
        expect(hits, isA<List<BeaconFactSearchHit>>());
        expect(hits, hasLength(1));
        final id = hits.single.factCardId;
        final beaconId = hits.single.beaconId;
        final kind = hits.single.beaconKind;
        final text = hits.single.factText;
        final attachments = hits.single.attachmentsJson;
        final saved = hits.single.saved;
        expect(id, isA<String>());
        expect(kind, isA<int>());
        expect(saved, isA<bool>());
        expect(
          [id, beaconId, kind, text, attachments, saved],
          ['F1', 'B1', 1, 'Meet at 10:00', '[{"id":"a1"}]', true],
        );
      });
    });
  });

  group('BeaconThreadsCase.searchAvailableFacts delegation', () {
    test('calls repository.search once with both arguments and returns the '
        'very same list, unmodified', () async {
      final hits = List<BeaconFactSearchHit>.unmodifiable([
        (
          factCardId: 'F1',
          beaconId: 'B1',
          beaconKind: 0,
          factText: 'Meet at 10:00',
          attachmentsJson: '[]',
          saved: true,
        ),
        (
          factCardId: 'F2',
          beaconId: 'B2',
          beaconKind: 1,
          factText: 'Meet in the park',
          attachmentsJson: '[{"id":"a1"}]',
          saved: false,
        ),
      ]);
      final snapshot = List<BeaconFactSearchHit>.of(hits);
      final repo = _RecordingRepository(hits);
      await _withCase(repo, (case_) async {
        final result = await case_.searchAvailableFacts(
          query: 'meet',
          excludeBeaconId: 'B9',
        );
        expect(identical(result, hits), isTrue);
        expect(result, snapshot);
      });
      expect(repo.calls, [
        {'query': 'meet', 'excludeBeaconId': 'B9'},
      ]);
    });

    test('without excludeBeaconId calls repository.search with null', () async {
      final repo = _RecordingRepository(const []);
      await _withCase(repo, (case_) async {
        final result = await case_.searchAvailableFacts(query: 'meet');
        expect(result, isEmpty);
      });
      expect(repo.calls, [
        {'query': 'meet', 'excludeBeaconId': null},
      ]);
    });
  });
}

class _RecordingRepository extends Fake implements BeaconFactCardRepository {
  _RecordingRepository(this._hits);

  final List<BeaconFactSearchHit> _hits;
  final calls = <Map<String, Object?>>[];

  @override
  Future<List<BeaconFactSearchHit>> search({
    required String query,
    String? excludeBeaconId,
  }) async {
    calls.add({'query': query, 'excludeBeaconId': excludeBeaconId});
    return _hits;
  }
}

Future<void> _withCase(
  BeaconFactCardRepository repo,
  Future<void> Function(BeaconThreadsCase case_) body,
) async {
  final watermark = RoomReadWatermarkStore.testing();
  try {
    await body(
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
  }
}
