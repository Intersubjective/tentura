import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/model/person_action_policy.dart';

Profile _profile({
  int myVote = 0,
  double score = 0,
  bool subjectExplicitlyTrustsViewer = false,
  double rScore = 0,
}) => Profile(
  id: 'peer',
  displayName: 'Peer',
  myVote: myVote,
  score: score,
  subjectExplicitlyTrustsViewer: subjectExplicitlyTrustsViewer,
  rScore: rScore,
);

PersonVisibilityState _expectedVisibility(Profile profile) {
  if (profile.isMutuallyVisible) return PersonVisibilityState.mutual;
  if (profile.viewerCanSeeSubject && !profile.subjectCanSeeViewer) {
    return PersonVisibilityState.viewerOnly;
  }
  if (!profile.viewerCanSeeSubject && profile.subjectCanSeeViewer) {
    return PersonVisibilityState.subjectOnly;
  }
  return PersonVisibilityState.neither;
}

PersonPrimaryAction _expectedPrimary(
  Profile profile, {
  required bool isSelf,
  required bool isBlocked,
}) {
  if (isSelf || isBlocked) return PersonPrimaryAction.none;
  if (profile.isMutuallyVisible) return PersonPrimaryAction.sendRequest;
  if (!profile.viewerExplicitlyTrustsSubject) return PersonPrimaryAction.trust;
  return PersonPrimaryAction.none;
}

void main() {
  group('PersonActionPolicy — sixteen trust/MR mechanism rows', () {
    final cases =
        <
          ({
            bool tOut,
            bool mrOut,
            bool tIn,
            bool mrIn,
          })
        >[
          (tOut: false, mrOut: false, tIn: false, mrIn: false),
          (tOut: false, mrOut: false, tIn: false, mrIn: true),
          (tOut: false, mrOut: false, tIn: true, mrIn: false),
          (tOut: false, mrOut: false, tIn: true, mrIn: true),
          (tOut: false, mrOut: true, tIn: false, mrIn: false),
          (tOut: false, mrOut: true, tIn: false, mrIn: true),
          (tOut: false, mrOut: true, tIn: true, mrIn: false),
          (tOut: false, mrOut: true, tIn: true, mrIn: true),
          (tOut: true, mrOut: false, tIn: false, mrIn: false),
          (tOut: true, mrOut: false, tIn: false, mrIn: true),
          (tOut: true, mrOut: false, tIn: true, mrIn: false),
          (tOut: true, mrOut: false, tIn: true, mrIn: true),
          (tOut: true, mrOut: true, tIn: false, mrIn: false),
          (tOut: true, mrOut: true, tIn: false, mrIn: true),
          (tOut: true, mrOut: true, tIn: true, mrIn: false),
          (tOut: true, mrOut: true, tIn: true, mrIn: true),
        ];

    for (final c in cases) {
      test('T→=${c.tOut} MR→=${c.mrOut} T←=${c.tIn} MR←=${c.mrIn}', () {
        final profile = _profile(
          myVote: c.tOut ? 1 : 0,
          score: c.mrOut ? 1 : 0,
          subjectExplicitlyTrustsViewer: c.tIn,
          rScore: c.mrIn ? 1 : 0,
        );
        final policy = PersonActionPolicy.from(
          profile,
          isSelf: false,
          isBlocked: false,
        );

        expect(policy.viewerExplicitlyTrustsSubject, c.tOut);
        expect(policy.subjectExplicitlyTrustsViewer, c.tIn);
        expect(policy.viewerCanSeeSubject, c.tOut || c.mrOut);
        expect(policy.subjectCanSeeViewer, c.tIn || c.mrIn);
        expect(policy.visibilityState, _expectedVisibility(profile));
        expect(policy.isMutuallyVisible, profile.isMutuallyVisible);
        expect(
          policy.canDirectSendRequest,
          profile.isMutuallyVisible,
        );
        expect(
          policy.primaryAction,
          _expectedPrimary(profile, isSelf: false, isBlocked: false),
        );
        expect(
          policy.showSecondaryTrust,
          profile.isMutuallyVisible && !profile.viewerExplicitlyTrustsSubject,
        );
        expect(policy.showRequestOptions, !profile.isMutuallyVisible);
      });
    }
  });

  group('PersonActionPolicy — self and blocked', () {
    test('self suppresses all actions', () {
      final profile = _profile(score: 1, rScore: 1);
      final policy = PersonActionPolicy.from(
        profile,
        isSelf: true,
        isBlocked: false,
      );

      expect(policy.primaryAction, PersonPrimaryAction.none);
      expect(policy.showSecondaryTrust, isFalse);
      expect(policy.showRequestOptions, isFalse);
      expect(policy.canDirectSendRequest, isFalse);
    });

    test('blocked suppresses all actions', () {
      final profile = _profile(score: 1, rScore: 1);
      final policy = PersonActionPolicy.from(
        profile,
        isSelf: false,
        isBlocked: true,
      );

      expect(policy.primaryAction, PersonPrimaryAction.none);
      expect(policy.showSecondaryTrust, isFalse);
      expect(policy.showRequestOptions, isFalse);
      expect(policy.canDirectSendRequest, isFalse);
    });
  });

  group('PersonActionPolicy — transition regressions', () {
    test('subject-only visibility + Trust → mutual → Send primary', () {
      final before = _profile(rScore: 1);
      final beforePolicy = PersonActionPolicy.from(
        before,
        isSelf: false,
        isBlocked: false,
      );
      expect(beforePolicy.visibilityState, PersonVisibilityState.subjectOnly);
      expect(beforePolicy.primaryAction, PersonPrimaryAction.trust);

      final after = before.copyWith(myVote: 1);
      final afterPolicy = PersonActionPolicy.from(
        after,
        isSelf: false,
        isBlocked: false,
      );
      expect(afterPolicy.visibilityState, PersonVisibilityState.mutual);
      expect(afterPolicy.primaryAction, PersonPrimaryAction.sendRequest);
      expect(after.viewerExplicitlyTrustsSubject, isTrue);
    });

    test('neither visibility + Trust → viewer-only → no Send primary', () {
      final before = _profile();
      final beforePolicy = PersonActionPolicy.from(
        before,
        isSelf: false,
        isBlocked: false,
      );
      expect(beforePolicy.visibilityState, PersonVisibilityState.neither);
      expect(beforePolicy.primaryAction, PersonPrimaryAction.trust);

      final after = before.copyWith(myVote: 1);
      final afterPolicy = PersonActionPolicy.from(
        after,
        isSelf: false,
        isBlocked: false,
      );
      expect(afterPolicy.visibilityState, PersonVisibilityState.viewerOnly);
      expect(afterPolicy.primaryAction, PersonPrimaryAction.none);
      expect(afterPolicy.showRequestOptions, isTrue);
      expect(afterPolicy.canDirectSendRequest, isFalse);
    });

    test(
      'viewer-only with outgoing trust already set → no misleading Trust CTA',
      () {
        final profile = _profile(myVote: 1, score: 1);
        final policy = PersonActionPolicy.from(
          profile,
          isSelf: false,
          isBlocked: false,
        );

        expect(policy.visibilityState, PersonVisibilityState.viewerOnly);
        expect(policy.primaryAction, PersonPrimaryAction.none);
        expect(policy.showRequestOptions, isTrue);
        expect(policy.showSecondaryTrust, isFalse);
      },
    );

    test(
      'mutual MR without outgoing trust → Send primary + secondary Trust',
      () {
        final profile = _profile(score: 1, rScore: 1);
        final policy = PersonActionPolicy.from(
          profile,
          isSelf: false,
          isBlocked: false,
        );

        expect(policy.isMutuallyVisible, isTrue);
        expect(policy.viewerExplicitlyTrustsSubject, isFalse);
        expect(policy.primaryAction, PersonPrimaryAction.sendRequest);
        expect(policy.showSecondaryTrust, isTrue);
        expect(policy.showRequestOptions, isFalse);
      },
    );
  });

  group('PersonActionPolicy — reachability does not imply explicit trust', () {
    test('positive MeritRank visibility keeps explicit-trust flags false', () {
      final profile = _profile(score: 1, rScore: 1);
      final policy = PersonActionPolicy.from(
        profile,
        isSelf: false,
        isBlocked: false,
      );

      expect(policy.viewerExplicitlyTrustsSubject, isFalse);
      expect(policy.subjectExplicitlyTrustsViewer, isFalse);
      expect(policy.isMutuallyVisible, isTrue);
      expect(policy.canDirectSendRequest, isTrue);
    });
  });
}
