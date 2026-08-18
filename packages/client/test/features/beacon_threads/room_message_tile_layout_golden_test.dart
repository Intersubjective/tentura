import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/components/room_message_bubble_shape.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_reply_quote.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

class _GoldenProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _GoldenPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

void main() {
  const logicalSize = Size(360, 200);
  final createdAt = DateTime.utc(2026, 5, 22, 12, 34);

  const me = Profile(id: 'me', displayName: 'Me');
  const other = Profile(id: 'other', displayName: 'Alex River');

  Future<void> pumpRoomMessageGolden(
    WidgetTester tester, {
    required String goldenName,
    required RoomMessage message,
    required Profile myProfile,
    RoomMessage? previousMessage,
    RoomMessage? nextMessage,
  }) async {
    final profileCubit = _GoldenProfileCubit();
    final presenceCubit = _GoldenPresenceCubit();
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(value: profileCubit),
          BlocProvider<PresenceCubit>.value(value: presenceCubit),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: logicalSize),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: RepaintBoundary(
                  key: const Key('golden'),
                  child: SizedBox(
                    width: logicalSize.width,
                    child: RoomMessageTile(
                      message: message,
                      myProfile: myProfile,
                      previousMessage: previousMessage,
                      nextMessage: nextMessage,
                      onToggleReaction: (_, _) async {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/room_message_$goldenName.png'),
    );
  }

  RoomMessage textMessage({
    required String id,
    required String authorId,
    required Profile author,
    required String body,
    Map<String, int> reactionCounts = const {},
    Map<String, List<Profile>> reactors = const {},
    List<RoomMessageAttachment> attachments = const [],
    String? replyToMessageId,
    String? replyToAuthorId,
    String? replyToAuthorTitle,
    String? replyToBodyExcerpt,
    bool replyToHasAttachments = false,
  }) => RoomMessage(
    id: id,
    beaconId: 'b1',
    authorId: authorId,
    body: body,
    createdAt: createdAt,
    author: author,
    reactionCounts: reactionCounts,
    reactors: reactors,
    attachments: attachments,
    replyToMessageId: replyToMessageId,
    replyToAuthorId: replyToAuthorId,
    replyToAuthorTitle: replyToAuthorTitle,
    replyToBodyExcerpt: replyToBodyExcerpt,
    replyToHasAttachments: replyToHasAttachments,
  );

  group('room message layout goldens', () {
    testWidgets('short_text_mine_inline_meta', (tester) async {
      await pumpRoomMessageGolden(
        tester,
        goldenName: 'short_text_mine_inline_meta',
        message: textMessage(
          id: 'm1',
          authorId: 'me',
          author: me,
          body: 'Hey there!',
        ),
        myProfile: me,
      );
    });

    testWidgets('short_text_other_inline_meta', (tester) async {
      await pumpRoomMessageGolden(
        tester,
        goldenName: 'short_text_other_inline_meta',
        message: textMessage(
          id: 'm2',
          authorId: 'other',
          author: other,
          body: 'Hello room',
        ),
        myProfile: me,
      );
    });

    testWidgets('long_text_wraps_with_inline_meta', (tester) async {
      await pumpRoomMessageGolden(
        tester,
        goldenName: 'long_text_wraps_with_inline_meta',
        message: textMessage(
          id: 'm3',
          authorId: 'me',
          author: me,
          body:
              'This is a longer room message that should wrap across several '
              'lines so we can see the trailing timestamp on the last line '
              'of the text block.',
        ),
        myProfile: me,
      );
    });

    testWidgets('short_text_with_reactions_hugs_width', (tester) async {
      await pumpRoomMessageGolden(
        tester,
        goldenName: 'short_text_with_reactions_hugs_width',
        message: textMessage(
          id: 'm4',
          authorId: 'other',
          author: other,
          body: 'Nice work',
          reactionCounts: const {'👍': 2},
        ),
        myProfile: me,
      );
    });

    testWidgets('short_text_mine_with_reaction', (tester) async {
      await pumpRoomMessageGolden(
        tester,
        goldenName: 'short_text_mine_with_reaction',
        message: textMessage(
          id: 'm6',
          authorId: 'me',
          author: me,
          body: 'Thanks!',
          reactionCounts: const {'👍': 1},
        ),
        myProfile: me,
      );
    });

    testWidgets('mixed_text_and_file_attachment', (tester) async {
      await pumpRoomMessageGolden(
        tester,
        goldenName: 'mixed_text_and_file_attachment',
        message: textMessage(
          id: 'm5',
          authorId: 'me',
          author: me,
          body: 'See attached notes',
          attachments: const [
            RoomMessageAttachment(
              id: 'a1',
              kind: BeaconRoomMessageAttachmentKind.file,
              position: 0,
              mime: 'application/pdf',
              sizeBytes: 1024,
              fileName: 'notes.pdf',
            ),
          ],
        ),
        myProfile: me,
      );
    });

    testWidgets('reply_quote_mine_light', (tester) async {
      await pumpRoomMessageGolden(
        tester,
        goldenName: 'reply_quote_mine_light',
        message: textMessage(
          id: 'm-reply-mine',
          authorId: 'me',
          author: me,
          body: 'Sure, tomorrow works',
          replyToMessageId: 'parent-1',
          replyToAuthorId: 'other',
          replyToAuthorTitle: 'Alex River',
          replyToBodyExcerpt: 'can you bring the ladder tomorrow morning',
        ),
        myProfile: me,
      );
    });

    testWidgets('reply_quote_other_light', (tester) async {
      await pumpRoomMessageGolden(
        tester,
        goldenName: 'reply_quote_other_light',
        message: textMessage(
          id: 'm-reply-other',
          authorId: 'other',
          author: other,
          body: 'Reply body text',
          replyToMessageId: 'parent-2',
          replyToAuthorId: 'me',
          replyToAuthorTitle: 'Me',
          replyToBodyExcerpt: 'Original message excerpt for golden capture',
        ),
        myProfile: me,
      );
    });

    testWidgets('reply_quote_mine_dark', (tester) async {
      final profileCubit = _GoldenProfileCubit();
      final presenceCubit = _GoldenPresenceCubit();
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: profileCubit),
            BlocProvider<PresenceCubit>.value(value: presenceCubit),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            theme: TenturaTheme.dark(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(size: logicalSize),
              child: TenturaResponsiveScope(
                child: Scaffold(
                  body: RepaintBoundary(
                    key: const Key('golden'),
                    child: SizedBox(
                      width: logicalSize.width,
                      child: RoomMessageTile(
                        message: textMessage(
                          id: 'm-reply-mine-dark',
                          authorId: 'me',
                          author: me,
                          body: 'Sure, tomorrow works',
                          replyToMessageId: 'parent-1',
                          replyToAuthorId: 'other',
                          replyToAuthorTitle: 'Alex River',
                          replyToBodyExcerpt:
                              'can you bring the ladder tomorrow morning',
                        ),
                        myProfile: me,
                        onToggleReaction: (_, _) async {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byKey(const Key('golden')),
        matchesGoldenFile('goldens/room_message_reply_quote_mine_dark.png'),
      );
    });

    testWidgets('reply_quote_other_dark', (tester) async {
      final profileCubit = _GoldenProfileCubit();
      final presenceCubit = _GoldenPresenceCubit();
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: profileCubit),
            BlocProvider<PresenceCubit>.value(value: presenceCubit),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            theme: TenturaTheme.dark(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(size: logicalSize),
              child: TenturaResponsiveScope(
                child: Scaffold(
                  body: RepaintBoundary(
                    key: const Key('golden'),
                    child: SizedBox(
                      width: logicalSize.width,
                      child: RoomMessageTile(
                        message: textMessage(
                          id: 'm-reply-other-dark',
                          authorId: 'other',
                          author: other,
                          body: 'Reply body text',
                          replyToMessageId: 'parent-2',
                          replyToAuthorId: 'me',
                          replyToAuthorTitle: 'Me',
                          replyToBodyExcerpt:
                              'Original message excerpt for golden capture',
                        ),
                        myProfile: me,
                        onToggleReaction: (_, _) async {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byKey(const Key('golden')),
        matchesGoldenFile('goldens/room_message_reply_quote_other_dark.png'),
      );
    });
  }, skip: 'Goldens disabled');

  group('room message layout', () {
    testWidgets('mine bubble hugs the right edge on compact width', (
      tester,
    ) async {
      const compactSize = Size(390, 800);
      final profileCubit = _GoldenProfileCubit();
      final presenceCubit = _GoldenPresenceCubit();

      await tester.binding.setSurfaceSize(compactSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: profileCubit),
            BlocProvider<PresenceCubit>.value(value: presenceCubit),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(size: compactSize),
              child: TenturaResponsiveScope(
                child: Scaffold(
                  body: ListView(
                    children: [
                      RoomMessageTile(
                        message: textMessage(
                          id: 'm-mine',
                          authorId: 'me',
                          author: me,
                          body: 'Hey there friend',
                        ),
                        myProfile: me,
                        onToggleReaction: (_, _) async {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Bubble shell is the Material > DecoratedBox under the interaction
      // wrapper; avatar for others also uses DecoratedBox, so scope to mine.
      final bubble = find.descendant(
        of: find.byType(RoomMessageTile),
        matching: find.byWidgetPredicate(
          (w) => w is Material && w.shape is RoomMessageBubbleShape,
        ),
      );
      final rect = tester.getRect(bubble);
      const farGutter = TenturaSpacing.screenH;
      expect(compactSize.width - rect.right, closeTo(farGutter, 0.5));
      expect(rect.left, greaterThan(farGutter + 1));
    });

    testWidgets('image album caps to readable media width on wide viewport', (
      tester,
    ) async {
      const wideSize = Size(1400, 900);
      final profileCubit = _GoldenProfileCubit();
      final presenceCubit = _GoldenPresenceCubit();

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: profileCubit),
            BlocProvider<PresenceCubit>.value(value: presenceCubit),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(size: wideSize),
              child: TenturaResponsiveScope(
                child: Scaffold(
                  body: SizedBox(
                    width: wideSize.width,
                    child: RoomMessageTile(
                      message: textMessage(
                        id: 'm8',
                        authorId: 'me',
                        author: me,
                        body: '',
                        attachments: const [
                          RoomMessageAttachment(
                            id: 'img1',
                            kind: BeaconRoomMessageAttachmentKind.image,
                            position: 0,
                            mime: 'image/jpeg',
                            sizeBytes: 4096,
                            imageId: 'image-1',
                            imageAuthorId: 'me',
                            width: 1200,
                            height: 900,
                          ),
                        ],
                      ),
                      myProfile: me,
                      onToggleReaction: (_, _) async {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSize(find.byType(RoomMessageInlineImageAlbum)).width,
        520,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('angry_reaction_with_reactors_no_layout_overflow', (
      tester,
    ) async {
      const reactorA = Profile(id: 'r1', displayName: 'Sam');
      const reactorB = Profile(id: 'r2', displayName: 'Jo');

      final profileCubit = _GoldenProfileCubit();
      final presenceCubit = _GoldenPresenceCubit();
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: profileCubit),
            BlocProvider<PresenceCubit>.value(value: presenceCubit),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(size: logicalSize),
              child: TenturaResponsiveScope(
                child: Scaffold(
                  body: SizedBox(
                    width: logicalSize.width,
                    child: RoomMessageTile(
                      message: textMessage(
                        id: 'm7',
                        authorId: 'other',
                        author: other,
                        body: 'Ok',
                        reactionCounts: const {'😠': 2},
                        reactors: const {
                          '😠': [reactorA, reactorB],
                        },
                      ),
                      myProfile: me,
                      onToggleReaction: (_, _) async {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });

    testWidgets('mine reply quote hugs right edge without clipping', (
      tester,
    ) async {
      const compactSize = Size(390, 800);
      final profileCubit = _GoldenProfileCubit();
      final presenceCubit = _GoldenPresenceCubit();

      await tester.binding.setSurfaceSize(compactSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: profileCubit),
            BlocProvider<PresenceCubit>.value(value: presenceCubit),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(size: compactSize),
              child: TenturaResponsiveScope(
                child: Scaffold(
                  body: ListView(
                    children: [
                      RoomMessageTile(
                        message: textMessage(
                          id: 'm-reply-mine-layout',
                          authorId: 'me',
                          author: me,
                          body: 'ok',
                          replyToMessageId: 'parent-layout',
                          replyToAuthorId: 'other',
                          replyToAuthorTitle: 'Alex River',
                          replyToBodyExcerpt:
                              'abcdefghijklmnopqrstuvwxyz wider second line quote excerpt',
                        ),
                        myProfile: me,
                        onToggleReaction: (_, _) async {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final quote = tester.renderObject<RenderBox>(
        find.byType(RoomMessageReplyQuote),
      );
      expect(quote.size.width, lessThanOrEqualTo(compactSize.width));

      final bubble = find.descendant(
        of: find.byType(RoomMessageTile),
        matching: find.byWidgetPredicate(
          (w) => w is Material && w.shape is RoomMessageBubbleShape,
        ),
      );
      final rect = tester.getRect(bubble);
      const farGutter = TenturaSpacing.screenH;
      expect(compactSize.width - rect.right, closeTo(farGutter, 0.5));
    });

    testWidgets('other reply quote fits compact width without clipping', (
      tester,
    ) async {
      const compactSize = Size(390, 800);
      final profileCubit = _GoldenProfileCubit();
      final presenceCubit = _GoldenPresenceCubit();

      await tester.binding.setSurfaceSize(compactSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: profileCubit),
            BlocProvider<PresenceCubit>.value(value: presenceCubit),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(size: compactSize),
              child: TenturaResponsiveScope(
                child: Scaffold(
                  body: ListView(
                    children: [
                      RoomMessageTile(
                        message: textMessage(
                          id: 'm-reply-other-layout',
                          authorId: 'other',
                          author: other,
                          body: 'Reply body',
                          replyToMessageId: 'parent-layout-2',
                          replyToAuthorId: 'me',
                          replyToAuthorTitle: 'Me',
                          replyToBodyExcerpt:
                              'Long quote excerpt that must ellipsize instead of overflowing',
                        ),
                        myProfile: me,
                        onToggleReaction: (_, _) async {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final quote = tester.renderObject<RenderBox>(
        find.byType(RoomMessageReplyQuote),
      );
      expect(quote.size.width, lessThanOrEqualTo(compactSize.width));
    });
  });
}
