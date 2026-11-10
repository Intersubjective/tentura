import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/inbox/data/repository/posts_repository.dart';
import 'package:tentura/features/inbox/domain/entity/post_participant_preview.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_participants_copy.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_row.dart';
import 'package:tentura/features/post_view/ui/widget/post_participants_list.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';

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

Future<void> _pumpRowAt(
  WidgetTester tester, {
  required PostSummary post,
  required Locale locale,
  required Size size,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
            onOpenParticipants: () {},
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
  bool isAuthor = true,
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
  'isAuthor': isAuthor,
  'status': 0,
  'expiresAt': null,
};

const _viewerId = 'Uviewer';

/// A `BeaconParticipantList` wire row for the same Post.
Map<String, dynamic> _participantRow({
  required String userId,
  required String title,
  required bool opened,
  int role = BeaconParticipantRoleBits.addressee,
}) => {
  '__typename': 'v2_BeaconParticipantRow',
  'id': 'p-$userId',
  'beaconId': _postId,
  'userId': userId,
  'userTitle': title,
  'userHandle': null,
  'userHasPicture': false,
  'userPicHeight': 0,
  'userPicWidth': 0,
  'userBlurHash': '',
  'userImageId': '',
  'role': role,
  'status': 0,
  'roomAccess': RoomAccessBits.admitted,
  'offerNote': null,
  'nextMoveText': null,
  'nextMoveStatus': null,
  'nextMoveSource': null,
  'linkedMessageId': null,
  'lastSeenRoomAt': opened ? '2026-11-04T10:00:00.000Z' : null,
  'opened': opened,
  'helpType': null,
  'roleLabel': null,
  'broughtById': null,
  'broughtBy': null,
  'broughtHow': null,
  'createdAt': '2026-11-04T10:00:00.000Z',
  'updatedAt': '2026-11-04T10:00:00.000Z',
};

/// The first n in 0..50 for which [text] of n is on screen.
int? _shownCount(String Function(int) text) {
  for (var n = 0; n <= 50; n++) {
    if (find.text(text(n)).evaluate().isNotEmpty) return n;
  }
  return null;
}

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

      // Three other members plus the viewer.
      expect(find.text(l10n.postConversationPeople(4)), findsOneWidget);
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
            "3 people · 1 hasn't opened · 1 declined",
          );
        },
      );
    });
  });

  group('Posts card people count includes the viewer', () {
    final en = lookupL10n(const Locale('en'));
    final ru = lookupL10n(const Locale('ru'));

    test('a four-member Post reads as four people, viewer included', () {
      // Server counts the other three members; one of them has not opened.
      final post = _summary(participantCount: 3, notOpenedCount: 1);
      expect(
        postConversationParticipantsLine(en, post),
        "4 people · 1 hasn't opened",
      );
      expect(
        postConversationParticipantsLine(ru, post),
        '4 человека · 1 не открыл',
      );
    });

    test('a Post with nobody else still reads Only you', () {
      final post = _summary();
      expect(postConversationParticipantsLine(en, post), 'Only you');
      expect(postConversationParticipantsLine(ru, post), 'Только вы');
    });

    test('plural forms follow the viewer-inclusive count', () {
      expect(
        postConversationParticipantsLine(en, _summary(participantCount: 1)),
        '2 people',
      );
      expect(
        postConversationParticipantsLine(ru, _summary(participantCount: 1)),
        '2 человека',
      );
      expect(
        postConversationParticipantsLine(ru, _summary(participantCount: 4)),
        '5 человек',
      );
      expect(
        postConversationParticipantsLine(ru, _summary(participantCount: 20)),
        '21 человек',
      );
    });

    for (final sample in [
      (
        locale: const Locale('en'),
        size: const Size(1280, 800),
        line: "4 people · 1 hasn't opened",
      ),
      (
        locale: const Locale('ru'),
        size: kPhoneSurface,
        line: '4 человека · 1 не открыл',
      ),
    ]) {
      testWidgets(
        'the card of a four-member Post reads four people '
        '(${sample.locale.languageCode} '
        '${sample.size.width.toInt()}×${sample.size.height.toInt()})',
        (tester) async {
          // Real MyPosts wire for a non-author viewer of a four-member Post.
          late PostSummary post;
          await tester.runAsync(
            () => withRemoteWire(
              {
                'MyPosts': {
                  '__typename': 'query_root',
                  'myPosts': [
                    _wireRow(
                      participantCount: 3,
                      myDeclinedForwardCount: 0,
                      isAuthor: false,
                    ),
                  ],
                },
              },
              <WireSent>[],
              (remote) async {
                post = (await PostsRepository(remote).myPosts()).single;
              },
            ),
          );
          await _pumpRowAt(
            tester,
            post: post,
            locale: sample.locale,
            size: sample.size,
          );

          expect(find.text(sample.line), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final sample in [
      (
        locale: const Locale('en'),
        size: const Size(1280, 800),
        line: "4 people · 1 hasn't opened",
      ),
      (
        locale: const Locale('ru'),
        size: kPhoneSurface,
        line: '4 человека · 1 не открыл',
      ),
    ]) {
      testWidgets(
        'the card counts the same people as the Participants sheet '
        '(${sample.locale.languageCode} '
        '${sample.size.width.toInt()}×${sample.size.height.toInt()})',
        (tester) async {
          // One Post, four members: author Alice, Bob, Carol (not opened)
          // and the viewer. Both reads come off the real wire.
          late PostSummary post;
          late List<BeaconParticipant> members;
          await tester.runAsync(() async {
            final realtime = buildTestRealtimeSync();
            await withRemoteWire(
              {
                'MyPosts': {
                  '__typename': 'query_root',
                  'myPosts': [
                    _wireRow(
                      participantCount: 3,
                      myDeclinedForwardCount: 0,
                      isAuthor: false,
                    ),
                  ],
                },
                'BeaconParticipantList': {
                  '__typename': 'query_root',
                  'BeaconParticipantList': [
                    _participantRow(
                      userId: 'Uauthor',
                      title: 'Alice',
                      opened: true,
                      role: BeaconParticipantRoleBits.author,
                    ),
                    _participantRow(userId: 'Ubob', title: 'Bob', opened: true),
                    _participantRow(
                      userId: 'Ucarol',
                      title: 'Carol',
                      opened: false,
                    ),
                    _participantRow(
                      userId: _viewerId,
                      title: 'Eve',
                      opened: false,
                    ),
                  ],
                },
              },
              <WireSent>[],
              (remote) async {
                post = (await PostsRepository(remote).myPosts()).single;
                members = await BeaconThreadsRepository(
                  remote,
                  realtime.port,
                ).fetchParticipants(_postId);
              },
            );
            await realtime.port.dispose();
          });
          final l10n = lookupL10n(sample.locale);

          await tester.binding.setSurfaceSize(sample.size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              theme: TenturaTheme.light(),
              locale: sample.locale,
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: Scaffold(
                body: TenturaResponsiveScope(
                  child: SingleChildScrollView(
                    child: PostParticipantsList(
                      viewerId: _viewerId,
                      participants: members,
                      forwardEdges: const [],
                      onForwardsGraph: () {},
                      peopleTagsEnabled: false,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          final sheetPeople = _shownCount(l10n.postParticipantsTitle);
          final sheetNotOpened = _shownCount(l10n.postParticipantsUnopened);
          expect(sheetPeople, 4, reason: 'the sheet counts the viewer');
          expect(sheetNotOpened, 1);

          await _pumpRowAt(
            tester,
            post: post,
            locale: sample.locale,
            size: sample.size,
          );
          expect(
            find.text(
              '${l10n.postConversationPeople(sheetPeople!)} · '
              '${l10n.postConversationNotOpened(sheetNotOpened!)}',
            ),
            findsOneWidget,
            reason: "the card shows the sheet's people and not-opened counts",
          );
          expect(
            find.text(sample.line),
            findsOneWidget,
            reason: 'four members, the viewer included; one has not opened',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
