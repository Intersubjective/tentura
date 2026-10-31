// tentura-9f0 landing gate acceptance (trial merge tentura-rsm)

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/build_client.dart';

// tentura-n59 landing gate acceptance (chat read receipts)

void main() {
  group('direct V2 operation routing', () {
    test('BeaconStageImage and BeaconSetMedia are routed to Tentura V2', () {
      expect(isTenturaDirectOperation('BeaconStageImage'), isTrue);
      expect(isTenturaDirectOperation('BeaconSetMedia'), isTrue);
      expect(isTenturaDirectOperation('BeaconAddImage'), isTrue);
    });

    test('the server-served invitation TTL lookup routes to Tentura V2', () {
      expect(isTenturaDirectOperation('InvitationTtl'), isTrue);
    });

    test('beaconSetCover is not a supported operation name', () {
      expect(isTenturaDirectOperation('BeaconSetCover'), isFalse);
      expect(isTenturaDirectOperation('beaconSetCover'), isFalse);
    });

    test('subjective-help tag evidence operations route to Tentura V2', () {
      const operationNames = [
        'SubjectiveTags',
        'ForwardContext',
        'MyRoutingTags',
        'TagExplanation',
        'SeedRoutingAttestation',
        'RevokeAcknowledgement',
        'SetRoutingMute',
        'InviteSeedPromptState',
        'InviteSeedPromptAnswer',
        'InviteSeedPromptSkip',
      ];
      for (final name in operationNames) {
        expect(isTenturaDirectOperation(name), isTrue, reason: name);
      }
    });

    test('availability profile commands route to Tentura V2', () {
      const operationNames = [
        'UserAvailabilitySetLimited',
        'UserAvailabilityPause',
        'UserAvailabilityResume',
      ];
      for (final name in operationNames) {
        expect(isTenturaDirectOperation(name), isTrue, reason: name);
      }
    });

    test('the field targeted Request read routes to Tentura V2 (#671); '
        'the relation read stays on Hasura (#672)', () {
      expect(
        isTenturaDirectOperation('ConstellationFieldRequestsFetch'),
        isTrue,
      );
      expect(isTenturaDirectOperation('ConstellationViewerRelations'), isFalse);
    });

    test('the tag magnet read and writes route to Tentura V2', () {
      for (final name in const [
        'ConstellationTagMagnets',
        'ConstellationTagMagnetUpsert',
        'ConstellationTagMagnetRemove',
      ]) {
        expect(isTenturaDirectOperation(name), isTrue, reason: name);
      }
    });

    test('ForwardCandidatesFetch routes to Tentura V2', () {
      expect(isTenturaDirectOperation('ForwardCandidatesFetch'), isTrue);
    });

    test('ForwardCandidateContextFetch routes to Tentura V2', () {
      expect(isTenturaDirectOperation('ForwardCandidateContextFetch'), isTrue);
    });

    test('PersonSharedContexts routes to Tentura V2', () {
      expect(isTenturaDirectOperation('PersonSharedContexts'), isTrue);
    });

    test('Activity coalesce attention ops route to Tentura V2', () {
      expect(isTenturaDirectOperation('ActivityOffersV2'), isTrue);
      expect(isTenturaDirectOperation('ActivityAttention'), isTrue);
    });

    test('BeaconRoomReadWatermarks routes to Tentura V2', () {
      expect(isTenturaDirectOperation('BeaconRoomReadWatermarks'), isTrue);
    });

    test('MarkBeaconPeopleSeen routes to Tentura V2', () {
      expect(isTenturaDirectOperation('MarkBeaconPeopleSeen'), isTrue);
    });

    test('post bud and author-invite operations route to Tentura V2', () {
      const operationNames = [
        'PostBudFromPost',
        'PostBudInviteCandidates',
        'AuthorInviteCreate',
        'AuthorInviteAccept',
        'AuthorInviteDecline',
        'AuthorInviteWithdraw',
        'MyPendingAuthorInvites',
        'BeaconAuthorInvites',
        'BeaconBudObservers',
      ];
      for (final name in operationNames) {
        expect(isTenturaDirectOperation(name), isTrue, reason: name);
      }
    });

    test('noisy-wall preference operations route to Tentura V2', () {
      expect(isTenturaDirectOperation('NoisyWallEnabled'), isTrue);
      expect(isTenturaDirectOperation('SetNoisyWallEnabled'), isTrue);
    });
  });
}
