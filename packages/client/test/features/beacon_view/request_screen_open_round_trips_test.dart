// How many GraphQL requests the Request screen sends when it opens, and how
// many round trips it waits through before it is complete (Sentry
// "Consecutive HTTP" on BeaconViewRoute, #750).
//
// Real path: the screen's BeaconViewCubit over the production BeaconViewCase,
// repositories, Ferry link chain and RemoteApiService. Only HTTP is faked, by
// a server that answers from schema.graphql and holds responses back in
// rounds (see GraphqlRoundTripServer).
//
// Before the fix (measured with this harness):
//   author, live Request:          13 requests, 3 round trips
//   author, wrapping-up Request:   11 requests, 4 round trips
//   helper, wrapping-up Request:   11 requests, 4 round trips
// After (the forwards and the final check leave with the other reads, and
// neither re-reads the Request):
//   author, live Request:          12 requests, 2 round trips
//   author, wrapping-up Request:   10 requests, 2 round trips
//   helper, wrapping-up Request:   10 requests, 2 round trips
// Since then the "Seen by" lookup (#766) leaves in the same round as the
// other reads: one more request each, no more round trips (13 / 11 / 11).

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

import '../../support/graphql_round_trip_server.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'request_open_round_trips_support.dart';

const _beaconId = kOpenRoundsBeaconId;
const _authorId = kOpenRoundsAuthorId;
const _helperId = kOpenRoundsHelperId;

/// What the open Request screen ended up showing, plus how it got there.
typedef _OpenedRequest = ({
  GraphqlRoundTripServer server,
  BeaconViewState state,
  FakeUiEffectPort effects,
});

/// Opens the Request as [viewerId] and answers every read until the load
/// settles. The server holds one forward edge sent by the viewer, the
/// Request's display status and (while wrapping up) its final-check
/// snapshot, so the test can check those still reach the screen.
Future<_OpenedRequest> _openRequest({
  required String viewerId,
  required BeaconStatus status,
}) async {
  final server = openRoundsServer(viewerId: viewerId, status: status);
  final effects = FakeUiEffectPort();
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
      final beacons = wired.beacons;
      final cubit = BeaconViewCubit(
        id: _beaconId,
        myProfile: Profile(id: viewerId, displayName: 'Viewer'),
        beaconViewCase: wired.viewCase,
        effects: effects,
      );
      try {
        await server.drain();
        state = cubit.state;
      } finally {
        await cubit.close();
        await beacons.dispose();
      }
    } finally {
      await realtime.port.dispose();
      await remote.close();
    }
  }, () => server.client);
  return (server: server, state: state, effects: effects);
}

void _expectLoaded(_OpenedRequest opened, BeaconStatus status) {
  final state = opened.state;
  final trace = opened.server.describe();
  expect(state.loadError, isNull, reason: trace);
  expect(opened.effects.emitted, isEmpty, reason: trace);
  expect(state.beaconUnavailable, isFalse, reason: trace);
  expect(state.beaconContentLoaded, isTrue, reason: trace);
  expect(state.beaconContextLoaded, isTrue, reason: trace);
  expect(state.firstLoadDone, isTrue, reason: trace);
  expect(state.beacon.id, _beaconId);
  expect(state.beacon.title, kOpenRoundsTitle);
  expect(state.beacon.status, status);
  expect(state.displayStatus?.canCancel, isTrue, reason: trace);
}

void main() {
  group('Opening the Request screen', () {
    test(
      'the author of a live Request gets the whole screen, including their '
      'forward status, in two round trips and fewer than 14 requests',
      () async {
        final opened = await _openRequest(
          viewerId: _authorId,
          status: BeaconStatus.open,
        );
        final server = opened.server;
        final trace = server.describe();

        _expectLoaded(opened, BeaconStatus.open);
        // The "sent to nobody yet" line (#484) still knows the author's
        // forwards.
        expect(opened.state.forwardsLoaded, isTrue, reason: trace);
        expect(
          opened.state.myForwards.map((edge) => edge.id),
          [kOpenRoundsForwardId],
          reason: trace,
        );

        expectOpenRounds(
          server,
          rounds: 2,
          calls: 13,
          roundsBefore: 3,
          callsBefore: 13,
        );
      },
    );

    test(
      'the author of a wrapping-up Request gets the final check in two round '
      'trips and fewer than 12 requests',
      () async {
        final opened = await _openRequest(
          viewerId: _authorId,
          status: BeaconStatus.reviewOpen,
        );
        final server = opened.server;
        final trace = server.describe();

        _expectLoaded(opened, BeaconStatus.reviewOpen);
        expect(opened.state.closureState?.epoch, 2, reason: trace);
        expect(opened.state.closureState?.canCloseNow, isTrue, reason: trace);

        expectOpenRounds(
          server,
          rounds: 2,
          calls: 11,
          roundsBefore: 4,
          callsBefore: 11,
        );
      },
    );

    test(
      'a helper on a wrapping-up Request gets the final check in two round '
      'trips and fewer than 12 requests',
      () async {
        final opened = await _openRequest(
          viewerId: _helperId,
          status: BeaconStatus.reviewOpen,
        );
        final server = opened.server;
        final trace = server.describe();

        _expectLoaded(opened, BeaconStatus.reviewOpen);
        expect(opened.state.isBeaconMine, isFalse);
        expect(opened.state.closureState?.epoch, 2, reason: trace);
        expect(opened.state.closureState?.canCloseNow, isFalse, reason: trace);

        expectOpenRounds(
          server,
          rounds: 2,
          calls: 11,
          roundsBefore: 4,
          callsBefore: 11,
        );
      },
    );
  });
}
