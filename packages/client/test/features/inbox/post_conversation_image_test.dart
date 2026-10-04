import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    String? rootImageUrl,
    VoidCallback? onOpen,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: TenturaResponsiveScope(
            child: PostConversationRow(
              post: PostSummary(
                id: 'P1',
                authorId: 'U1',
                authorName: 'Anna',
                authorAvatar: 'https://example.test/avatar.jpg',
                rootImageUrl: rootImageUrl,
                rootExcerpt: 'Root message',
                lastActivityAt: DateTime.utc(2030),
              ),
              now: DateTime.utc(2030),
              onOpen: onOpen ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('uses root artwork with square token size and cover fit', (
    tester,
  ) async {
    await pumpRow(tester, rootImageUrl: 'https://example.test/root.jpg');
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, 'https://example.test/root.jpg');
    expect(image.fit, BoxFit.cover);
    expect(find.byType(TenturaAvatar), findsNothing);
    final context = tester.element(find.byType(PostConversationRow));
    expect(
      tester.getSize(find.byType(Image)),
      Size.square(context.tt.avatarSize),
    );
    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect).first);
    expect(clip.borderRadius, BorderRadius.circular(context.tt.cardRadius));
    final fallback = image.errorBuilder!(
      context,
      Exception('unavailable'),
      null,
    );
    expect(fallback, isA<ColoredBox>());
    await tester.pumpWidget(MaterialApp(home: fallback));
    expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
  });

  testWidgets('text-only conversation uses neutral icon and still opens', (
    tester,
  ) async {
    var opened = false;
    await pumpRow(tester, onOpen: () => opened = true);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(TenturaAvatar), findsNothing);
    expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
    await tester.tap(find.text('Root message'));
    expect(opened, isTrue);
  });
}
