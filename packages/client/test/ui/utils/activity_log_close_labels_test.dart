import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_activity_event_presenter.dart';

BeaconActivityEvent _transition(String id, int from, int to, String reason) =>
    BeaconActivityEvent(
      id: id,
      beaconId: 'moving-day',
      visibility: 0,
      type: BeaconActivityEventTypeBits.beaconLifecycleChanged,
      createdAt: DateTime.utc(2026, 11, 3),
      diffJson: jsonEncode({
        'fromState': from,
        'toState': to,
        'reason': reason,
      }),
    );

void main() {
  group('Log close labels describe whether a final check occurred', () {
    for (final language in ['en', 'ru']) {
      test(
        '$language distinguishes immediate and reviewed closes with or without history',
        () {
          final l10n = lookupL10n(Locale(language));
          final direct = _transition('direct', 8, 6, 'authorCloseNow');
          final reviewed = _transition(
            'reviewed',
            BeaconStatus.reviewOpen.smallintValue,
            BeaconStatus.closed.smallintValue,
            'authorCloseNow',
          );
          final expected = <String>[];
          final actual = <String>[];
          for (final openedReason in [
            null,
            BeaconLifecycleChangeReason.closureOpened,
            BeaconLifecycleChangeReason.legacyClosureOpenReason,
          ]) {
            final opened = openedReason == null
                ? null
                : _transition(
                    'opened',
                    BeaconStatus.enoughHelp.smallintValue,
                    BeaconStatus.reviewOpen.smallintValue,
                    openedReason,
                  );
            // Ordinary review histories are presented without skip filtering.
            final reviewHistory = [?opened, reviewed];
            actual.add(beaconActivityEventLabel(l10n, reviewHistory.last));
            expected.add(l10n.beaconActivityLifecycleClosedAfterReview);
            // No-window histories use the same filtering as the Log sheet.
            final directHistory = omitSkippedFinalCheckActivityEvents([
              ?opened,
              direct,
            ]);
            expect(
              directHistory.map((event) => event.id),
              orderedEquals(['direct']),
              reason:
                  'A skipped final check removes its opened entry: $openedReason',
            );
            actual.add(beaconActivityEventLabel(l10n, directHistory.single));
            expected.add(l10n.beaconLifecycleClosed);
          }
          // Persisted state 4 is legacy closed, never an open review.
          actual.add(
            beaconActivityEventLabel(
              l10n,
              _transition('legacy-closed', 4, 6, 'authorCloseNow'),
            ),
          );
          expected.add(l10n.beaconLifecycleClosed);
          expect(actual, expected);
          // The event must also be correct independently of sibling filtering.
          expect(
            beaconActivityEventLabel(l10n, direct),
            l10n.beaconLifecycleClosed,
          );
        },
      );
    }
  });
}
