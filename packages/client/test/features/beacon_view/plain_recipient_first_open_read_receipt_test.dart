// A person who received a Request by forward, but has not offered help, opens
// it. The sender's "sent to" list can only show «read» if the open tells the
// server, and the Request's involvement read (the only thing that used to
// stamp it) is skipped for people without involvement access.
//
// Real path: the screen's BeaconViewCubit over the production BeaconViewCase,
// repositories, Ferry link chain and RemoteApiService. Only HTTP is faked, by
// a server that answers from schema.graphql (see GraphqlRoundTripServer).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:tentura/data/service/remote_api_client/build_client.dart'
    show isTenturaDirectOperation;
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

import '../../support/graphql_round_trip_server.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'request_open_round_trips_support.dart';

const _beaconId = kOpenRoundsBeaconId;
const _viewerId = 'Uplainrecipient';

/// `BeaconAccessReason` bits: author 1, admitted 4, forwarded 8.
const _author = 1;
const _admitted = 4;
const _forwarded = 8;

const _markReadOperation = 'BeaconForwardMarkRead';

/// Opens the Request as `_viewerId` with the given access and settles every
/// read, then reloads it `backgroundRefreshes` more times. Returns the server (to inspect what the screen sent) and the state.
typedef _Opened = ({
  GraphqlRoundTripServer server,
  BeaconViewState state,
  List<Map<String, dynamic>> bodies,
});

/// Records every GraphQL request body on its way to the fake server.
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._inner, this.bodies);

  final http.Client _inner;
  final List<Map<String, dynamic>> bodies;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is http.Request && request.body.isNotEmpty) {
      final decoded = jsonDecode(request.body);
      for (final op in decoded is List ? decoded : [decoded]) {
        bodies.add(op as Map<String, dynamic>);
      }
    }
    return _inner.send(request);
  }
}

Future<_Opened> _open({
  required int accessLevel,
  required int accessReasons,
  required bool canReadInvolvement,
  int backgroundRefreshes = 0,
}) async {
  final server = GraphqlRoundTripServer(
    viewerId: _viewerId,
    overrides: (type, field, operation) => switch ((type, field)) {
      ('beacon', 'id') => _beaconId,
      ('beacon', 'status') => 0,
      ('beacon', 'kind') || ('beacon', 'forward_policy') => 0,
      ('beacon', 'access_level') => accessLevel,
      ('beacon', 'access_reasons') => accessReasons,
      ('beacon', 'can_read_content') || ('beacon', 'is_discoverable') => true,
      ('beacon', 'can_read_involvement') ||
      ('beacon', 'can_read_admitted_helpers') => canReadInvolvement,
      ('beacon', 'title') => kOpenRoundsTitle,
      ('user', 'id') => kOpenRoundsAuthorId,
      ('user', 'display_name') => 'Somebody',
      _ => GraphqlRoundTripServer.auto,
    },
  );
  final effects = FakeUiEffectPort();
  final bodies = <Map<String, dynamic>>[];
  late BeaconViewState state;
  await http.runWithClient(() async {
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
    );
    final realtime = buildTestRealtimeSync();
    try {
      await remote.setSessionAuth();
      final wired = buildWiredBeaconViewCase(remote, realtime);
      final cubit = BeaconViewCubit(
        id: _beaconId,
        myProfile: const Profile(id: _viewerId, displayName: 'Viewer'),
        beaconViewCase: wired.viewCase,
        effects: effects,
      );
      try {
        await server.drain();
        // Realtime catch-up and invalidations reload the open Request through
        // the same fetch; none of them is a new «first open».
        for (var i = 0; i < backgroundRefreshes; i++) {
          // The fake server answers only while drained, so run both at once.
          final refreshed = cubit.refreshAfterClosureReview();
          await server.drain();
          await refreshed;
        }
        state = cubit.state;
      } finally {
        await cubit.close();
        await wired.beacons.dispose();
      }
    } finally {
      await realtime.port.dispose();
      await remote.close();
    }
  }, () => _RecordingClient(server.client, bodies));
  return (server: server, state: state, bodies: bodies);
}

List<GraphqlRoundTripCall> _markReadCalls(GraphqlRoundTripServer server) => [
  for (final call in server.calls)
    if (call.operationNames.contains(_markReadOperation)) call,
];

void main() {
  group('Opening a Request received by forward', () {
    test(
      'a forward recipient (who can read involvement) tells the server once that '
      'they read it',
      () async {
        final opened = await _open(
          accessLevel: 2, // observer
          accessReasons: _forwarded,
          // Production policy (m0280): a forward recipient can read involvement.
          canReadInvolvement: true,
        );
        final trace = opened.server.describe();

        expect(opened.state.beaconContentLoaded, isTrue, reason: trace);
        expect(opened.state.beacon.canReadInvolvement, isTrue, reason: trace);

        final calls = _markReadCalls(opened.server);
        expect(
          calls,
          hasLength(1),
          reason: 'one read receipt per open, not one per refresh\n$trace',
        );
        expect(calls.single.path, '/api/v2/graphql', reason: trace);
        final sent = opened.bodies.where(
          (b) => b['operationName'] == _markReadOperation,
        );
        expect(sent.single['variables'], containsPair('id', _beaconId));
        expect(
          isTenturaDirectOperation(_markReadOperation),
          isTrue,
          reason: 'the mutation lives on Tentura V2 and must route there',
        );
      },
    );

    test(
      'reloading the open Request does not send the read receipt again',
      () async {
        final opened = await _open(
          accessLevel: 2,
          accessReasons: _forwarded,
          canReadInvolvement: true,
          backgroundRefreshes: 2,
        );
        final trace = opened.server.describe();
        expect(opened.state.beaconContentLoaded, isTrue, reason: trace);
        expect(
          _markReadCalls(opened.server),
          hasLength(1),
          reason: 'one read receipt per open, not one per refresh\n$trace',
        );
      },
    );

    for (final (name, level, reasons) in [
      ('an author', 0, _author),
      ('an admitted helper', 1, _admitted),
    ]) {
      test(
        '$name who did not receive it by forward sends no read receipt',
        () async {
          final opened = await _open(
            accessLevel: level,
            accessReasons: reasons,
            canReadInvolvement: true,
            backgroundRefreshes: 1,
          );
          final trace = opened.server.describe();
          expect(opened.state.beaconContentLoaded, isTrue, reason: trace);
          expect(_markReadCalls(opened.server), isEmpty, reason: trace);
        },
      );
    }

    // Forwarded to them as well: the receipt is idempotent on the server, so
    // one extra call is harmless and keeps the stamp independent of the
    // lazily-loaded involvement read.
    for (final (name, level, reasons) in [
      (
        'an admitted helper who also received it by forward',
        1,
        _admitted | _forwarded,
      ),
    ]) {
      test('$name sends exactly one read receipt per open', () async {
        final opened = await _open(
          accessLevel: level,
          accessReasons: reasons,
          canReadInvolvement: true,
          backgroundRefreshes: 1,
        );
        final trace = opened.server.describe();
        expect(opened.state.beaconContentLoaded, isTrue, reason: trace);
        expect(_markReadCalls(opened.server), hasLength(1), reason: trace);
      });
    }

    test(
      'an observer who did not receive it by forward sends no read receipt',
      () async {
        final opened = await _open(
          accessLevel: 2,
          accessReasons: 32, // discovered
          canReadInvolvement: false,
        );
        expect(
          _markReadCalls(opened.server),
          isEmpty,
          reason: opened.server.describe(),
        );
      },
    );
  });
}
