import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/entity/lineage_suggestion_group.dart';
import 'package:tentura/features/forward/ui/bloc/forward_state.dart';

void main() {
  test('defaults to unseen scope', () {
    expect(const ForwardState().activeFilter, ForwardFilter.unseen);
  });

  test('scopeCounts and visibleRecipients for unseen (MR order)', () {
    const low = ForwardCandidate(
      profile: Profile(
        id: 'a',
        displayName: 'Low',
        rScore: 1,
        score: 10,
      ),
    );
    const high = ForwardCandidate(
      profile: Profile(
        id: 'b',
        displayName: 'High',
        rScore: 1,
        score: 90,
      ),
    );
    const blocked = ForwardCandidate(
      profile: Profile(
        id: 'c',
        displayName: 'Blocked',
        rScore: 1,
        score: 99,
      ),
      involvement: CandidateInvolvement.helpOffered,
    );

    const state = ForwardState(
      candidates: [low, high, blocked],
    );

    expect(state.scopeCounts.unseen, 2);
    expect(state.scopeCounts.involved, 1);
    expect(state.visibleRecipients.map((c) => c.id).toList(), ['b', 'a']);
  });

  test('involved scope includes forwarded-by-others', () {
    const forwarded = ForwardCandidate(
      profile: Profile(id: 'f', displayName: 'F', rScore: 1, score: 50),
      involvement: CandidateInvolvement.forwarded,
    );
    const unseen = ForwardCandidate(
      profile: Profile(id: 'u', displayName: 'U', rScore: 1, score: 80),
    );

    const state = ForwardState(
      candidates: [forwarded, unseen],
      activeFilter: ForwardFilter.alreadyInvolved,
    );

    expect(state.scopeCounts.involved, 1);
    expect(state.visibleRecipients.single.id, 'f');
  });

  test('involved scope excludes lineage-only unseen suggestions', () {
    const lineageOnly = ForwardCandidate(
      profile: Profile(id: 'lineage', displayName: 'Lineage', rScore: 1, score: 99),
      lineageGroup: LineageSuggestionGroup.involved,
    );
    const involved = ForwardCandidate(
      profile: Profile(id: 'inv', displayName: 'Inv', rScore: 1, score: 50),
      involvement: CandidateInvolvement.forwardedByMe,
    );

    const state = ForwardState(
      candidates: [involved],
      lineageSuggestions: [lineageOnly],
      activeFilter: ForwardFilter.alreadyInvolved,
    );

    expect(state.scopeCounts.involved, 1);
    expect(state.visibleRecipients.map((c) => c.id).toList(), ['inv']);
  });

  test('involved scope includes candidate also listed as lineage suggestion', () {
    const shared = ForwardCandidate(
      profile: Profile(id: 'shared', displayName: 'Shared', rScore: 1, score: 60),
      involvement: CandidateInvolvement.forwardedByMe,
    );
    const lineageDup = ForwardCandidate(
      profile: Profile(id: 'shared', displayName: 'Shared', rScore: 1, score: 60),
      lineageGroup: LineageSuggestionGroup.involved,
    );

    const state = ForwardState(
      candidates: [shared],
      lineageSuggestions: [lineageDup],
      activeFilter: ForwardFilter.alreadyInvolved,
    );

    expect(state.visibleRecipients.single.id, 'shared');
    expect(state.visibleRecipients.single.involvement,
        CandidateInvolvement.forwardedByMe);
    expect(state.visibleRecipients.single.lineageGroup, isNull);
  });

  test('filterCandidatesByQuery matches profile description (MR sort)', () {
    const low = ForwardCandidate(
      profile: Profile(
        id: 'low',
        displayName: 'Low',
        description: 'alpha bravo',
        rScore: 1,
        score: 10,
      ),
    );
    const high = ForwardCandidate(
      profile: Profile(
        id: 'high',
        displayName: 'High',
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
