import 'package:built_collection/built_collection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/data/gql/_g/beacon_involvement_data.data.gql.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';

final _beacon = Beacon.empty;

ForwardCandidate _candidateFromInvolvement(
  Profile profile,
  BeaconInvolvementData involvement,
) =>
    ForwardCandidate(
      profile: profile,
      involvement: ForwardCase.computeInvolvement(profile.id, involvement),
      myForwardNote: involvement.myForwardedRecipientNotes[profile.id],
      forwardEdgeId: involvement.myForwardedRecipientEdgeIds[profile.id],
      recipientReadAt: involvement.myForwardedRecipientReadAts[profile.id],
    );

GBeaconInvolvementDataData_beaconInvolvement _gqlInvolvement(
  void Function(GBeaconInvolvementDataData_beaconInvolvementBuilder b) updates,
) =>
    GBeaconInvolvementDataData_beaconInvolvement(updates);

void main() {
  group('ForwardRepository.mapBeaconInvolvement', () {
    test('maps myForwardedRecipients to notes, edge ids, and readAt', () {
      final gql = _gqlInvolvement(
        (b) => b
          ..myForwardedRecipients = ListBuilder([
            GBeaconInvolvementDataData_beaconInvolvement_myForwardedRecipients(
              (r) => r
                ..recipientId = 'recipient-1'
                ..edgeId = 'edge-abc'
                ..note = 'Please help'
                ..readAt = '2025-06-01T12:00:00.000Z',
            ),
          ]),
      );

      final involvement = ForwardRepository.mapBeaconInvolvement(
        beacon: _beacon,
        inv: gql,
      );

      expect(
        involvement.myForwardedRecipientNotes,
        {'recipient-1': 'Please help'},
      );
      expect(
        involvement.myForwardedRecipientEdgeIds,
        {'recipient-1': 'edge-abc'},
      );
      expect(
        involvement.myForwardedRecipientReadAts['recipient-1'],
        DateTime.utc(2025, 6, 1, 12),
      );
    });

    test('null GraphQL lists become empty sets', () {
      final involvement = ForwardRepository.mapBeaconInvolvement(
        beacon: _beacon,
        inv: _gqlInvolvement((_) {}),
      );

      expect(involvement.forwardedToIds, isEmpty);
      expect(involvement.helpOfferedIds, isEmpty);
      expect(involvement.withdrawnIds, isEmpty);
      expect(involvement.rejectedIds, isEmpty);
      expect(involvement.watchingIds, isEmpty);
      expect(involvement.onwardForwarderIds, isEmpty);
      expect(involvement.myForwardedRecipientNotes, isEmpty);
    });

    test('maps involvement id sets from GraphQL', () {
      final involvement = ForwardRepository.mapBeaconInvolvement(
        beacon: _beacon,
        inv: _gqlInvolvement(
          (b) => b
            ..forwardedToIds = ListBuilder(['fwd'])
            ..helpOfferedIds = ListBuilder(['help'])
            ..withdrawnIds = ListBuilder(['wd'])
            ..rejectedIds = ListBuilder(['rej'])
            ..watchingIds = ListBuilder(['watch'])
            ..onwardForwarderIds = ListBuilder(['onward']),
        ),
      );

      expect(involvement.forwardedToIds, {'fwd'});
      expect(involvement.helpOfferedIds, {'help'});
      expect(involvement.withdrawnIds, {'wd'});
      expect(involvement.rejectedIds, {'rej'});
      expect(involvement.watchingIds, {'watch'});
      expect(involvement.onwardForwarderIds, {'onward'});
    });
  });

  group('GraphQL involvement → ForwardCandidate merge', () {
    test('forwardedByMe recipient carries note and edge id', () {
      const profile = Profile(id: 'recipient-1', displayName: 'R');
      final gql = _gqlInvolvement(
        (b) => b
          ..myForwardedRecipients = ListBuilder([
            GBeaconInvolvementDataData_beaconInvolvement_myForwardedRecipients(
              (r) => r
                ..recipientId = 'recipient-1'
                ..edgeId = 'edge-1'
                ..note = 'Check this beacon',
            ),
          ]),
      );

      final candidate = _candidateFromInvolvement(
        profile,
        ForwardRepository.mapBeaconInvolvement(beacon: _beacon, inv: gql),
      );

      expect(candidate.involvement, CandidateInvolvement.forwardedByMe);
      expect(candidate.myForwardNote, 'Check this beacon');
      expect(candidate.forwardEdgeId, 'edge-1');
    });

    test('helpOffered id set yields helpOffered candidate', () {
      const profile = Profile(id: 'helper', displayName: 'H');
      final gql = _gqlInvolvement(
        (b) => b..helpOfferedIds = ListBuilder(['helper']),
      );

      final candidate = _candidateFromInvolvement(
        profile,
        ForwardRepository.mapBeaconInvolvement(beacon: _beacon, inv: gql),
      );

      expect(candidate.involvement, CandidateInvolvement.helpOffered);
      expect(candidate.myForwardNote, isNull);
    });

    test('rejected id set yields declined candidate', () {
      const profile = Profile(id: 'decliner', displayName: 'D');
      final gql = _gqlInvolvement(
        (b) => b..rejectedIds = ListBuilder(['decliner']),
      );

      final candidate = _candidateFromInvolvement(
        profile,
        ForwardRepository.mapBeaconInvolvement(beacon: _beacon, inv: gql),
      );

      expect(candidate.involvement, CandidateInvolvement.declined);
    });

    test('forwardedToIds yields forwarded candidate', () {
      const profile = Profile(id: 'recipient', displayName: 'R');
      final gql = _gqlInvolvement(
        (b) => b..forwardedToIds = ListBuilder(['recipient']),
      );

      final candidate = _candidateFromInvolvement(
        profile,
        ForwardRepository.mapBeaconInvolvement(beacon: _beacon, inv: gql),
      );

      expect(candidate.involvement, CandidateInvolvement.forwarded);
    });

    test('myForwardedRecipients wins over forwardedToIds for same user', () {
      const profile = Profile(id: 'u1', displayName: 'U');
      final gql = _gqlInvolvement(
        (b) => b
          ..forwardedToIds = ListBuilder(['u1'])
          ..myForwardedRecipients = ListBuilder([
            GBeaconInvolvementDataData_beaconInvolvement_myForwardedRecipients(
              (r) => r
                ..recipientId = 'u1'
                ..edgeId = 'edge-me'
                ..note = 'From me',
            ),
          ]),
      );

      final candidate = _candidateFromInvolvement(
        profile,
        ForwardRepository.mapBeaconInvolvement(beacon: _beacon, inv: gql),
      );

      expect(candidate.involvement, CandidateInvolvement.forwardedByMe);
      expect(candidate.myForwardNote, 'From me');
    });

    test('parses fixture JSON via fromJson', () {
      final built = _gqlInvolvement(
        (b) => b
          ..watchingIds = ListBuilder(['watcher'])
          ..myForwardedRecipients = ListBuilder([
            GBeaconInvolvementDataData_beaconInvolvement_myForwardedRecipients(
              (r) => r
                ..recipientId = 'watcher'
                ..edgeId = 'edge-w'
                ..note = 'Watching note',
            ),
          ]),
      );
      final json = built.toJson();
      final parsed =
          GBeaconInvolvementDataData_beaconInvolvement.fromJson(json)!;

      final involvement = ForwardRepository.mapBeaconInvolvement(
        beacon: _beacon,
        inv: parsed,
      );
      const profile = Profile(id: 'watcher', displayName: 'W');
      final candidate = _candidateFromInvolvement(profile, involvement);

      // watching beats forwardedToIds, but myForwardedRecipients → forwardedByMe
      expect(candidate.involvement, CandidateInvolvement.forwardedByMe);
      expect(candidate.myForwardNote, 'Watching note');
    });
  });
}
