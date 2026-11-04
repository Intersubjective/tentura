import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/inbox/data/repository/posts_repository.dart';
import 'package:tentura/features/inbox/domain/entity/post_participant_preview.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_participants_copy.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';

const _postId = 'Bpostparticipants01';

PostSummary _summary({
  int participantCount = 0,
  int notOpenedCount = 0,
  int myDeclinedForwardCount = 0,
  List<PostParticipantPreview> previewParticipants = const [],
}) => PostSummary(
  id: _postId,
  authorId: 'Uauthor',
  authorName: 'Алиса',
  lastActivityAt: DateTime.utc(2026, 11, 4),
  participantCount: participantCount,
  notOpenedCount: notOpenedCount,
  myDeclinedForwardCount: myDeclinedForwardCount,
  previewParticipants: previewParticipants,
);

Future<void> _pumpRow(
  WidgetTester tester, {
  required PostSummary post,
  required Locale locale,
  VoidCallback? onOpenParticipants,
}) async {
  await usePhoneSurface(tester);
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
            now: DateTime.utc(2026, 11, 4),
            onOpen: () {},
            onOpenParticipants: onOpenParticipants,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Map<String, dynamic> _wireRow({
  int participantCount = 2,
  int notOpenedCount = 1,
  int myDeclinedForwardCount = 1,
}) => {
  '__typename': 'v2_PostSummary',
  'id': _postId,
  'authorId': 'Uauthor',
  'authorName': 'Alice',
  'authorAvatar': '',
  'forwardedByName': null,
  'rootImageUrl': null,
  'rootExcerpt': 'Weekend hike',
  'lastMessageExcerpt': null,
  'lastMessageIsRoot': true,
  'lastMessageAt': null,
  'lastActivityAt': '2026-11-04T12:00:00.000Z',
  'pinnedAt': null,
  'mutedUntil': null,
  'mutedForever': false,
  'unreadCount': 0,
  'participantCount': participantCount,
  'notOpenedCount': notOpenedCount,
  'myDeclinedForwardCount': myDeclinedForwardCount,
  'previewParticipants': [
    {
      '__typename': 'v2_PostParticipantPreview',
      'id': 'Upeer1',
      'displayName': 'Борис',
      'avatar': '',
    },
    {
      '__typename': 'v2_PostParticipantPreview',
      'id': 'Upeer2',
      'displayName': 'Вера',
      'avatar': '',
    },
  ],
  'isAuthor': true,
  'status': 0,
  'expiresAt': null,
};

void main() {
  group('Post conversation participants line', () {
    testWidgets('renders avatar stack and counts in RU at phone width', (
      tester,
    ) async {
      final l10n = lookupL10n(const Locale('ru'));
      final post = _summary(
        participantCount: 5,
        notOpenedCount: 2,
        myDeclinedForwardCount: 1,
        previewParticipants: const [
          PostParticipantPreview(id: 'U1', displayName: 'Борис'),
          PostParticipantPreview(id: 'U2', displayName: 'Вера'),
          PostParticipantPreview(id: 'U3', displayName: 'Глеб'),
          PostParticipantPreview(id: 'U4', displayName: 'Дина'),
        ],
      );
      await _pumpRow(tester, post: post, locale: const Locale('ru'));

      expect(find.byKey(postConversationParticipantsKey), findsOneWidget);
      expect(find.byType(TenturaAvatarStack), findsOneWidget);
      final line = postConversationParticipantsLine(l10n, post)!;
      expect(find.text(line), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'participants line must not overflow at 375×667',
      );
    });

    testWidgets('hides zero not-opened and declined segments', (tester) async {
      final l10n = lookupL10n(const Locale('en'));
      final post = _summary(participantCount: 3);
      await _pumpRow(tester, post: post, locale: const Locale('en'));

      expect(find.text(l10n.postConversationPeople(3)), findsOneWidget);
      expect(find.textContaining('opened'), findsNothing);
      expect(find.textContaining('declined'), findsNothing);
    });

    testWidgets('shows Only you when alone', (tester) async {
      final l10n = lookupL10n(const Locale('en'));
      await _pumpRow(
        tester,
        post: _summary(),
        locale: const Locale('en'),
      );
      expect(find.text(l10n.postConversationOnlyYou), findsOneWidget);
    });

    testWidgets('tap invokes participants opener callback', (tester) async {
      var tapped = false;
      await _pumpRow(
        tester,
        post: _summary(participantCount: 2),
        locale: const Locale('en'),
        onOpenParticipants: () => tapped = true,
      );
      await tester.tap(find.byKey(postConversationParticipantsKey));
      await tester.pump();
      expect(tapped, isTrue);
    });

    test('MyPosts wire maps forward/open/decline counts to row copy', () async {
      await withRemoteWire(
        {
          'MyPosts': {
            '__typename': 'query_root',
            'myPosts': [_wireRow()],
          },
        },
        <WireSent>[],
        (remote) async {
          final post = (await PostsRepository(remote).myPosts()).single;
          expect(post.participantCount, 2);
          expect(post.notOpenedCount, 1);
          expect(post.myDeclinedForwardCount, 1);
          final en = lookupL10n(const Locale('en'));
          expect(
            postConversationParticipantsLine(en, post),
            "2 people · 1 hasn't opened · 1 declined",
          );
        },
      );
    });
  });
}
