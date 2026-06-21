import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/coordination/beacon_coordination_phase_input.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';

final _t = DateTime.utc(2026, 6, 20, 12);
final _l10n = lookupL10n(const Locale('en'));

Beacon _beacon() => Beacon.empty.copyWith(
      id: 'b1',
      title: 'Test',
      lifecycle: BeaconLifecycle.open,
      createdAt: _t,
      updatedAt: _t,
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  test('blocked status never includes blocker title', () {
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: _beacon(),
        tier: BeaconVisibilityTier.coordination,
        now: _t,
        hasOpenBlocker: true,
      ),
    );
    final pres = formatBeaconPhaseStatus(_l10n, result, now: _t);
    expect(pres.statusLine, 'Blocked · clearing needed');
    expect(pres.statusLine.toLowerCase(), isNot(contains('airline')));
    expect(pres.tone, TenturaTone.warn);
  });

  test('looking for helpers includes no offers slot2', () {
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: _beacon(),
        tier: BeaconVisibilityTier.coordination,
        now: _t,
      ),
    );
    final pres = formatBeaconPhaseStatus(_l10n, result, now: _t);
    expect(pres.statusLine, contains('no offers yet'));
  });

  test('resolve blocker CTA label', () {
    final label = formatBeaconPhasePrimaryCtaLabel(
      _l10n,
      BeaconPhasePrimaryAction.resolveBlocker,
    );
    expect(label, 'Resolve blocker');
  });

  test('non-responsible viewer gets none action after gating', () {
    final action = resolveEffectivePrimaryAction(
      suggested: BeaconPhasePrimaryAction.resolveBlocker,
      isAuthor: false,
      isAuthorOrSteward: false,
      canCoordinateInRoom: true,
      isPersonallyResponsibleForBlocker: false,
      canOfferHelp: true,
      canNavigateRoom: true,
    );
    expect(action, BeaconPhasePrimaryAction.none);
  });

  test('closed status includes concrete closure date and time', () {
    final endedAt = DateTime(2026, 6, 15, 14, 30);
    final now = DateTime(2026, 6, 20, 12);
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: _beacon().copyWith(
          lifecycle: BeaconLifecycle.closed,
          updatedAt: endedAt,
        ),
        tier: BeaconVisibilityTier.coordination,
        now: now,
      ),
    );
    final pres = formatBeaconPhaseStatus(_l10n, result, now: now);
    expect(pres.statusLine, startsWith('Closed · '));
    expect(pres.statusLine, isNot('Closed'));
    expect(pres.tone, TenturaTone.neutral);
  });

  test('cancelled status includes time when closed today', () {
    final endedAt = DateTime(2026, 6, 20, 9, 15);
    final now = DateTime(2026, 6, 20, 12);
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: _beacon().copyWith(
          lifecycle: BeaconLifecycle.cancelled,
          updatedAt: endedAt,
        ),
        tier: BeaconVisibilityTier.coordination,
        now: now,
      ),
    );
    final pres = formatBeaconPhaseStatus(_l10n, result, now: now);
    expect(pres.statusLine, startsWith('Cancelled · '));
    expect(pres.statusLine, isNot(contains(',')));
  });

  test('offers awaiting author includes active today when updated today', () {
    final now = DateTime.utc(2026, 6, 20, 12);
    final beacon = _beacon().copyWith(
      helpOfferCount: 2,
      updatedAt: now,
    );
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: beacon,
        tier: BeaconVisibilityTier.coordination,
        now: now,
        hasUnreviewedOffers: true,
      ),
    );
    final pres = formatBeaconPhaseStatus(_l10n, result, now: now);
    expect(pres.statusLine, contains(_l10n.beaconPhaseOffersAwaitingAuthor));
    expect(pres.statusLine, contains(_l10n.beaconPhaseActiveToday));
    expect(pres.tone, TenturaTone.info);
  });

  test('offers awaiting author includes quiet days when stale', () {
    final now = DateTime.utc(2026, 6, 20, 12);
    final beacon = _beacon().copyWith(
      helpOfferCount: 2,
      updatedAt: now.subtract(const Duration(days: 5)),
    );
    final result = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: beacon,
        tier: BeaconVisibilityTier.coordination,
        now: now,
        hasUnreviewedOffers: true,
      ),
    );
    final pres = formatBeaconPhaseStatus(_l10n, result, now: now);
    expect(pres.statusLine, contains(_l10n.beaconPhaseOffersAwaitingAuthor));
    expect(pres.statusLine, contains(_l10n.beaconPhaseQuietForDays(5)));
    expect(pres.tone, TenturaTone.info);
  });
}
