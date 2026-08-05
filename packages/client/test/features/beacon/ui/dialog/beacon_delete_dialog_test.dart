import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('blocked delete dialog shows archive action', (tester) async {
    var archived = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: BeaconDeleteDialog(
          status: BeaconStatus.closed,
          hasEverHadCommitter: true,
          onArchive: () async => archived = true,
        ),
      ),
    );

    expect(find.text('Cannot delete'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(archived, isTrue);
  });
}
