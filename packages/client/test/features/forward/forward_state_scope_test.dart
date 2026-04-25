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
    const low = ForwardCandidate(
      profile: Profile(
        id: 'a',
        title: 'Low',
        rScore: 1,
        score: 10,
      ),
    );
    const high = ForwardCandidate(
      profile: Profile(
        id: 'b',
        title: 'High',
        rScore: 1,
        score: 90,
      ),
    );
    const blocked = ForwardCandidate(
      profile: Profile(
        id: 'c',
        title: 'Blocked',
        rScore: 1,
        score: 99,
      ),
      involvement: CandidateInvolvement.committed,
    );

    const state = ForwardState(
      candidates: [low, high, blocked],
    );

    expect(state.scopeCounts.best, 2);
    expect(state.visibleRecipients.map((c) => c.id).toList(), ['b', 'a']);
  });

  test('involved scope includes forwarded-by-others', () {
    const forwarded = ForwardCandidate(
      profile: Profile(id: 'f', title: 'F', rScore: 1, score: 50),
      involvement: CandidateInvolvement.forwarded,
    );
    const unseen = ForwardCandidate(
      profile: Profile(id: 'u', title: 'U', rScore: 1, score: 80),
    );

    const state = ForwardState(
      candidates: [forwarded, unseen],
      activeFilter: ForwardFilter.alreadyInvolved,
    );

    expect(state.scopeCounts.involved, 1);
    expect(state.visibleRecipients.single.id, 'f');
  });

  test('filterCandidatesByQuery matches profile description (MR sort)', () {
    const low = ForwardCandidate(
      profile: Profile(
        id: 'low',
        title: 'Low',
        description: 'alpha bravo',
        rScore: 1,
        score: 10,
      ),
    );
    const high = ForwardCandidate(
      profile: Profile(
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
