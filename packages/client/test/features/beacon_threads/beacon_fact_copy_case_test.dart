// `BeaconThreadsCase` exposes fact copy / origin / destinations and returns
// the repository result unchanged. The real `BeaconFactCardRepository` runs
// over the real `RemoteApiService` with only HTTP stubbed, so result types
// are real, and the stubbed transport proves the case forwards to the
// repository.

// Dynamic calls: the case's new members are invoked before they exist.
// ignore_for_file: avoid_dynamic_calls

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

Future<void> _withCase(
  Map<String, Object> responses,
  List<Map<String, dynamic>> sent,
  Future<void> Function(dynamic case_) body,
) => http.runWithClient(
  () async {
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
    );
    final watermark = RoomReadWatermarkStore.testing();
    try {
      await remote.setSessionAuth();
      await body(
        BeaconThreadsCase(
          _FakeThreadsRepository(),
          BeaconFactCardRepository(remote),
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
    sent.add({
      'op': json['operationName'],
      'vars': (json['variables'] as Map).cast<String, dynamic>(),
    });
    return http.Response(
      jsonEncode({'data': responses[json['operationName']]}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

void main() {
  test(
    'copy goes through the case with the same arguments and result',
    () async {
      final sent = <Map<String, dynamic>>[];
      await _withCase(
        {
          'BeaconFactCardCopy': {
            '__typename': 'mutation_root',
            'BeaconFactCardCopy': {
              '__typename': 'v2_BeaconFactCardCopyResult',
              'factCardId': 'Fnew00000001',
              'outcome': 'alreadyThere',
            },
          },
        },
        sent,
        (c) async {
          final r = await c.copyFact(
            sourceFactCardId: 'F1',
            destinationBeaconId: 'B2',
          );
          expect(r.factCardId, 'Fnew00000001');
          expect(r.outcome.toString(), contains('alreadyThere'));
        },
      );
      expect(sent.single['op'], 'BeaconFactCardCopy');
      expect(sent.single['vars'], {
        'sourceFactCardId': 'F1',
        'destinationBeaconId': 'B2',
      });
    },
  );

  test(
    'origin goes through the case with the same arguments and result',
    () async {
      final sent = <Map<String, dynamic>>[];
      await _withCase(
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
        (c) async {
          final r = await c.factOrigin(beaconId: 'B9', factCardId: 'F9');
          expect(r.available, isTrue);
          expect(r.beaconId, 'B1');
          expect(r.copiedRevisionSeq, 3);
        },
      );
      expect(sent.single['op'], 'BeaconFactCardOrigin');
      expect(sent.single['vars'], {'beaconId': 'B9', 'factCardId': 'F9'});
    },
  );

  test(
    'destinations go through the case with the same arguments and result',
    () async {
      final sent = <Map<String, dynamic>>[];
      await _withCase(
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
            ],
          },
        },
        sent,
        (c) async {
          final r = await c.factCopyDestinations(sourceFactCardId: 'F1');
          expect(r, hasLength(1));
          expect(r.first.id, 'Bone');
          expect(r.first.title, 'Garden help');
        },
      );
      expect(sent.single['op'], 'BeaconFactCopyDestinations');
      expect(sent.single['vars'], {'sourceFactCardId': 'F1'});
    },
  );
}
