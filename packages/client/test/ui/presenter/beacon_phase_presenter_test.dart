import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
