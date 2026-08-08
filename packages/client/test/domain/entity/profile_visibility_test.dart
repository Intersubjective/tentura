import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';

Profile _profile({
  int myVote = 0,
  double score = 0,
  bool subjectExplicitlyTrustsViewer = false,
  double rScore = 0,
  bool isMutualFriend = false,
}) => Profile(
  id: 'p',
  myVote: myVote,
  score: score,
  subjectExplicitlyTrustsViewer: subjectExplicitlyTrustsViewer,
  rScore: rScore,
  isMutualFriend: isMutualFriend,
);

void main() {
  group('canonical visibility getters — sixteen signal combinations', () {
    final cases =
        <
          ({
            bool tOut,
            bool mrOut,
            bool tIn,
            bool mrIn,
            bool viewerSeesSubject,
            bool subjectSeesViewer,
            bool mutual,
          })
        >[
          (
            tOut: false,
            mrOut: false,
            tIn: false,
            mrIn: false,
            viewerSeesSubject: false,
            subjectSeesViewer: false,
            mutual: false,
          ),
          (
            tOut: false,
            mrOut: false,
            tIn: false,
            mrIn: true,
            viewerSeesSubject: false,
            subjectSeesViewer: true,
            mutual: false,
          ),
          (
            tOut: false,
            mrOut: false,
            tIn: true,
            mrIn: false,
            viewerSeesSubject: false,
            subjectSeesViewer: true,
            mutual: false,
          ),
          (
            tOut: false,
            mrOut: false,
            tIn: true,
            mrIn: true,
            viewerSeesSubject: false,
            subjectSeesViewer: true,
            mutual: false,
          ),
          (
            tOut: false,
            mrOut: true,
            tIn: false,
            mrIn: false,
            viewerSeesSubject: true,
            subjectSeesViewer: false,
            mutual: false,
          ),
          (
            tOut: false,
            mrOut: true,
            tIn: false,
            mrIn: true,
            viewerSeesSubject: true,
            subjectSeesViewer: true,
            mutual: true,
          ),
          (
            tOut: false,
            mrOut: true,
            tIn: true,
            mrIn: false,
            viewerSeesSubject: true,
            subjectSeesViewer: true,
            mutual: true,
          ),
          (
            tOut: false,
            mrOut: true,
            tIn: true,
            mrIn: true,
            viewerSeesSubject: true,
            subjectSeesViewer: true,
            mutual: true,
          ),
          (
            tOut: true,
            mrOut: false,
            tIn: false,
            mrIn: false,
            viewerSeesSubject: true,
            subjectSeesViewer: false,
            mutual: false,
          ),
          (
            tOut: true,
            mrOut: false,
            tIn: false,
            mrIn: true,
            viewerSeesSubject: true,
            subjectSeesViewer: true,
            mutual: true,
          ),
          (
            tOut: true,
            mrOut: false,
            tIn: true,
            mrIn: false,
            viewerSeesSubject: true,
            subjectSeesViewer: true,
            mutual: true,
          ),
          (
            tOut: true,
            mrOut: false,
            tIn: true,
            mrIn: true,
            viewerSeesSubject: true,
            subjectSeesViewer: true,
            mutual: true,
          ),
          (
            tOut: true,
            mrOut: true,
            tIn: false,
            mrIn: false,
            viewerSeesSubject: true,
            subjectSeesViewer: false,
            mutual: false,
          ),
          (
            tOut: true,
            mrOut: true,
            tIn: false,
            mrIn: true,
            viewerSeesSubject: true,
            subjectSeesViewer: true,
            mutual: true,
          ),
          (
            tOut: true,
            mrOut: true,
            tIn: true,
            mrIn: false,
            viewerSeesSubject: true,
            subjectSeesViewer: true,
            mutual: true,
          ),
          (
            tOut: true,
            mrOut: true,
            tIn: true,
            mrIn: true,
            viewerSeesSubject: true,
            subjectSeesViewer: true,
            mutual: true,
          ),
        ];

    for (final c in cases) {
      test(
        'T→=${c.tOut} MR→=${c.mrOut} T←=${c.tIn} MR←=${c.mrIn}',
        () {
          final profile = _profile(
            myVote: c.tOut ? 1 : 0,
            score: c.mrOut ? 1 : 0,
            subjectExplicitlyTrustsViewer: c.tIn,
            rScore: c.mrIn ? 1 : 0,
          );

          expect(profile.viewerExplicitlyTrustsSubject, c.tOut);
          expect(profile.forwardMeritRankPositive, c.mrOut);
          expect(profile.reverseMeritRankPositive, c.mrIn);
          expect(profile.viewerCanSeeSubject, c.viewerSeesSubject);
          expect(profile.subjectCanSeeViewer, c.subjectSeesViewer);
          expect(profile.isMutuallyVisible, c.mutual);
        },
      );
    }
  });

  group('score boundary values', () {
    test('zero and negative MeritRank scores are not positive', () {
      expect(
        _profile(score: 0, rScore: 0).isMutuallyVisible,
        isFalse,
      );
      expect(
        _profile(score: -1, rScore: -1).isMutuallyVisible,
        isFalse,
      );
      expect(
        _profile(score: 0, rScore: 1).isMutuallyVisible,
        isFalse,
      );
      expect(
        _profile(score: 1, rScore: 0).isMutuallyVisible,
        isFalse,
      );
    });

    test('zero myVote is not outgoing explicit trust', () {
      final profile = _profile(myVote: 0, score: 1);
      expect(profile.viewerExplicitlyTrustsSubject, isFalse);
      expect(profile.isFriend, isFalse);
    });
  });

  group('reachability and alias semantics', () {
    test('explicit mutual trust is mutual with non-positive MeritRank', () {
      final profile = _profile(
        myVote: 1,
        subjectExplicitlyTrustsViewer: true,
        score: 0,
        rScore: 0,
      );
      expect(profile.isMutuallyVisible, isTrue);
    });

    test('positive MeritRank both ways is mutual without trust', () {
      final profile = _profile(score: 0.5, rScore: 2);
      expect(profile.isMutuallyVisible, isTrue);
      expect(profile.viewerExplicitlyTrustsSubject, isFalse);
      expect(profile.subjectCanSeeViewer, isTrue);
    });

    test('mixed trust and MeritRank cases are mutual', () {
      expect(
        _profile(
          myVote: 1,
          subjectExplicitlyTrustsViewer: false,
          score: 0,
          rScore: 1,
        ).isMutuallyVisible,
        isTrue,
      );
      expect(
        _profile(
          myVote: 0,
          subjectExplicitlyTrustsViewer: true,
          score: 1,
          rScore: 0,
        ).isMutuallyVisible,
        isTrue,
      );
    });

    test('one-way visibility keeps the eye closed', () {
      expect(
        _profile(myVote: 1, score: 1).isMutuallyVisible,
        isFalse,
      );
      expect(
        _profile(
          subjectExplicitlyTrustsViewer: true,
          rScore: 1,
        ).isMutuallyVisible,
        isFalse,
      );
    });

    test('isMutualFriend is strict reciprocal explicit trust only', () {
      final profile = _profile(
        myVote: 1,
        subjectExplicitlyTrustsViewer: false,
        isMutualFriend: true,
      );
      expect(profile.isMutualFriend, isTrue);
      expect(profile.subjectCanSeeViewer, isFalse);
      expect(profile.isMutuallyVisible, isFalse);
    });

    test('isSeeingMe is reverse MeritRank only', () {
      expect(_profile(rScore: 1).isSeeingMe, isTrue);
      expect(_profile(subjectExplicitlyTrustsViewer: true).isSeeingMe, isFalse);
      expect(_profile(score: 5).isSeeingMe, isFalse);
    });

    test('isFriend aliases outgoing explicit trust', () {
      expect(_profile(myVote: 1).isFriend, isTrue);
      expect(_profile(myVote: 1).viewerExplicitlyTrustsSubject, isTrue);
      expect(_profile(myVote: 0).isNotFriend, isTrue);
    });
  });
}
