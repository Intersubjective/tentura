// A Request draft carries one durable client operation id: the `BeaconCreate`
// mutation sends it, a retry after a failed create sends the same one, and it
// survives the composer being closed and reopened. Observed on the wire through
// the real `BeaconCreateCase` and `BeaconRepository` over a mocked transport.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/port/beacon_child_command_store_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

/// Command-id store that also accepts the standalone (top-level) context.
class _DurableCommandStore implements BeaconChildCommandStorePort {
  final values = <String, String>{};

  static String _key(BeaconCreationContext context) => switch (context) {
    BeaconCreationContextStandalone() => 'standalone',
    BeaconCreationContextChild(:final parentBeaconId) => 'child:$parentBeaconId',
    BeaconCreationContextPromotedChild(
      :final parentBeaconId,
      :final sourceMessageId,
    ) =>
      'promo:$parentBeaconId:$sourceMessageId',
  };

  @override
  Future<void> clear(BeaconCreationContext context) async =>
      values.remove(_key(context));

  @override
  Future<String?> read(BeaconCreationContext context) async =>
      values[_key(context)];

  @override
  Future<void> write(BeaconCreationContext context, String clientCommandId) async =>
      values[_key(context)] = clientCommandId;
}

/// Runs [body] against a real repository whose transport records the
/// `clientOpId` of every `BeaconCreate` request. The first [failFirst] create
/// requests fail the way a timed-out network call does.
Future<List<Object?>> _withWire(
  Future<void> Function(BeaconCreateCase caseUnderTest) body, {
  int failFirst = 0,
}) async {
  final sent = <Object?>[];
  await http.runWithClient(
    () async {
      final remote = RemoteApiService(
        const Env(),
        const WebSocketClientRealtimeSocketFactory(),
      );
      final sync = buildTestRealtimeSync();
      try {
        await remote.setSessionAuth();
        await body(
          BeaconCreateCase(
            BeaconRepository(remote, sync.port),
            FakeBeaconImagePort(),
          ),
        );
      } finally {
        await remote.close();
        await sync.port.dispose();
      }
    },
    () => MockClient((request) async {
      const headers = {'content-type': 'application/json'};
      if (request.url.path.endsWith('/session/access-token')) {
        return http.Response(
          jsonEncode({
            'subject': 'Uauthor000001',
            'access_token': 'test-token',
            'expires_in': 3600,
          }),
          200,
          headers: headers,
        );
      }
      final json = jsonDecode(request.body) as Map<String, dynamic>;
      if (json['operationName'] == 'BeaconCreate') {
        sent.add((json['variables'] as Map)['clientOpId']);
        if (sent.length <= failFirst) {
          return http.Response(
            jsonEncode({
              'errors': [
                {'message': 'timeout'},
              ],
            }),
            200,
            headers: headers,
          );
        }
        return http.Response(
          jsonEncode({
            'data': {
              'beaconCreate': {'__typename': 'v2_Beacon', 'id': 'Bdraft000001'},
            },
          }),
          200,
          headers: headers,
        );
      }
      return http.Response(jsonEncode({'data': null}), 200, headers: headers);
    }),
  );
  return sent;
}

BeaconCreateCubit _composer(
  BeaconCreateCase createCase,
  BeaconChildCommandStorePort store,
) => BeaconCreateCubit(
  beaconCreateCase: createCase,
  hierarchyCase: buildBeaconHierarchyCaseForTest(
    FakeBeaconHierarchyRepositoryPort(),
    createCase: createCase,
    beacons: FakeBeaconWritePort(),
    commandStore: store,
  ),
  effects: FakeUiEffectPort(),
);

Future<void> _saveDraft(BeaconCreateCubit cubit) async {
  await pumpEventQueue();
  cubit
    ..setTitle('Need a piano moved')
    ..setDescription('Two flights of stairs, this weekend.');
  await cubit.ensureDraft(context: 'c', showMessage: false);
}

void main() {
  group('Request create idempotency key', () {
    test('sends the persisted draft id as clientOpId on the wire', () async {
      final store = _DurableCommandStore()
        ..values['standalone'] = 'persisted-op-id';

      final sent = await _withWire((createCase) async {
        final cubit = _composer(createCase, store);
        addTearDown(cubit.close);
        await _saveDraft(cubit);
      });

      expect(sent, ['persisted-op-id']);
    });

    test('a retry after a failed create reuses the same id', () async {
      final store = _DurableCommandStore();

      final sent = await _withWire(failFirst: 1, (createCase) async {
        final cubit = _composer(createCase, store);
        addTearDown(cubit.close);
        await _saveDraft(cubit);
        await cubit.ensureDraft(context: 'c', showMessage: false);
      });

      expect(sent, hasLength(2));
      expect(sent.first, isA<String>());
      expect(sent.first as String, isNotEmpty);
      expect(sent.last, sent.first);
    });

    test('a reopened composer reuses the id of the unsaved draft', () async {
      final store = _DurableCommandStore();

      final sent = await _withWire(failFirst: 1, (createCase) async {
        final first = _composer(createCase, store);
        await _saveDraft(first);
        await first.close();

        final reopened = _composer(createCase, store);
        addTearDown(reopened.close);
        await _saveDraft(reopened);
      });

      expect(sent, hasLength(2));
      expect(sent.first, isNotNull);
      expect(sent.last, sent.first);
    });
  });
}
