import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_activity_event_presenter.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));
  final theme = TenturaTheme.light();

  BeaconActivityEvent event(int type) => BeaconActivityEvent(
    id: 'e1',
    beaconId: 'b1',
    visibility: 0,
    type: type,
    createdAt: DateTime(2026, 6, 18),
  );

  test('beaconPublished label and icon', () {
    final e = event(BeaconActivityEventTypeBits.beaconPublished);
    expect(
      beaconActivityEventLabel(l10n, e),
      l10n.beaconActivityBeaconPublished,
    );
    expect(beaconActivityLogIcon(e), Icons.campaign_outlined);
    expect(
      beaconActivityLogIconColor(theme, e),
      theme.colorScheme.primary,
    );
  });

  test('blockerOpened uses danger tier color', () {
    final e = event(BeaconActivityEventTypeBits.blockerOpened);
    expect(
      beaconActivityEventLabel(l10n, e),
      l10n.beaconActivityBlockerOpened,
    );
    expect(beaconActivityLogTier(e), BeaconActivityLogTier.high);
  });
}
