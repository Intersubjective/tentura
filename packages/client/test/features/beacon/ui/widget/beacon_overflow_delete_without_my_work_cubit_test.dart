import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lifecycle_ui.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// Mirrors request-detail overflow delete: show [BeaconDeleteDialog] without
/// reading [MyWorkCubit] (absent on the root BeaconView stack).
Future<void> _onDeleteFromDetail(
  BuildContext context,
  Beacon beacon,
) async {
  if (!context.mounted) return;
  await BeaconDeleteDialog.show(
    context,
    status: beacon.status,
    hasEverHadCommitter: beaconDeleteBlockedByCommitters(beacon),
  );
}

void main() {
  testWidgets(
    'Delete Request shows confirm dialog without MyWorkCubit in tree',
    (tester) async {
      final t = DateTime.utc(2026, 6, 20);
      final beacon = Beacon(
        id: 'b1',
        title: 'T',
        author: const Profile(id: 'a', displayName: 'A'),
        createdAt: t,
        updatedAt: t,
        status: BeaconStatus.open,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: TenturaResponsiveScope(
            child: Scaffold(
              appBar: AppBar(
                actions: [
                  Builder(
                    builder: (context) => BeaconOverflowMenu(
                      beacon: beacon,
                      onDelete: () => _onDeleteFromDetail(context, beacon),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(TestIds.key(TestIds.beaconOverflowMenu)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Request'));
      await tester.pumpAndSettle();

      expect(find.text('Delete request?'), findsOneWidget);
    },
  );
}
