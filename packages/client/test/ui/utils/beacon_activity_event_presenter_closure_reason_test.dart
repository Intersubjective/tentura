// tentura-pt83: presenter must interpret server lifecycle diff.reason values
// closureOpened and closureExpired (legacy stored wires via consts).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_activity_event_presenter.dart';

/// Server [`beacon_activity_event.diff.reason`] wire values (see server consts).
const _serverClosureOpenedReason = 'closureOpened';
const _serverClosureExpiredReason = 'closureExpired';
const _legacyReviewExpiredReason = 'reviewExpired';

BeaconActivityEvent _lifecycleEvent(String reasonWire) => BeaconActivityEvent(
  id: 'e-closure',
  beaconId: 'b1',
  visibility: 0,
  type: BeaconActivityEventTypeBits.beaconLifecycleChanged,
  createdAt: DateTime(2026, 6, 18),
  diffJson: '{"fromState":5,"toState":6,"reason":"$reasonWire"}',
);

void main() {
  final l10n = lookupL10n(const Locale('en'));

  group('server closureOpened lifecycle event (tentura-pt83 regression)', () {
    test('label icon tier and non-system flag match review-open UX', () {
      final e = _lifecycleEvent(_serverClosureOpenedReason);
      expect(
        beaconActivityEventLabel(l10n, e),
        l10n.beaconLifecycleReviewOpen,
      );
      expect(beaconActivityLogIcon(e), Icons.hourglass_top_outlined);
      expect(beaconLifecycleEventIsSystem(e), isFalse);
      expect(beaconActivityLogTier(e), BeaconActivityLogTier.high);
    });

    test('presentation matches legacy stored open wire for stored events', () {
      final server = _lifecycleEvent(_serverClosureOpenedReason);
      final legacy = _lifecycleEvent(
        BeaconLifecycleChangeReason.legacyClosureOpenReason,
      );
      expect(
        beaconActivityEventLabel(l10n, server),
        beaconActivityEventLabel(l10n, legacy),
      );
      expect(beaconActivityLogIcon(server), beaconActivityLogIcon(legacy));
      expect(
        beaconLifecycleEventIsSystem(server),
        beaconLifecycleEventIsSystem(legacy),
      );
      expect(beaconActivityLogTier(server), beaconActivityLogTier(legacy));
    });
  });

  group('server closureExpired lifecycle event (tentura-pt83)', () {
    test('label icon tier and system flag match review-expired UX', () {
      final e = _lifecycleEvent(_serverClosureExpiredReason);
      expect(
        beaconActivityEventLabel(l10n, e),
        l10n.beaconActivityLifecycleReviewExpired,
      );
      expect(beaconActivityLogIcon(e), Icons.timer_off_outlined);
      expect(beaconLifecycleEventIsSystem(e), isTrue);
      expect(beaconActivityLogTier(e), BeaconActivityLogTier.high);
    });

    test('presentation matches legacy reviewExpired wire for stored events', () {
      final server = _lifecycleEvent(_serverClosureExpiredReason);
      final legacy = _lifecycleEvent(_legacyReviewExpiredReason);
      expect(
        beaconActivityEventLabel(l10n, server),
        beaconActivityEventLabel(l10n, legacy),
      );
      expect(beaconActivityLogIcon(server), beaconActivityLogIcon(legacy));
      expect(
        beaconLifecycleEventIsSystem(server),
        beaconLifecycleEventIsSystem(legacy),
      );
    });
  });
}
