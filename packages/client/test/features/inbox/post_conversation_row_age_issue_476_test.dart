// Issue #476 (QA 7.50.7): the Post thread row in Conversations still read
// its age the long way («7m ago», «Just now») while the Post and Request
// cards beside it use the card's short age («7m», «now», «Sep 12»).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

void main() {
  final now = DateTime(2030, 10, 14, 12);

  setUp(() => RelativeTimestampTicker.debugClock = () => now);
  tearDown(() => RelativeTimestampTicker.debugClock = null);

  Future<void> pumpRow(
    WidgetTester tester, {
    required DateTime lastActivityAt,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: TenturaResponsiveScope(
            child: PostConversationRow(
              post: PostSummary(
                id: 'P1',
                authorId: 'U1',
                authorName: 'Theo',
                rootExcerpt: 'Who can help me move a sofa?',
                lastMessageExcerpt: 'I can, what time?',
                lastActivityAt: lastActivityAt,
              ),
              now: now,
              onOpen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('#476 Post thread row age', () {
    testWidgets('reads the short card age, not «… ago»', (tester) async {
      await pumpRow(
        tester,
        lastActivityAt: now.subtract(const Duration(minutes: 7)),
      );

      expect(find.text('7m'), findsOneWidget);
      expect(find.textContaining('ago'), findsNothing);
    });

    testWidgets('a fresh message reads «now»', (tester) async {
      await pumpRow(
        tester,
        lastActivityAt: now.subtract(const Duration(seconds: 20)),
      );

      expect(find.text('now'), findsOneWidget);
      expect(find.text('Just now'), findsNothing);
    });

    testWidgets('past a week it is the date, as on the cards', (tester) async {
      await pumpRow(
        tester,
        lastActivityAt: now.subtract(const Duration(days: 30)),
      );

      expect(find.text('Sep 14'), findsOneWidget);
    });

    testWidgets('Russian reads the short age too', (tester) async {
      final ru = lookupL10n(const Locale('ru'));
      await pumpRow(
        tester,
        lastActivityAt: now.subtract(const Duration(minutes: 7)),
        locale: const Locale('ru'),
      );

      expect(find.text(ru.relativeTimeCompactMinutes(7)), findsOneWidget);
      expect(find.text(ru.relativeTimeMinutesAgo(7)), findsNothing);
    });
  });
}
