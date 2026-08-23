import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/build_client.dart';

void main() {
  group('direct V2 operation routing', () {
    test('BeaconStageImage and BeaconSetMedia are routed to Tentura V2', () {
      expect(isTenturaDirectOperation('BeaconStageImage'), isTrue);
      expect(isTenturaDirectOperation('BeaconSetMedia'), isTrue);
      expect(isTenturaDirectOperation('BeaconAddImage'), isTrue);
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

    test('ForwardCandidatesFetch routes to Tentura V2', () {
      expect(isTenturaDirectOperation('ForwardCandidatesFetch'), isTrue);
    });

    test('ForwardCandidateContextFetch routes to Tentura V2', () {
      expect(isTenturaDirectOperation('ForwardCandidateContextFetch'), isTrue);
    });
  });
}
