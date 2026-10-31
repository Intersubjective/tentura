// Runs the real `ForwardRepository` over the real Ferry link chain (only the
// HTTP transport is faked) and returns the involvement it maps.

import 'package:gql/language.dart' show printNode;

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/forward/data/gql/_g/beacon_involvement_data.ast.gql.dart'
    as involvement_ast;
import 'package:tentura/features/forward/data/repository/forward_repository.dart';

import '../../../support/remote_wire_harness.dart';
import '../../../support/test_realtime_sync.dart';

class _NoBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The GraphQL text the client sends for `BeaconInvolvementData`.
String beaconInvolvementQueryText() => printNode(involvement_ast.document);

Future<BeaconInvolvementData> fetchWireInvolvement({
  List<String> declinedOfferIds = const [],
  List<String> withdrawnIds = const [],
  List<WireSent>? sent,
}) async {
  late BeaconInvolvementData result;
  final beacon = Beacon.empty.copyWith(
    id: 'Bbeacon000001',
    author: const Profile(id: 'Uauthor000001'),
  );
  await withRemoteWire(
    {
      'BeaconInvolvementData': {
        '__typename': 'query_root',
        'beaconInvolvement': {
          '__typename': 'v2_BeaconInvolvement',
          'forwardedToIds': <String>[],
          'helpOfferedIds': <String>[],
          'withdrawnIds': withdrawnIds,
          'rejectedIds': <String>[],
          'watchingIds': <String>[],
          'onwardForwarderIds': <String>[],
          'declinedOfferIds': declinedOfferIds,
          'myForwardedRecipients': <Map<String, dynamic>>[],
        },
      },
    },
    sent ?? <WireSent>[],
    (remote) async {
      final repository = ForwardRepository(
        remote,
        _NoBeaconRepository(),
        buildTestRealtimeSync().port,
      );
      result = await repository.fetchInvolvementForBeacon(beacon);
    },
  );
  return result;
}
