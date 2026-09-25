// tentura-9f0 landing gate acceptance (trial merge tentura-rsm)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/room_message_receipt.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

class _LandingProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _LandingPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

/// Landing-check pump for tentura-w4f. Acceptance: optional [theme] must drive
/// [MaterialApp.theme] so dark reply-quote goldens match committed PNGs.
Future<void> pumpRoomMessageLandingGolden(
  WidgetTester tester, {
  required String goldenName,
  required RoomMessage message,
  required Profile myProfile,
  RoomMessageReceipt? receipt,
  ThemeData? theme,
}) async {
  final profileCubit = _LandingProfileCubit();
  final presenceCubit = _LandingPresenceCubit();
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: profileCubit),
        BlocProvider<PresenceCubit>.value(value: presenceCubit),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        theme: theme ?? TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 200)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: RepaintBoundary(
                key: const Key('landing_golden'),
                child: SizedBox(
                  width: 360,
                  child: RoomMessageTile(
                    message: message,
                    myProfile: myProfile,
                    receipt: receipt,
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

  if (theme != null) {
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      materialApp.theme,
      same(theme),
      reason:
          'landing golden pump must apply the optional theme parameter to '
          'MaterialApp.theme',
    );
  }

  await expectLater(
    find.byKey(const Key('landing_golden')),
    matchesGoldenFile('goldens/room_message_$goldenName.png'),
  );
}

void main() {
  final createdAt = DateTime.utc(2026, 5, 22, 12, 34);

  const me = Profile(id: 'me', displayName: 'Me');
  const other = Profile(id: 'other', displayName: 'Alex River');

  RoomMessage textMessage({
    required String id,
    required String authorId,
    required Profile author,
    required String body,
    String? replyToMessageId,
    String? replyToAuthorId,
    String? replyToAuthorTitle,
    String? replyToBodyExcerpt,
  }) => RoomMessage(
    id: id,
    beaconId: 'b1',
    authorId: authorId,
    body: body,
    createdAt: createdAt,
    author: author,
    replyToMessageId: replyToMessageId,
    replyToAuthorId: replyToAuthorId,
    replyToAuthorTitle: replyToAuthorTitle,
    replyToBodyExcerpt: replyToBodyExcerpt,
  );

  group('room message reply quote landing check (tentura-w4f)', () {
    testWidgets('reply_quote_mine_light matches committed landing golden', (
      tester,
    ) async {
      await pumpRoomMessageLandingGolden(
        tester,
        goldenName: 'reply_quote_mine_light',
        theme: TenturaTheme.light(),
        message: textMessage(
          id: 'm-landing-mine-light',
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
    }, tags: 'golden');

    testWidgets('reply_quote_other_light matches committed landing golden', (
      tester,
    ) async {
      await pumpRoomMessageLandingGolden(
        tester,
        goldenName: 'reply_quote_other_light',
        theme: TenturaTheme.light(),
        message: textMessage(
          id: 'm-landing-other-light',
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
    }, tags: 'golden');

    testWidgets('reply_quote_mine_dark matches committed landing golden', (
      tester,
    ) async {
      await pumpRoomMessageLandingGolden(
        tester,
        goldenName: 'reply_quote_mine_dark',
        theme: TenturaTheme.dark(),
        message: textMessage(
          id: 'm-landing-mine-dark',
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
    }, tags: 'golden');

    testWidgets('reply_quote_other_dark matches committed landing golden', (
      tester,
    ) async {
      await pumpRoomMessageLandingGolden(
        tester,
        goldenName: 'reply_quote_other_dark',
        theme: TenturaTheme.dark(),
        message: textMessage(
          id: 'm-landing-other-dark',
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
    }, tags: 'golden');

    testWidgets(
      'reply_quote_mine_dark_with_sent_receipt matches committed landing golden',
      (tester) async {
        await pumpRoomMessageLandingGolden(
          tester,
          goldenName: 'reply_quote_mine_dark_sent_receipt',
          theme: TenturaTheme.dark(),
          message: textMessage(
            id: 'm-landing-mine-dark-receipt',
            authorId: 'me',
            author: me,
            body: 'Sure, tomorrow works',
            replyToMessageId: 'parent-1',
            replyToAuthorId: 'other',
            replyToAuthorTitle: 'Alex River',
            replyToBodyExcerpt: 'can you bring the ladder tomorrow morning',
          ),
          myProfile: me,
          receipt: const RoomMessageReceipt(
            state: RoomMessageReceiptState.sent,
          ),
        );
      },
      tags: 'golden',
    );
  });
}
