import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

import '../../support/phone_surface.dart';

void main() {
  final now = DateTime.utc(2026, 10, 2, 12);
  final expiresAt = now.add(const Duration(days: 2, hours: 22));

  setUp(() => RelativeTimestampTicker.debugClock = () => now);
  tearDown(() => RelativeTimestampTicker.debugClock = null);

  testWidgets('375×667 RU: Posts row shows hourglass lifetime label', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: TenturaResponsiveScope(
            child: PostConversationRow(
              post: PostSummary(
                id: 'P248',
                authorId: 'U1',
                authorName: 'Олег',
                rootExcerpt: 'Кто в субботу?',
                lastMessageExcerpt: 'Я могу',
                lastActivityAt: now,
                expiresAt: expiresAt,
              ),
              now: now,
              onOpen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('⏳', findRichText: true), findsOneWidget);
    expect(find.textContaining('осталось', findRichText: true), findsOneWidget);
  });

  testWidgets('375×667 RU: gap between addressee line and hourglass lifetime', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: TenturaResponsiveScope(
            child: Builder(
              builder: (context) {
                return PostConversationRow(
                  post: PostSummary(
                    id: 'P248gap',
                    authorId: 'U1',
                    authorName: 'Олег',
                    rootExcerpt: 'Кто в субботу?',
                    lastMessageExcerpt: 'Я могу',
                    lastActivityAt: now,
                    expiresAt: expiresAt,
                  ),
                  now: now,
                  onOpen: () {},
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final addressing = find.textContaining('· вам', findRichText: true);
    final lifetime = find.byKey(const Key('PostConversation.Lifetime'));
    expect(addressing, findsOneWidget);
    expect(lifetime, findsOneWidget);
    final gap =
        tester.getTopLeft(lifetime).dx - tester.getTopRight(addressing).dx;
    final tt = tester.element(find.byType(TenturaResponsiveScope)).tt;
    expect(gap, greaterThanOrEqualTo(tt.iconTextGap - 1));
  });
}
