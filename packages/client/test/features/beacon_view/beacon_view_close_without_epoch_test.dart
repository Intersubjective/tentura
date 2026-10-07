import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/service/remote_api_client/realtime_socket.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

const _beaconId = 'Bclosenoepoch1';
const _author = Profile(id: 'Uclauthor0001', displayName: 'Author');

/// Real [ClosureRepository] over HTTP with a finalized author state for a
/// closed Request with no evaluation epoch.
Future<void> _withClosedWithoutEpochServer(
  Future<void> Function(ClosureRepository repo) body,
) => http.runWithClient(
  () async {
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
    );
    try {
      await remote.setSessionAuth();
      await body(ClosureRepository(remote));
    } finally {
      await remote.close();
    }
  },
  () => MockClient((request) async {
    const json = {'content-type': 'application/json'};
    if (request.url.path.endsWith('/session/access-token')) {
      return http.Response(
        jsonEncode({
          'subject': _author.id,
          'access_token': 'test-token',
          'expires_in': 3600,
        }),
        200,
        headers: json,
      );
    }
    final name =
        (jsonDecode(request.body) as Map<String, dynamic>)['operationName'];
    if (name == 'BeaconClose') {
      return http.Response(
        jsonEncode({
          'data': {'beaconClose': true},
        }),
        200,
        headers: json,
      );
    }
    return http.Response(
      jsonEncode({
        'data': {
          'closureState': {
            '__typename': 'ClosureState',
            'epoch': 0,
            'status': 1,
            'role': 'author',
            'members': <Object>[],
            'outcomes': <Object>[],
            'myMarks': <String>[],
            'closesAt': '2026-10-05T19:40:00.000Z',
            'canCloseNow': false,
            'canReopen': false,
            'extensionsUsed': 0,
          },
        },
      }),
      200,
      headers: json,
    );
  }),
);

void main() {
  group(
    'BeaconViewCubit.closeBeacon when the Request closes without an epoch',
    () {
      test(
        'close anyway after the unsettled-offers confirmation completes without an error message',
        () async {
          final effects = FakeUiEffectPort();
          final beaconRepo = TrackingBeaconRepository()
            ..fetchByIdHandler = (_) async => Beacon(
              id: _beaconId,
              title: 'Converted request',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
              status: BeaconStatus.closed,
              canReadContent: true,
              author: _author,
            );

          await _withClosedWithoutEpochServer((repo) async {
            final cubit = BeaconViewCubit(
              id: _beaconId,
              myProfile: _author,
              beaconViewCase: buildTestBeaconViewCase(
                beaconRepo: beaconRepo,
                closureRepo: repo,
              ),
              effects: effects,
            );
            addTearDown(() async {
              await cubit.close();
              await beaconRepo.dispose();
            });

            await cubit.stream
                .timeout(const Duration(seconds: 2))
                .firstWhere((s) => s.beaconContextLoaded);
            await pumpEventQueue();

            final result = await cubit.closeBeacon(
              expectedRequiresReviewWindow: false,
            );

            expect(effects.emitted.whereType<ShowError>(), isEmpty);
            expect(result, isNotNull);
            expect(result!.beaconId, _beaconId);
            // Closed and finalized: no review window left open.
            expect(result.state, 1);
            expect(result.closesAt, isNull);
            expect(result.branchMismatch, isFalse);
            expect(cubit.state.beacon.status, BeaconStatus.closed);
            expect(cubit.state.isLoading, isFalse);
          });
        },
      );
    },
  );
}
