import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_requests_fetch.data.gql.dart';
import 'package:tentura/features/constellation/data/model/constellation_field_mapper.dart';
import 'package:tentura/features/constellation/data/repository/constellation_targeted_read_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';

import '../../support/remote_wire_harness.dart';

const _beaconId = 'Bnewfield001';
const _authorId = 'Ufieldauthor1';
const _request = ConstellationRequest(
  id: _beaconId,
  authorId: _authorId,
  title: 'Published without sending',
  status: 0,
);

Map<String, dynamic> _response() => {
  '__typename': 'query_root',
  'constellationFieldRequests': [
    {
      '__typename': 'v2_ConstellationRequest',
      'id': _beaconId,
      'authorId': _authorId,
      'title': _request.title,
      'status': 0,
      'needs': <String>[],
      'primaryNeedSlug': null,
      'startAt': null,
      'endAt': null,
      'addressLabel': null,
      'hasCoordinates': false,
      'isMine': false,
      'viewerHasActiveHelpOffer': false,
      'viewerIsRoomParticipant': false,
      'viewerHasForwardEdge': false,
      'helpOfferCount': 0,
      'coverSource': 0,
      'coverThumb': null,
      'parentBeaconId': null,
    },
  ],
};

void main() {
  group('A targeted read returns a newly published Request', () {
    test(
      'an authorized empty discovery response produces no Request entities',
      () async {
        final sent = <WireSent>[];
        await withRemoteWire(
          {
            'ConstellationFieldRequestsFetch': {
              '__typename': 'query_root',
              'constellationFieldRequests': <Map<String, dynamic>>[],
            },
          },
          sent,
          (remote) async {
            // The authorized server read excludes non-discoverable rows. The
            // client DTO has no isDiscoverable flag to recheck: an omitted row
            // must remain absent through the actual Ferry/repository boundary.
            final repository = ConstellationTargetedReadRepository(remote);
            expect(
              await repository.fetchRequests({'not-discoverable'}),
              isEmpty,
            );
          },
        );
        expect(sent, hasLength(1));
        expect(sent.single.operationName, 'ConstellationFieldRequestsFetch');
        expect(sent.single.variables['ids'], ['not-discoverable']);
      },
    );

    test('nullable media and scheduling fields survive GraphQL decoding and '
        'domain mapping', () {
      final data = GConstellationFieldRequestsFetchData.fromJson(_response())!;
      final requests = mapConstellationFieldRequestsFetch(
        data.constellationFieldRequests,
      );

      expect(requests, [_request]);
      expect(requests.single.coverThumb, isNull);
      expect(requests.single.needs, isEmpty);
      expect(requests.single.helpOfferCount, 0);
    });

    test(
      'the repository reads the beacon id decoded from the item hint and '
      'returns the new Request without swallowing mapping failures',
      () async {
        final socket = StreamController<Map<String, dynamic>>.broadcast();
        final invalidation = InvalidationService.forTesting(socket.stream);
        addTearDown(() async {
          await invalidation.dispose();
          await socket.close();
        });
        final pendingHint = invalidation.entityChanges.firstWhere(
          (change) => change.kind == RealtimeEntityKind.constellationItem,
        );
        socket.add({
          'type': 'subscription',
          'path': 'entity_changes',
          'payload': {
            'entity': 'constellation_item',
            'id': _beaconId,
            'event': 'insert',
            'actor_user_id': _authorId,
          },
        });
        final hint = await pendingHint;
        expect(hint.aggregateId, _beaconId);
        expect(hint.operation, RealtimeOperation.insert);

        final sent = <WireSent>[];
        await withRemoteWire(
          {'ConstellationFieldRequestsFetch': _response()},
          sent,
          (remote) async {
            final repository = ConstellationTargetedReadRepository(remote);
            final requests = await repository.fetchRequests({hint.aggregateId});
            expect(requests, [_request]);
          },
        );
        expect(sent, hasLength(1));
        expect(sent.single.operationName, 'ConstellationFieldRequestsFetch');
        expect(sent.single.variables, {
          'ids': [_beaconId],
          'showClosed': false,
          'participatedOnly': false,
        });
      },
    );
  });
}
