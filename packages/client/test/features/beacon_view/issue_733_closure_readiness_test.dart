import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #733: the plan is optional, so its steps (done or not) never gate or tick
// close readiness; and with fewer than three committed helpers nobody can
// vote, so the close action says it closes at once instead of promising an
// acknowledgement step.

final _en = lookupL10n(const Locale('en'));

BeaconDisplayStatusDto _display(int committers) => BeaconDisplayStatusDto(
  beaconId: 'b1',
  status: BeaconStatus.enoughHelp,
  phase: BeaconCoordinationPhase.coordinating,
  suggestedAction: BeaconPhasePrimaryAction.none,
  slot2Kind: BeaconPhaseSlot2Kind.none,
  tier: BeaconDisplayTier.coordination,
  everAcknowledgedCommitterCount: committers,
);

TimelineHelpOffer _committed(
  String id, {
  CommitmentStakeState stake = CommitmentStakeState.acknowledged,
}) => TimelineHelpOffer(
  user: Profile(id: id, displayName: id),
  message: '',
  createdAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2025),
  coordinationResponse: CoordinationResponseType.useful,
  stakeState: stake,
);

CoordinationItem _planStep(CoordinationItemStatus status) => CoordinationItem(
  id: 'plan1',
  beaconId: 'b1',
  kind: CoordinationItemKind.plan,
  status: status,
  creatorId: 'uAuthor',
  createdAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2025),
  title: 'Meet 10:00 at the park gate',
);

BeaconViewState _state({
  BeaconStatus status = BeaconStatus.enoughHelp,
  List<String> helpers = const ['h1', 'h2'],
  int? committers,
  CoordinationItem? plan,
  CommitmentStakeState stake = CommitmentStakeState.acknowledged,
}) => BeaconViewState(
  beacon: Beacon(
    createdAt: DateTime.utc(2025),
    updatedAt: DateTime.utc(2025),
    id: 'b1',
    title: 'T',
    author: const Profile(id: 'uAuthor', displayName: 'Author'),
    status: status,
  ),
  helpOffers: [for (final h in helpers) _committed(h, stake: stake)],
  myProfile: const Profile(id: 'uAuthor', displayName: 'Me'),
  displayStatus: committers == null ? null : _display(committers),
  openCoordinationBlocker: plan,
  beaconContextLoaded: true,
);

void main() {
  group('plan steps never gate close readiness', () {
    for (final status in [BeaconStatus.open, BeaconStatus.enoughHelp]) {
      test('${status.name}: no plan, an open step and a done step read the '
          'same', () {
        final none = buildClosureConfirmationSummary(_state(status: status));
        for (final step in [
          _planStep(CoordinationItemStatus.open),
          _planStep(CoordinationItemStatus.resolved),
        ]) {
          final withPlan = buildClosureConfirmationSummary(
            _state(status: status, plan: step),
          );
          expect(withPlan.readiness, none.readiness, reason: step.status.name);
          expect(withPlan.missingCriteria, none.missingCriteria);
          expect(withPlan.hasOpenBlocker, isFalse);
          expect(
            withPlan.hasSuccessfulHelpOfferResult,
            none.hasSuccessfulHelpOfferResult,
          );
        }
      });
    }

    test('a real open blocker still blocks (guard)', () {
      final blocker = _planStep(
        CoordinationItemStatus.open,
      ).copyWith(kind: CoordinationItemKind.blocker);
      expect(
        computeClosureReadiness(_state(plan: blocker)),
        BeaconClosureReadiness.blocked,
      );
    });
  });

  group('nobody can vote with fewer than three committed helpers', () {
    test('summary: 1 or 2 committers close without a final check', () {
      for (final n in [1, 2]) {
        final s = buildClosureConfirmationSummary(_state(committers: n));
        expect(s.requiresReviewWindow, isTrue);
        expect(s.closesWithoutFinalCheck, isTrue, reason: '$n');
      }
    });

    test('summary: 3 committers keep the final check (guard)', () {
      final s = buildClosureConfirmationSummary(
        _state(helpers: const ['h1', 'h2', 'h3'], committers: 3),
      );
      expect(s.closesWithoutFinalCheck, isFalse);
    });

    test('summary: unknown display status keeps the final-check copy', () {
      expect(
        buildClosureConfirmationSummary(_state()).closesWithoutFinalCheck,
        isFalse,
      );
    });

    test('HUD close action says it closes at once, not "acknowledge"', () {
      final spec = deriveBeaconHudAuthorActSpec(
        l10n: _en,
        state: _state(committers: 2),
      )!;
      expect(spec.action, BeaconHudAuthorAction.wrapUpForReview);
      expect(spec.effectLine, _en.beaconHudActEffectWrapUpNoVote);
      expect(spec.effectLine.toLowerCase(), isNot(contains('acknowledg')));
    });

    test('HUD close action with 3 committers still starts the final check '
        '(guard)', () {
      final spec = deriveBeaconHudAuthorActSpec(
        l10n: _en,
        state: _state(helpers: const ['h1', 'h2', 'h3'], committers: 3),
      )!;
      expect(spec.effectLine, _en.beaconHudActEffectWrapUpForReview);
    });
  });

  // Review r1 #1: the server's rule is ≥ 3 members AND someone still able to
  // vote; three helpers who all left must not be promised a final check.
  group('nobody can vote when no committed helper is still committed', () {
    const three = ['h1', 'h2', 'h3'];

    for (final stake in [
      CommitmentStakeState.exited,
      CommitmentStakeState.released,
    ]) {
      test('summary and HUD: 3 helpers, all ${stake.name}, close at once', () {
        final state = _state(helpers: three, committers: 3, stake: stake);
        expect(
          buildClosureConfirmationSummary(state).closesWithoutFinalCheck,
          isTrue,
        );
        // The HUD close action reads its effect line from this rule.
        expect(closureFinalCheckHasNoVote(state), isTrue);
      });
    }

    test('3 helpers, one still committed, keep the final check (guard)', () {
      final state = _state(helpers: three, committers: 3).copyWith(
        helpOffers: [
          _committed('h1', stake: CommitmentStakeState.exited),
          _committed('h2', stake: CommitmentStakeState.released),
          _committed('h3', stake: CommitmentStakeState.softened),
        ],
      );
      expect(
        buildClosureConfirmationSummary(state).closesWithoutFinalCheck,
        isFalse,
      );
      expect(closureFinalCheckHasNoVote(state), isFalse);
    });
  });

  test('the useful-or-done row reads as an accepted offer (EN and RU)', () {
    final ru = lookupL10n(const Locale('ru'));
    expect(_en.beaconCloseSheetEvidenceUsefulOrDone, 'An offer was accepted');
    expect(
      ru.beaconCloseSheetEvidenceUsefulOrDone,
      'Предложение помощи принято',
    );
  });

  // Review r1 nit: the RU closure copy keeps «ты» but no gendered verb.
  test('RU helper and two-member closure copy is gender-neutral', () {
    final ru = lookupL10n(const Locale('ru'));
    for (final text in [
      ru.closureHelperNothingToDecide,
      ru.closureAuthorTwoMembers,
    ]) {
      expect(text, isNot(matches(RegExp('(сделал|понял|решил)'))));
    }
  });
}
