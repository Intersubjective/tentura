// `ForwardCase.computeInvolvement` for people whose offer the author
// declined: a pure unit test on the involvement entity (no GraphQL), so a
// mapper bug cannot hide which layer is at fault.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';

BeaconInvolvementData _involvement({
  Set<String> declinedOfferIds = const {},
  Set<String> withdrawnIds = const {},
  Set<String> helpOfferedIds = const {},
  Set<String> rejectedIds = const {},
  Set<String> watchingIds = const {},
  Set<String> forwardedToIds = const {},
  Map<String, String> myForwardedRecipientNotes = const {},
}) => (
  beacon: Beacon.empty.copyWith(author: const Profile(id: 'author')),
  forwardedToIds: forwardedToIds,
  helpOfferedIds: helpOfferedIds,
  withdrawnIds: withdrawnIds,
  declinedOfferIds: declinedOfferIds,
  rejectedIds: rejectedIds,
  watchingIds: watchingIds,
  onwardForwarderIds: const <String>{},
  myForwardedRecipientNotes: myForwardedRecipientNotes,
  myForwardedRecipientEdgeIds: const <String, String>{},
  myForwardedRecipientReadAts: const <String, DateTime?>{},
  myForwardedRecipientHasOnwardChild: const <String, bool>{},
  myForwardedRecipientRejected: const <String, bool>{},
);

void main() {
  group('ForwardCase.computeInvolvement with declined offers', () {
    test('an id in declinedOfferIds is offerDeclinedByAuthor', () {
      expect(
        ForwardCase.computeInvolvement(
          'u1',
          _involvement(declinedOfferIds: {'u1'}),
        ),
        CandidateInvolvement.offerDeclinedByAuthor,
      );
    });

    test('declined beats withdrawn when the id is in both', () {
      expect(
        ForwardCase.computeInvolvement(
          'u1',
          _involvement(declinedOfferIds: {'u1'}, withdrawnIds: {'u1'}),
        ),
        CandidateInvolvement.offerDeclinedByAuthor,
      );
    });

    test('an id only in withdrawnIds is still withdrawn', () {
      expect(
        ForwardCase.computeInvolvement(
          'u1',
          _involvement(withdrawnIds: {'u1'}),
        ),
        CandidateInvolvement.withdrawn,
      );
    });

    test('someone else in declinedOfferIds leaves a withdrawer withdrawn', () {
      expect(
        ForwardCase.computeInvolvement(
          'u1',
          _involvement(declinedOfferIds: {'u2'}, withdrawnIds: {'u1'}),
        ),
        CandidateInvolvement.withdrawn,
      );
    });

    test('a person in no list stays unseen', () {
      expect(
        ForwardCase.computeInvolvement(
          'u1',
          _involvement(declinedOfferIds: {'u2'}),
        ),
        CandidateInvolvement.unseen,
      );
    });

    test('other states are unaffected by an unrelated declined offer', () {
      final inv = _involvement(
        declinedOfferIds: {'other'},
        helpOfferedIds: {'helper'},
        rejectedIds: {'dismisser'},
        watchingIds: {'watcher'},
        forwardedToIds: {'recipient'},
        myForwardedRecipientNotes: {'mine': 'note'},
      );
      expect(
        ForwardCase.computeInvolvement('helper', inv),
        CandidateInvolvement.helpOffered,
      );
      expect(
        ForwardCase.computeInvolvement('dismisser', inv),
        CandidateInvolvement.declined,
      );
      expect(
        ForwardCase.computeInvolvement('watcher', inv),
        CandidateInvolvement.watching,
      );
      expect(
        ForwardCase.computeInvolvement('recipient', inv),
        CandidateInvolvement.forwarded,
      );
      expect(
        ForwardCase.computeInvolvement('mine', inv),
        CandidateInvolvement.forwardedByMe,
      );
    });
  });
}
