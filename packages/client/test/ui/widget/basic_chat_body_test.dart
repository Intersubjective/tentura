import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'me', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _TestPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

void main() {
  Future<void> pumpBasicChatBody(
    WidgetTester tester, {
    required double width,
  }) async {
    final message = RoomMessage(
      id: 'm1',
      beaconId: 'b1',
      authorId: 'other',
      author: const Profile(id: 'other', displayName: 'Alex'),
      body: 'A wide room message',
      createdAt: DateTime.utc(2026, 6, 30, 12),
    );

    await tester.binding.setSurfaceSize(Size(width, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
          BlocProvider<PresenceCubit>.value(value: _TestPresenceCubit()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 720)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: BasicChatBody(
                  messages: [message],
                  myProfile: const Profile(id: 'me', displayName: 'Me'),
                  participants: const [],
                  isLoading: false,
                  imageRepository: ImageRepository(),
                  enableComposerAttachments: false,
                  enableParticipantMentions: false,
                  onSend: (_, _) async {},
                  onToggleReaction: (_, _) async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('wide windows center chat list and composer in a 720px column', (
    tester,
  ) async {
    await pumpBasicChatBody(tester, width: 1400);

    expect(tester.getSize(find.byType(ListView)).width, 720);
    expect(tester.getTopLeft(find.byType(TextField)).dx, greaterThan(340));
  });

  testWidgets('regular windows keep chat full panel width', (tester) async {
    await pumpBasicChatBody(tester, width: 720);

    expect(tester.getSize(find.byType(ListView)).width, 720);
  });

  testWidgets(
    'composer stays keyboard-enabled during visible room refresh with unvoted poll',
    (tester) async {
      const poll = RoomPollData(
        id: 'poll-1',
        question: 'Where should we meet?',
        totalVotes: 0,
        myVariantIds: [],
        variants: [
          RoomPollVariant(
            id: 'a',
            description: 'Option A',
            votesCount: 0,
          ),
          RoomPollVariant(
            id: 'b',
            description: 'Option B',
            votesCount: 0,
          ),
        ],
      );
      final message = RoomMessage(
        id: 'm1',
        beaconId: 'b1',
        authorId: 'other',
        author: const Profile(id: 'other', displayName: 'Alex'),
        body: '',
        createdAt: DateTime.utc(2026, 6, 27, 12),
        linkedPollingId: poll.id,
        pollDataJson: poll.encode(),
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
            BlocProvider<PresenceCubit>.value(value: _TestPresenceCubit()),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(size: Size(390, 720)),
              child: TenturaResponsiveScope(
                child: Scaffold(
                  body: BasicChatBody(
                    messages: [message],
                    myProfile: const Profile(id: 'me', displayName: 'Me'),
                    participants: const [],
                    isLoading: true,
                    imageRepository: ImageRepository(),
                    enableComposerAttachments: false,
                    enableParticipantMentions: false,
                    onSend: (_, _) async {},
                    onToggleReaction: (_, _) async {},
                    onVotePoll: (_, _, _, {score}) async {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);

      await tester.tap(find.text('Option A'));
      await tester.pump();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.pump();

      expect(tester.testTextInput.isVisible, isTrue);
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  testWidgets('auto-scrolls to latest when own message is appended', (
    tester,
  ) async {
    final chatKey = GlobalKey<BasicChatBodyState>();
    final baseMessages = List<RoomMessage>.generate(
      40,
      (i) => RoomMessage(
        id: 'm$i',
        beaconId: 'b1',
        authorId: 'other',
        author: const Profile(id: 'other', displayName: 'Alex'),
        body: 'Background message $i',
        createdAt: DateTime.utc(2026, 6, 30, 12).add(Duration(minutes: i)),
      ),
    );

    Future<void> pumpMessages(List<RoomMessage> messages) async {
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
            BlocProvider<PresenceCubit>.value(value: _TestPresenceCubit()),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(size: Size(390, 720)),
              child: TenturaResponsiveScope(
                child: Scaffold(
                  body: BasicChatBody(
                    key: chatKey,
                    messages: messages,
                    myProfile: const Profile(id: 'me', displayName: 'Me'),
                    participants: const [],
                    isLoading: false,
                    imageRepository: ImageRepository(),
                    enableComposerAttachments: false,
                    enableParticipantMentions: false,
                    onSend: (_, _) async {},
                    onToggleReaction: (_, _) async {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpMessages(baseMessages);
    chatKey.currentState!.onRoomDataChangedForViewport(
      firstUnreadMessageId: null,
      messagesEmpty: false,
    );
    await tester.pumpAndSettle();

    final listScrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    final before = tester.state<ScrollableState>(listScrollable).position
      ..jumpTo(0);
    await tester.pumpAndSettle();
    expect(before.pixels, lessThan(before.maxScrollExtent - 56));

    await pumpMessages([
      ...baseMessages,
      RoomMessage(
        id: 'local:new',
        beaconId: 'b1',
        authorId: 'me',
        author: const Profile(id: 'me', displayName: 'Me'),
        body: 'Just sent by me',
        createdAt: DateTime.utc(2026, 6, 30, 13),
      ),
    ]);
    await tester.pumpAndSettle();

    final after = tester.state<ScrollableState>(listScrollable).position;
    expect(after.pixels, closeTo(after.maxScrollExtent, 1));
    expect(find.textContaining('Just sent by me'), findsOneWidget);
  });
}
