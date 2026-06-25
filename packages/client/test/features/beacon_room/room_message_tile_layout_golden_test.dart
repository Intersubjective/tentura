import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_tile.dart';
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
  }) =>
      RoomMessage(
        id: id,
        beaconId: 'b1',
        authorId: authorId,
        body: body,
        createdAt: createdAt,
        author: author,
        reactionCounts: reactionCounts,
        reactors: reactors,
        attachments: attachments,
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
  }, skip: 'Goldens disabled');

  group('room message layout', () {
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
  });
}
