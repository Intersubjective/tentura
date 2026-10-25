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
}
