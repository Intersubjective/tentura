import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/unified_forward_row.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  const viewerId = 'v1';
  final sender = const Profile(id: 's1', displayName: 'Sender');
  final recipient = const Profile(id: 'r1', displayName: 'Recipient');
  final edge = ForwardEdge(
    id: 'e1',
    beaconId: 'b1',
    sender: sender,
    recipient: recipient,
    note: 'Test note',
    createdAt: DateTime.now(),
  );

  testWidgets('UnifiedForwardRow.outgoing renders without bar and with correct alignment', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: UnifiedForwardRow.outgoing(
            edge: edge,
            viewerUserId: viewerId,
            helpOffered: {},
            watching: {},
            onward: {},
          ),
        ),
      ),
    );

    // Header (Row with children) should not have the previous spacer or bar alignment
    // We check that there is no vertical bar (Container with width 2 and primary color)
    // The previous implementation had a bar Container(width: 2, height: double.infinity, color: scheme.primary.withValues(alpha: 0.45))
    final barFinder = find.byWidgetPredicate((widget) =>
        widget is Container &&
        widget.constraints?.minWidth == 2 &&
        widget.constraints?.maxHeight == double.infinity);

    expect(barFinder, findsNothing, reason: 'Vertical bar should not be present in outgoing mode');

    // Verify that the header is starting at the beginning of the Column
    final headerFinder = find.text('Sender');
    expect(headerFinder, findsOneWidget);
    
    // Check note alignment - should have padding
    expect(find.text('Test note'), findsOneWidget);
    final padding = tester.widget<Padding>(find.ancestor(of: find.text('Test note'), matching: find.byType(Padding)).first);
    expect(padding.padding, const EdgeInsets.only(left: 18.0 + 4));
  });
}
