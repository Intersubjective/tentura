import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/inbox/data/repository/posts_repository.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/remote_wire_harness.dart';

Future<PostSummary> _loadPost(String? forwardedByName) async {
  late PostSummary post;
  await withRemoteWire(
    {
      'MyPosts': {
        '__typename': 'query_root',
        'myPosts': [
          {
            '__typename': 'v2_PostSummary',
            'id': 'Bpost00000001',
            'authorId': 'Uauthor000001',
            'authorName': 'QA Alice',
            'authorAvatar': '',
            'forwardedByName': forwardedByName,
            'rootImageUrl': null,
            'rootExcerpt': 'Root message',
            'lastMessageExcerpt': null,
            'lastMessageAt': null,
            'lastActivityAt': '2030-01-01T00:00:00.000Z',
            'pinnedAt': null,
            'mutedUntil': null,
            'mutedForever': false,
            'unreadCount': 0,
            'isAuthor': false,
            'status': 0,
            'expiresAt': null,
          },
        ],
      },
    },
    <WireSent>[],
    (remote) async {
      post = (await PostsRepository(remote).myPosts()).single;
    },
  );
  return post;
}

Future<void> _pumpRow(
  WidgetTester tester,
  PostSummary post,
  Locale locale,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: TenturaResponsiveScope(
          child: PostConversationRow(
            post: post,
            now: DateTime.utc(2030),
            onOpen: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('Post conversation attribution', () {
    const locale = Locale('en');
    // Preserve the existing direct-address copy used by the production row.
    final direct = lookupL10n(locale).postConversationAddressed('QA Alice');
    const forwarded = 'QA Alice · via Bob GQ';

    testWidgets(
      'row names the forwarder and keeps direct addressing without one',
      (tester) async {
        final directPost = await tester.runAsync(() => _loadPost(null));
        final forwardedPost = await tester.runAsync(
          () => _loadPost('Bob GQ'),
        );

        await _pumpRow(tester, directPost!, locale);
        expect(find.text(direct), findsOneWidget);

        await _pumpRow(tester, forwardedPost!, locale);
        expect(find.text(forwarded), findsOneWidget);
        expect(find.text(direct), findsNothing);
      },
    );

    testWidgets(
      'accessibility label names the forwarder and keeps direct addressing without one',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final directPost = await tester.runAsync(() => _loadPost(null));
          final forwardedPost = await tester.runAsync(
            () => _loadPost('Bob GQ'),
          );

          await _pumpRow(tester, directPost!, locale);
          expect(
            find.bySemanticsLabel(
              RegExp('^${RegExp.escape(direct)}, Root message'),
            ),
            findsOneWidget,
          );

          await _pumpRow(tester, forwardedPost!, locale);
          expect(
            find.bySemanticsLabel(
              RegExp('^${RegExp.escape(forwarded)}, Root message'),
            ),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(RegExp(RegExp.escape(direct))),
            findsNothing,
          );
        } finally {
          semantics.dispose();
        }
      },
    );
  });
}
