import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Beacon _beacon({
  BeaconLifecycle lifecycle = BeaconLifecycle.open,
  int helpOfferCount = 0,
  BeaconCoordinationStatus coordinationStatus = BeaconCoordinationStatus.neutral,
}) =>
    Beacon(
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      id: 'b1',
      title: 'Test',
      author: const Profile(id: 'u1'),
      lifecycle: lifecycle,
      helpOfferCount: helpOfferCount,
      coordinationStatus: coordinationStatus,
    );

void main() {
  final l10n = lookupL10n(const Locale('en'));

  group('beaconStatusMenuOpenRowLabel', () {
    test('draft shows publish label', () {
      expect(
        beaconStatusMenuOpenRowLabel(l10n, _beacon(lifecycle: BeaconLifecycle.draft)),
        l10n.beaconStatusRowPublish,
      );
    });

    test('open with help offers shows coordinating label', () {
      expect(
        beaconStatusMenuOpenRowLabel(l10n, _beacon(helpOfferCount: 2)),
        l10n.beaconPhaseCoordinating,
      );
    });

    test('open without offers shows open label', () {
      expect(
        beaconStatusMenuOpenRowLabel(l10n, _beacon()),
        l10n.beaconStatusRowOpen,
      );
    });
  });

  group('beaconStatusMenuDisabledReasonLabel', () {
    test('none and terminal return empty string', () {
      expect(
        beaconStatusMenuDisabledReasonLabel(
          l10n,
          BeaconStatusMenuDisabledReason.none,
        ),
        '',
      );
      expect(
        beaconStatusMenuDisabledReasonLabel(
          l10n,
          BeaconStatusMenuDisabledReason.terminalState,
        ),
        '',
      );
    });

    test('blocked returns hint text', () {
      expect(
        beaconStatusMenuDisabledReasonLabel(
          l10n,
          BeaconStatusMenuDisabledReason.blocked,
        ),
        l10n.beaconStatusHintBlocked,
      );
    });
  });

  group('beaconSituationStateLine', () {
    test('open with unreviewed offers shows coordinating', () {
      expect(
        beaconSituationStateLine(l10n, _beacon(helpOfferCount: 1)),
        l10n.beaconPhaseCoordinating,
      );
    });

    test('closed shows closed label', () {
      expect(
        beaconSituationStateLine(
          l10n,
          _beacon(lifecycle: BeaconLifecycle.closed),
        ),
        l10n.beaconStatusRowClosed,
      );
    });

    test('open with enough help shows coordination status label', () {
      expect(
        beaconSituationStateLine(
          l10n,
          _beacon(
            coordinationStatus: BeaconCoordinationStatus.enoughHelpOffered,
          ),
        ),
        l10n.coordinationEnoughHelp,
      );
    });
  });
}
