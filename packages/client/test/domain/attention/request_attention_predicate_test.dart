import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_state.dart';

RequestAttentionFacts _facts({
  String id = 'R1',
  int optional = 0,
  int outcomes = 0,
  int obligations = 0,
  bool pendingForward = false,
  bool pendingPrompt = false,
  bool archived = false,
}) => RequestAttentionFacts(
  requestId: id,
  unclearedOptionalEvents: optional,
  unclearedOutcomes: outcomes,
  liveObligations: obligations,
  pendingForward: pendingForward,
  pendingPrompt: pendingPrompt,
  viewerArchived: archived,
);

/// Every distinguishable shape a Request can present to the rule, crossed with
/// the archive axis. Small enough to enumerate, which is the point: the M1
/// invariant is asserted over the whole space, not over three handpicked rows.
Iterable<RequestAttentionFacts> _stateSpace() sync* {
  var n = 0;
  for (final optional in [0, 1, 2]) {
    for (final outcomes in [0, 1]) {
      for (final obligations in [0, 1, 3]) {
        for (final archived in [false, true]) {
          for (final pendingForward in [false, true]) {
            yield _facts(
              id: 'R${n++}',
              optional: optional,
              outcomes: outcomes,
              obligations: obligations,
              archived: archived,
              pendingForward: pendingForward,
            );
          }
        }
      }
    }
  }
}

/// A *forked* copy of the My Desk rule: identical name-for-name, but it forgets
/// the reachability half — archived Requests are counted although the surface's
/// default filter hides them. This is the shape of the divergence M1 forbids,
/// and the invariant tests below are re-run against it to prove they notice.
List<RequestAttentionFacts> _forkedMembers(
  Iterable<RequestAttentionFacts> requests, {
  Set<MyDeskAttentionFilter> exposedFilters = myDeskExposedFilters,
}) => [
  for (final r in requests)
    if (requestHasMyDeskAttention(r)) r,
];

MyWorkCardViewModel _card(RequestAttentionFacts r) {
  final beacon = Beacon.empty.copyWith(
    id: r.requestId,
    updatedAt: DateTime(2026),
    status: BeaconStatus.open,
  );
  return MyWorkCardViewModel(
    beaconId: r.requestId,
    role: MyWorkCardRole.authored,
    kind: r.viewerArchived
        ? MyWorkCardKind.obligationArchived
        : MyWorkCardKind.authoredActive,
    beacon: beacon,
    viewerArchived: r.viewerArchived,
  );
}

/// The desk filter each declared `MyDeskAttentionFilter` actually resolves to.
/// Binding the enum to the real filter here is what makes the reachability
/// assertion load-bearing: a mapping that lies is a list that cannot show what
/// the indicator counted.
const _realDeskFilter = {
  MyDeskAttentionFilter.active: MyWorkFilter.active,
  MyDeskAttentionFilter.archive: MyWorkFilter.archived,
};

/// The real desk list, asked through exactly the filters the surface offers.
Set<String> _reachableThroughRealFilters(
  Iterable<RequestAttentionFacts> rs, {
  Set<MyDeskAttentionFilter> exposedFilters = myDeskExposedFilters,
}) {
  final nonArchived = [for (final r in rs) if (!r.viewerArchived) _card(r)];
  final archived = [for (final r in rs) if (r.viewerArchived) _card(r)];
  return {
    for (final filter in exposedFilters.map((f) => _realDeskFilter[f]!))
      for (final c in filterMyWorkCardsForDesk(
        filter: filter,
        nonArchivedCards: nonArchived,
        archivedCards: archived,
      ))
        c.beaconId,
  };
}

void main() {
  group('D09 — dot and count are independent', () {
    test('a Request with both shows both', () {
      final r = _facts(optional: 1, obligations: 2);
      expect(requestHasDot(r), isTrue);
      expect(requestCount(r), 2);

      final indicators = myDeskIndicators([r]);
      expect(indicators.dot, isTrue, reason: 'the count must not hide the dot');
      expect(indicators.count, 2, reason: 'the dot must not hide the count');
    });

    test('an uncleared outcome alone is a dot, with no number', () {
      final indicators = myDeskIndicators([_facts(outcomes: 1)]);
      expect(indicators.dot, isTrue);
      expect(indicators.count, 0);
    });

    test('obligations alone are a number, with no dot', () {
      final indicators = myDeskIndicators([_facts(obligations: 4)]);
      expect(indicators.dot, isFalse);
      expect(indicators.count, 4);
    });

    test('the number counts obligations, not Request cards', () {
      final indicators = myDeskIndicators([
        _facts(id: 'A', obligations: 3),
        _facts(id: 'B', obligations: 2),
      ]);
      expect(indicators.count, 5);
    });

    test('one Request may carry the dot while another carries the number', () {
      final indicators = myDeskIndicators([
        _facts(id: 'A', optional: 1),
        _facts(id: 'B', obligations: 2),
      ]);
      expect(indicators.dot, isTrue);
      expect(indicators.count, 2);
    });

    test('For You never has a count', () {
      final indicators = forYouIndicators([
        _facts(optional: 1, obligations: 9, pendingForward: true),
      ]);
      expect(indicators.dot, isTrue);
      expect(indicators.count, 0);
      expect(indicators.hasCount, isFalse);
    });

    test('a pending forward alone lights For You but not My Desk', () {
      final r = _facts(pendingForward: true);
      expect(forYouIndicators([r]).dot, isTrue);
      expect(myDeskIndicators([r]).isLit, isFalse);
    });

    test('a pending prompt alone lights For You', () {
      expect(forYouIndicators([_facts(pendingPrompt: true)]).dot, isTrue);
    });
  });

  group('M1 — one predicate, not two', () {
    test('a lit My Desk indicator always has a non-empty list behind it', () {
      for (final r in _stateSpace()) {
        final members = myDeskAttentionMembers([r]);
        final indicators = indicatorsFromMembers(members);
        if (indicators.isLit) {
          expect(
            members,
            isNotEmpty,
            reason: 'lit tab over an empty list for ${r.requestId}',
          );
        }
        expect(
          indicators.isLit,
          members.isNotEmpty,
          reason: 'indicator and list must agree for ${r.requestId}',
        );
      }
    });

    test('a lit For You indicator always has a non-empty list behind it', () {
      for (final r in _stateSpace()) {
        final members = forYouAttentionMembers([r]);
        expect(forYouIndicators([r]).dot, members.isNotEmpty);
      }
    });

    test(
      'everything My Desk counts is reachable through a real desk filter',
      () {
        final all = _stateSpace().toList();
        for (final exposed in const [
          myDeskExposedFilters,
          {MyDeskAttentionFilter.active},
          {MyDeskAttentionFilter.archive},
        ]) {
          final counted = {
            for (final r in myDeskAttentionMembers(
              all,
              exposedFilters: exposed,
            ))
              r.requestId,
          };
          final reachable = _reachableThroughRealFilters(
            all,
            exposedFilters: exposed,
          );
          expect(
            counted.difference(reachable),
            isEmpty,
            reason: 'counted but no desk filter in $exposed shows it',
          );
        }
      },
    );

    test('an archived Request is counted only because Archive exposes it', () {
      final archived = _facts(id: 'ARCH', optional: 1, archived: true);

      // Archive is offered, so the attention is reachable and contributes.
      expect(myDeskIndicators([archived]).dot, isTrue);
      expect(
        _reachableThroughRealFilters([archived]),
        contains('ARCH'),
        reason: 'the Archive filter must actually expose it',
      );

      // Take the Archive filter away and it contributes to neither (§6).
      final withoutArchive = myDeskIndicators(
        [archived],
        exposedFilters: const {MyDeskAttentionFilter.active},
      );
      expect(withoutArchive.isLit, isFalse);
      expect(
        myDeskAttentionMembers(
          [archived],
          exposedFilters: const {MyDeskAttentionFilter.active},
        ),
        isEmpty,
      );
    });

    test('the invariant tests fail when the two rules are forked', () {
      // The fork keeps the name and drops the reachability half. Without the
      // Archive filter, its members include a row no list would show — which is
      // exactly the "lit tab, empty list" the invariant above asserts against.
      final archived = _facts(id: 'ARCH', optional: 1, archived: true);
      const activeOnly = {MyDeskAttentionFilter.active};

      final real = myDeskAttentionMembers(
        [archived],
        exposedFilters: activeOnly,
      );
      final forked = _forkedMembers([archived], exposedFilters: activeOnly);

      expect(real, isEmpty);
      expect(
        forked,
        isNotEmpty,
        reason: 'the fork must actually diverge, or this proves nothing',
      );
      expect(
        indicatorsFromMembers(forked).isLit,
        isTrue,
        reason: 'the forked rule lights a tab whose list is empty',
      );
      expect(
        indicatorsFromMembers(forked).isLit == real.isNotEmpty,
        isFalse,
        reason: 'the M1 equality the real rule holds is broken by the fork',
      );
    });

    test('indicators are computed from members, never from raw facts', () {
      // Membership is the only door: a Request the list excluded cannot reach
      // the indicator, whatever its facts say.
      final excluded = _facts(id: 'X', optional: 5, obligations: 5);
      expect(indicatorsFromMembers(const []).isLit, isFalse);
      expect(indicatorsFromMembers([excluded]).isLit, isTrue);
    });
  });

  group('indicators do not depend on which tab is open', () {
    test('the rule takes no tab input at all', () {
      final requests = [_facts(optional: 1, obligations: 2)];
      // Called twice with identical inputs — there is no third argument a
      // caller could pass to make an indicator disappear.
      expect(myDeskIndicators(requests), myDeskIndicators(requests));
      expect(myDeskIndicators(requests).dot, isTrue);
      expect(myDeskIndicators(requests).count, 2);
    });

    test('surface totals carry the same rule one level up', () {
      expect(surfaceDotFromTotal(0), isFalse);
      expect(surfaceDotFromTotal(1), isTrue);
      expect(surfaceCountFromTotal(0), 0);
      expect(surfaceCountFromTotal(3), 3);
    });
  });
}
