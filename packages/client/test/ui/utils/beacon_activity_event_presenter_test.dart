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

  test('lifecycle reviewExpired label icon and system flag', () {
    final e = BeaconActivityEvent(
      id: 'e1',
      beaconId: 'b1',
      visibility: 0,
      type: BeaconActivityEventTypeBits.beaconLifecycleChanged,
      createdAt: DateTime(2026, 6, 18),
      diffJson:
          '{"fromState":5,"toState":6,"reason":"${BeaconLifecycleChangeReason.reviewExpired}"}',
    );
    expect(
      beaconActivityEventLabel(l10n, e),
      l10n.beaconActivityLifecycleReviewExpired,
    );
    expect(beaconActivityLogIcon(e), Icons.timer_off_outlined);
    expect(beaconLifecycleEventIsSystem(e), isTrue);
    expect(beaconActivityLogTier(e), BeaconActivityLogTier.high);
  });

  test('lifecycle authorCloseNow uses closed-after-review label', () {
    final e = BeaconActivityEvent(
      id: 'e2',
      beaconId: 'b1',
      visibility: 0,
      type: BeaconActivityEventTypeBits.beaconLifecycleChanged,
      createdAt: DateTime(2026, 6, 18),
      diffJson:
          '{"fromState":5,"toState":6,"reason":"${BeaconLifecycleChangeReason.authorCloseNow}"}',
      actorId: 'author1',
    );
    expect(
      beaconActivityEventLabel(l10n, e),
      l10n.beaconActivityLifecycleClosedAfterReview,
    );
    expect(beaconLifecycleEventIsSystem(e), isFalse);
  });

  // tentura-617.33 (plan §8.8): fact edited / removed events must render as
  // real Log tab lines with their own meaning, not the generic coordination
  // fallback. Copy mirrors the existing 'Fact pinned' / 'Fact visibility
  // changed' entries.
  group('fact edited / removed (types 19 / 20)', () {
    test('factEdited (19) reads "Fact edited"', () {
      final e = event(BeaconActivityEventTypeBits.factEdited);
      expect(beaconActivityEventLabel(l10n, e), 'Fact edited');
      expect(beaconActivityLogIcon(e), isNot(Icons.hub_outlined));
    });

    test('factRemoved (20) reads "Fact removed"', () {
      final e = event(BeaconActivityEventTypeBits.factRemoved);
      expect(beaconActivityEventLabel(l10n, e), 'Fact removed');
      expect(beaconActivityLogIcon(e), isNot(Icons.hub_outlined));
    });

    test('edited and removed use distinct labels and icons', () {
      final edited = event(BeaconActivityEventTypeBits.factEdited);
      final removed = event(BeaconActivityEventTypeBits.factRemoved);
      expect(
        beaconActivityEventLabel(l10n, edited),
        isNot(beaconActivityEventLabel(l10n, removed)),
      );
      expect(
        beaconActivityLogIcon(edited),
        isNot(beaconActivityLogIcon(removed)),
      );
      // Neither may reuse the pin icon: they are not pin events.
      expect(beaconActivityLogIcon(edited), isNot(Icons.push_pin_outlined));
      expect(beaconActivityLogIcon(removed), isNot(Icons.push_pin_outlined));
    });
  });
}
