import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';

BeaconInvolvementData _involvement({
  String authorId = 'author',
  Set<String> forwardedToIds = const {},
  Set<String> helpOfferedIds = const {},
  Set<String> withdrawnIds = const {},
  Set<String> rejectedIds = const {},
  Set<String> watchingIds = const {},
  Set<String> onwardForwarderIds = const {},
  Map<String, String> myForwardedRecipientNotes = const {},
}) =>
    (
      beacon: Beacon.empty.copyWith(author: Profile(id: authorId)),
      forwardedToIds: forwardedToIds,
      helpOfferedIds: helpOfferedIds,
      withdrawnIds: withdrawnIds,
      rejectedIds: rejectedIds,
      watchingIds: watchingIds,
      onwardForwarderIds: onwardForwarderIds,
      myForwardedRecipientNotes: myForwardedRecipientNotes,
      myForwardedRecipientEdgeIds: const {},
      myForwardedRecipientReadAts: const {},
    );

void main() {
  group('ForwardCase.computeInvolvement', () {
    test('author', () {
      const userId = 'author';
      final inv = _involvement(authorId: userId);
      expect(
        ForwardCase.computeInvolvement(userId, inv),
        CandidateInvolvement.author,
      );
    });

    test('helpOffered', () {
      const userId = 'u1';
      final inv = _involvement(helpOfferedIds: {userId});
      expect(
        ForwardCase.computeInvolvement(userId, inv),
        CandidateInvolvement.helpOffered,
      );
    });

    test('withdrawn', () {
      const userId = 'u1';
      final inv = _involvement(withdrawnIds: {userId});
      expect(
        ForwardCase.computeInvolvement(userId, inv),
        CandidateInvolvement.withdrawn,
      );
    });

    test('forwardedByMe from myForwardedRecipientNotes', () {
      const userId = 'u1';
      final inv = _involvement(myForwardedRecipientNotes: {userId: 'note'});
      expect(
        ForwardCase.computeInvolvement(userId, inv),
        CandidateInvolvement.forwardedByMe,
      );
    });

    test('declined from rejectedIds', () {
      const userId = 'u1';
      final inv = _involvement(rejectedIds: {userId});
      expect(
        ForwardCase.computeInvolvement(userId, inv),
        CandidateInvolvement.declined,
      );
    });

    test('forwarded from onwardForwarderIds', () {
      const userId = 'u1';
      final inv = _involvement(onwardForwarderIds: {userId});
      expect(
        ForwardCase.computeInvolvement(userId, inv),
        CandidateInvolvement.forwarded,
      );
    });

    test('forwarded from forwardedToIds', () {
      const userId = 'u1';
      final inv = _involvement(forwardedToIds: {userId});
      expect(
        ForwardCase.computeInvolvement(userId, inv),
        CandidateInvolvement.forwarded,
      );
    });

    test('watching', () {
      const userId = 'u1';
      final inv = _involvement(watchingIds: {userId});
      expect(
        ForwardCase.computeInvolvement(userId, inv),
        CandidateInvolvement.watching,
      );
    });

    test('unseen when no involvement signals', () {
      const userId = 'u1';
      final inv = _involvement();
      expect(
        ForwardCase.computeInvolvement(userId, inv),
        CandidateInvolvement.unseen,
      );
    });

    test('author beats all lower-priority signals', () {
      const userId = 'author';
      final inv = _involvement(
        authorId: userId,
        helpOfferedIds: {userId},
        withdrawnIds: {userId},
        myForwardedRecipientNotes: {userId: 'note'},
        rejectedIds: {userId},
        onwardForwarderIds: {userId},
        watchingIds: {userId},
        forwardedToIds: {userId},
      );
      expect(
        ForwardCase.computeInvolvement(userId, inv),
        CandidateInvolvement.author,
      );
    });

    test('helpOffered beats withdrawn and below', () {
      const userId = 'u1';
      final inv = _involvement(
        helpOfferedIds: {userId},
        withdrawnIds: {userId},
        myForwardedRecipientNotes: {userId: 'note'},
        rejectedIds: {userId},
        onwardForwarderIds: {userId},
        watchingIds: {userId},
        forwardedToIds: {userId},
      );
      expect(
        ForwardCase.computeInvolvement(userId, inv),
        CandidateInvolvement.helpOffered,
      );
    });

    test('forwardedByMe wins over forwardedToIds overlap', () {
      const userId = 'u1';
      final inv = _involvement(
        forwardedToIds: {userId},
        myForwardedRecipientNotes: {userId: 'sent by me'},
      );
      expect(
        ForwardCase.computeInvolvement(userId, inv),
        CandidateInvolvement.forwardedByMe,
      );
    });

    test('watching beats forwardedToIds', () {
      const userId = 'u1';
      final inv = _involvement(
        watchingIds: {userId},
        forwardedToIds: {userId},
      );
      expect(
        ForwardCase.computeInvolvement(userId, inv),
        CandidateInvolvement.watching,
      );
    });
  });
}
