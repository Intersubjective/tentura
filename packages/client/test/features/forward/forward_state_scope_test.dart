import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_state.dart';

void main() {
  test('defaults to bestNext scope', () {
    expect(const ForwardState().activeFilter, ForwardFilter.bestNext);
  });

  test('scopeCounts and visibleRecipients for bestNext (MR order)', () {
    final low = ForwardCandidate(
      profile: const Profile(
        id: 'a',
        title: 'Low',
        rScore: 1,
        score: 10,
      ),
    );
    final high = ForwardCandidate(
      profile: const Profile(
        id: 'b',
        title: 'High',
        rScore: 1,
        score: 90,
      ),
    );
    final blocked = ForwardCandidate(
      profile: const Profile(
        id: 'c',
        title: 'Blocked',
        rScore: 1,
        score: 99,
      ),
      involvement: CandidateInvolvement.committed,
    );

    final state = ForwardState(
      candidates: [low, high, blocked],
      activeFilter: ForwardFilter.bestNext,
    );

    expect(state.scopeCounts.best, 2);
    expect(state.visibleRecipients.map((c) => c.id).toList(), ['b', 'a']);
  });

  test('involved scope includes forwarded-by-others', () {
    final forwarded = ForwardCandidate(
      profile: const Profile(id: 'f', title: 'F', rScore: 1, score: 50),
      involvement: CandidateInvolvement.forwarded,
    );
    final unseen = ForwardCandidate(
      profile: const Profile(id: 'u', title: 'U', rScore: 1, score: 80),
    );

    final state = ForwardState(
      candidates: [forwarded, unseen],
      activeFilter: ForwardFilter.alreadyInvolved,
    );

    expect(state.scopeCounts.involved, 1);
    expect(state.visibleRecipients.single.id, 'f');
  });

  test('filterCandidatesByQuery matches profile description (MR sort)', () {
    final low = ForwardCandidate(
      profile: const Profile(
        id: 'low',
        title: 'Low',
        description: 'alpha bravo',
        rScore: 1,
        score: 10,
      ),
    );
    final high = ForwardCandidate(
      profile: const Profile(
        id: 'high',
        title: 'High',
        description: 'alpha bravo',
        rScore: 1,
        score: 90,
      ),
    );
    final filtered = ForwardState.filterCandidatesByQuery(
      [low, high],
      'bravo',
    );

    expect(filtered.map((c) => c.id).toList(), ['high', 'low']);
  });
}
