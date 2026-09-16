import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/inbox/ui/widget/activity_event_subcard_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('shows capped previews and more label', (tester) async {
    final previews = [
      for (var i = 0; i < 3; i++)
        AttentionReceipt(
          id: 'e$i',
          category: 'requestProgress',
          kind: 'requestStatusChanged',
          priority: 'normal',
          title: 'Event $i',
          body: 'Body',
          actionUrl: '/#/',
          createdAt: DateTime.utc(2026, 1, i + 1),
          collapsedCount: 1,
          presentationPayloadJson: '{}',
          surface: AttentionSurface.activity,
        ),
    ];
    var marked = <String>[];
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: ActivityEventSubcardBlock(
                eventTotal: 5,
                eventsPreview: previews,
                onMarkSeen: marked.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ActivityEventSubcardBlock), findsOneWidget);
    expect(find.text('2 more updates'), findsOneWidget);
    expect(find.byType(TenturaTechCardStatic), findsNWidgets(3));

    await tester.tap(find.byType(TenturaTechCardStatic).at(1));
    await tester.pump();
    expect(marked, ['e1']);
  });
}
