// Issue #449 (QA, main ee68f49): the Log rows were made one neutral weight,
// but the main Timeline `_ActivityEntryTile` still bolded "high tier" lines
// (creation, status change) with w600, so two plain events read as headings.
// Spec: every Timeline line uses the same body weight; the tier stays on the
// icon colour.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/activity_list.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

void main() {
  final created = DateTime.utc(2026, 10, 13, 22, 35);
  const author = Profile(id: 'U1', displayName: 'Author');
  final beacon = Beacon(
    id: 'B1',
    title: 'Help me move the piano',
    createdAt: created,
    updatedAt: created,
    author: author,
  );

  testWidgets('#449 high-tier Timeline lines are not bold', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: BeaconActivityList(
              timeline: [
                TimelineCreation(author: author, createdAt: created),
                TimelineBeaconCoordinationStatusChanged(
                  author: author,
                  status: BeaconStatus.closed,
                  at: created.add(const Duration(minutes: 2)),
                ),
              ],
              beacon: beacon,
              isAuthorView: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final l10n = lookupL10n(const Locale('en'));
    final body = Theme.of(
      tester.element(find.byType(BeaconActivityList)),
    ).textTheme.bodySmall;
    final creation = find.text(l10n.timelineCreated('Author'));
    final status = find.textContaining('Author marked the request as');
    // Vacuity guard: both high-tier lines are on screen.
    expect(creation, findsOneWidget);
    expect(status, findsOneWidget);

    for (final line in [creation, status]) {
      final weight = tester.widget<Text>(line).style?.fontWeight;
      expect(weight, isNot(FontWeight.w600));
      expect(weight, body?.fontWeight);
    }
  });

  // #609 (#449) re-check: not only the weight; colour and size must not vary
  // by tier either. One line of each tier (high, medium, low) carries the
  // same body style; only the icon colour tells the tiers apart.
  testWidgets('#609 Timeline lines of every tier share one text style', (
    tester,
  ) async {
    const helper = Profile(id: 'U2', displayName: 'Helper');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: BeaconActivityList(
              timeline: [
                TimelineCreation(author: author, createdAt: created),
                TimelineHelpOfferCreated(
                  helpOfferer: helper,
                  message: 'I can lift',
                  createdAt: created.add(const Duration(minutes: 1)),
                ),
                TimelineHelpOfferUpdated(
                  helpOfferer: helper,
                  message: 'I can lift, Sunday',
                  updatedAt: created.add(const Duration(minutes: 2)),
                ),
              ],
              beacon: beacon,
              isAuthorView: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final l10n = lookupL10n(const Locale('en'));
    final body = Theme.of(
      tester.element(find.byType(BeaconActivityList)),
    ).textTheme.bodySmall;
    final lines = {
      'high': find.text(l10n.timelineCreated('Author')),
      'medium': find.text(l10n.timelineHelpOffered('Helper')),
      'low': find.text(l10n.timelineHelpOfferDetailsUpdated('Helper')),
    };
    for (final MapEntry(:key, :value) in lines.entries) {
      // Vacuity guard: each tier's line is on screen.
      expect(value, findsOneWidget, reason: '$key-tier line');
      expect(
        tester.widget<Text>(value).style,
        body,
        reason: '$key-tier line uses the plain body style',
      );
    }
  });
}
