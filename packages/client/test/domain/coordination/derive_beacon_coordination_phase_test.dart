import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/coordination/beacon_coordination_phase_input.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/coordination/beacon_has_unreviewed_offers.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';

final _t = DateTime.utc(2026, 6, 20, 12);

Beacon _beacon({
  BeaconLifecycle lifecycle = BeaconLifecycle.open,
  BeaconCoordinationStatus coordinationStatus = BeaconCoordinationStatus.neutral,
  int helpOfferCount = 0,
  int publicStatus = 0,
}) =>
    Beacon.empty.copyWith(
      id: 'b1',
      title: 'Test',
      lifecycle: lifecycle,
      coordinationStatus: coordinationStatus,
      helpOfferCount: helpOfferCount,
      publicStatus: publicStatus,
      createdAt: _t,
      updatedAt: _t,
    );

void main() {
  test('authored open neutral with offers is offersAwaitingAuthor', () {
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: _beacon(helpOfferCount: 3),
        tier: BeaconVisibilityTier.coordination,
        now: _t,
        hasUnreviewedOffers: beaconHasUnreviewedOffers(
          _beacon(helpOfferCount: 3),
        ),
      ),
    );
    expect(result.phase, BeaconCoordinationPhase.offersAwaitingAuthor);
    expect(result.slot2Kind, BeaconPhaseSlot2Kind.freshness);
    expect(result.suggestedAction, BeaconPhasePrimaryAction.reviewOffers);
    expect(result.rowHarmony.suppressYouAwaitingAuthor, isTrue);
  });

  test('offersAwaitingAuthor with stale activity uses freshness quiet days', () {
    final now = DateTime.utc(2026, 6, 20, 12);
    final updatedAt = now.subtract(const Duration(days: 3));
    final beacon = _beacon(helpOfferCount: 2).copyWith(updatedAt: updatedAt);
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: beacon,
        tier: BeaconVisibilityTier.coordination,
        now: now,
        hasUnreviewedOffers: beaconHasUnreviewedOffers(beacon),
      ),
    );
    expect(result.phase, BeaconCoordinationPhase.offersAwaitingAuthor);
    expect(result.slot2Kind, BeaconPhaseSlot2Kind.freshness);
    expect(result.lastActivityAt, updatedAt);
  });

  test('open neutral zero offers is lookingForHelpers', () {
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: _beacon(),
        tier: BeaconVisibilityTier.coordination,
        now: _t,
      ),
    );
    expect(result.phase, BeaconCoordinationPhase.lookingForHelpers);
    expect(result.slot2Kind, BeaconPhaseSlot2Kind.noOffersYet);
  });

  test('blocked phase when open blocker present', () {
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: _beacon(),
        tier: BeaconVisibilityTier.coordination,
        now: _t,
        hasOpenBlocker: true,
      ),
    );
    expect(result.phase, BeaconCoordinationPhase.blocked);
    expect(result.slot2Kind, BeaconPhaseSlot2Kind.blockerNeedsClearing);
    expect(result.rowHarmony.showBlockedTitleInNowSubline, isTrue);
  });

  test('public tier never exposes offersAwaitingAuthor', () {
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: _beacon(helpOfferCount: 2),
        tier: BeaconVisibilityTier.public,
        now: _t,
        hasUnreviewedOffers: true,
      ),
    );
    expect(result.phase, isNot(BeaconCoordinationPhase.offersAwaitingAuthor));
    expect(result.phase, BeaconCoordinationPhase.coordinating);
  });

  test('draft lifecycle maps to draft phase', () {
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: _beacon(lifecycle: BeaconLifecycle.draft),
        tier: BeaconVisibilityTier.coordination,
        now: _t,
      ),
    );
    expect(result.phase, BeaconCoordinationPhase.draft);
  });

  test('never returns empty phase for open beacon', () {
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: _beacon(),
        tier: BeaconVisibilityTier.coordination,
        now: _t,
      ),
    );
    expect(result.phase, isNotNull);
  });

  test('closed lifecycle uses lifecycleEndedAt slot2', () {
    final endedAt = DateTime.utc(2026, 6, 15, 14, 30);
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: _beacon(lifecycle: BeaconLifecycle.closed).copyWith(
          updatedAt: endedAt,
        ),
        tier: BeaconVisibilityTier.coordination,
        now: _t,
      ),
    );
    expect(result.phase, BeaconCoordinationPhase.closed);
    expect(result.slot2Kind, BeaconPhaseSlot2Kind.lifecycleEndedAt);
    expect(result.lifecycleEndedAt, endedAt);
  });

  test('cancelled lifecycle uses lifecycleEndedAt slot2', () {
    final endedAt = DateTime.utc(2026, 6, 10, 9, 0);
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: _beacon(lifecycle: BeaconLifecycle.cancelled).copyWith(
          updatedAt: endedAt,
        ),
        tier: BeaconVisibilityTier.public,
        now: _t,
      ),
    );
    expect(result.phase, BeaconCoordinationPhase.cancelled);
    expect(result.slot2Kind, BeaconPhaseSlot2Kind.lifecycleEndedAt);
    expect(result.lifecycleEndedAt, endedAt);
  });

  test('public closed via publicStatus uses lifecycleEndedAt slot2', () {
    final endedAt = DateTime.utc(2026, 6, 18, 16, 45);
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: _beacon(publicStatus: 4).copyWith(updatedAt: endedAt),
        tier: BeaconVisibilityTier.public,
        now: _t,
      ),
    );
    expect(result.phase, BeaconCoordinationPhase.closed);
    expect(result.slot2Kind, BeaconPhaseSlot2Kind.lifecycleEndedAt);
    expect(result.lifecycleEndedAt, endedAt);
  });
}
