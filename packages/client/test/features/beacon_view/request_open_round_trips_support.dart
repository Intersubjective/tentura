// Shared scenario for the Request-open round-trip tests: one Request served
// by a GraphqlRoundTripServer, and the production BeaconViewCase over the
// real repositories and RemoteApiService that talk to it.

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/service/remote_api_client/build_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_activity_event_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_view/data/repository/beacon_display_repository.dart';
import 'package:tentura/features/beacon_view/data/repository/coordination_repository.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/inbox/data/repository/posts_repository.dart';
import 'package:tentura/features/my_work/data/repository/archive_repository.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';

import '../../support/graphql_round_trip_server.dart';
import 'beacon_view_case_test_support.dart' show quietTestPresenceRepository;

const kOpenRoundsBeaconId = 'Bopenrounds';
const kOpenRoundsAuthorId = 'Uopenroundsauthor';
const kOpenRoundsHelperId = 'Uopenroundshelper';
const kOpenRoundsTitle = 'Move the couch';
const kOpenRoundsForwardId = 'Fopenrounds';

/// Path and operation of every GraphQL call, in send order.
String openRoundsTrace(GraphqlRoundTripServer server) => [
  '${server.rounds} rounds, ${server.calls.length} calls',
  for (final call in server.calls)
    'r${call.round + 1} ${call.path} ${call.operationNames.join('+')}',
].join('\n');

/// Pins the measured chain and that each operation uses the path
/// DEV_GUIDELINES assigns: v2 when [isTenturaDirectOperation], else Hasura v1.
void expectOpenRounds(
  GraphqlRoundTripServer server, {
  required int rounds,
  required int calls,
  required int roundsBefore,
  required int callsBefore,
}) {
  final trace = openRoundsTrace(server);
  expect(
    server.rounds,
    rounds,
    reason: 'After $rounds round trips (before $roundsBefore).\n$trace',
  );
  expect(
    server.calls.length,
    calls,
    reason: 'After $calls requests (before $callsBefore).\n$trace',
  );
  for (final call in server.calls) {
    for (final name in call.operationNames) {
      expect(
        call.path,
        isTenturaDirectOperation(name) ? '/api/v2/graphql' : '/api/v1/graphql',
        reason: '$name\n$trace',
      );
    }
  }
}

/// A server holding one Request seen by [viewerId] (its author, or an
/// admitted helper). Besides the Request it holds one forward edge sent by
/// the viewer, the Request's display status (Cancel allowed) and, while
/// wrapping up, a final-check snapshot at epoch 2, so a test can check those
/// still reach the screen. Every other read answers empty.
GraphqlRoundTripServer openRoundsServer({
  required String viewerId,
  required BeaconStatus status,
}) {
  final isAuthor = viewerId == kOpenRoundsAuthorId;
  return GraphqlRoundTripServer(
    viewerId: viewerId,
    overrides: (type, field, operation) => switch ((type, field)) {
      ('beacon', 'id') ||
      ('v2_BeaconDisplayStatus', 'beaconId') => kOpenRoundsBeaconId,
      ('beacon', 'status') ||
      ('v2_BeaconDisplayStatus', 'status') => status.smallintValue,
      ('beacon', 'kind') || ('beacon', 'forward_policy') => 0,
      // Author: level 0, reason author. Helper: level 1, reason admitted.
      ('beacon', 'access_level') => isAuthor ? 0 : 1,
      ('beacon', 'access_reasons') => isAuthor ? 1 : 4,
      ('beacon', 'can_read_content') ||
      ('beacon', 'can_read_involvement') ||
      ('beacon', 'can_read_admitted_helpers') ||
      ('beacon', 'is_discoverable') => true,
      ('beacon', 'title') => kOpenRoundsTitle,
      // The author is the only person in these answers besides forward
      // edges, whose sender is the viewer.
      ('user', 'id') =>
        operation == 'ForwardEdgesFetch' ? viewerId : kOpenRoundsAuthorId,
      ('user', 'display_name') => 'Somebody',
      ('query_root', 'beacon_forward_edge') ||
      ('query_root', 'beaconDisplayStatuses') => GraphqlRoundTripServer.oneRow,
      ('beacon_forward_edge', 'id') => kOpenRoundsForwardId,
      ('beacon_forward_edge', 'beacon_id') => kOpenRoundsBeaconId,
      ('beacon_forward_edge', 'cancelled_at') => null,
      ('v2_BeaconDisplayStatus', 'canCancel') => true,
      ('v2_BeaconDisplayStatus', 'phase') => 'coordinating',
      ('v2_ClosureState', 'status') => status.smallintValue,
      ('v2_ClosureState', 'epoch') => 2,
      ('v2_ClosureState', 'canCloseNow') => isAuthor,
      ('v2_ClosureState', 'role') => isAuthor ? 'author' : 'voter',
      _ => GraphqlRoundTripServer.auto,
    },
  );
}

/// The production Request use case and the real repositories it reads
/// through, all over [remote].
({
  BeaconViewCase viewCase,
  BeaconThreadsCase threadsCase,
  BeaconRepository beacons,
})
buildWiredBeaconViewCase(
  RemoteApiService remote,
  ({RealtimeSyncCase case_, RealtimeSyncPort port}) realtime,
) {
  final beacons = BeaconRepository(remote, realtime.port);
  final hints = BeaconRoomHintsRepository(remote);
  final threads = BeaconThreadsCase(
    BeaconThreadsRepository(remote, realtime.port),
    BeaconFactCardRepository(remote),
    PollingRepository(remote),
    hints,
    RoomReadWatermarkStore.testing(),
    realtime.case_,
    env: const Env(),
    logger: Logger('request-open-rounds'),
  );
  final viewCase = BeaconViewCase(
    beacons,
    ForwardRepository(remote, beacons, realtime.port),
    ClosureRepository(remote),
    ArchiveRepository(remote),
    CoordinationRepository(remote),
    BeaconDisplayRepository(remote),
    InboxRepository(remote, hints),
    PostsRepository(remote),
    BeaconFactCardRepository(remote),
    threads,
    BeaconActivityEventRepository(remote, realtime.port),
    realtime.case_,
    env: const Env(),
    logger: Logger('request-open-rounds'),
    presenceRepository: quietTestPresenceRepository(),
    hierarchyRepository: BeaconHierarchyRepository(remote),
  );
  return (viewCase: viewCase, threadsCase: threads, beacons: beacons);
}
