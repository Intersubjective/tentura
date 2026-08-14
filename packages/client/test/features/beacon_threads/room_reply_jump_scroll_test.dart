import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import 'support/room_body_harness.dart';

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

ScrollableState _listScrollableState(WidgetTester tester) {
  final listScrollable = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(listScrollable);
}

Future<void> _pumpUntilViewportDone(
  WidgetTester tester,
  GlobalKey<BasicChatBodyState> bodyKey, {
  int maxFrames = 40,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (bodyKey.currentState?.isViewportScrollDone == true) {
      return;
    }
  }
}

void main() {
  testWidgets(
    'pinned jump scrolls to historical target instead of max extent',
    (tester) async {
      final base = DateTime.utc(2026, 6, 30, 12);
      final recentMessages = List<RoomMessage>.generate(
        24,
        (i) => RoomMessage(
          id: 'recent-$i',
          beaconId: 'b1',
          authorId: 'peer',
          author: const Profile(id: 'peer', displayName: 'Peer'),
          body: 'Recent message $i with enough text to grow the list height',
          createdAt: base.add(Duration(minutes: i)),
        ),
      );
      final historical = RoomMessage(
        id: 'historical-parent',
        beaconId: 'b1',
        authorId: 'old-peer',
        author: const Profile(id: 'old-peer', displayName: 'Old'),
        body: 'Historical parent message body for jump regression',
        createdAt: base.subtract(const Duration(hours: 2)),
      );

      final bodyKey = GlobalKey<BasicChatBodyState>();

      Future<void> pumpBody({
        required List<RoomMessage> messages,
        String? pendingJumpMessageId,
      }) {
        return tester.pumpWidget(
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
                      key: bodyKey,
                      messages: messages,
                      pendingJumpMessageId: pendingJumpMessageId,
                      myProfile: const Profile(id: 'me', displayName: 'Me'),
                      participants: const [],
                      isLoading: false,
                      imageRepository: ImageRepository(),
                      clipboardImageRepository: ClipboardImageRepository(),
                      enableComposerAttachments: false,
                      enableParticipantMentions: false,
                      onSend: (_, _) async => true,
                      onToggleReaction: (_, _) async {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      await tester.binding.setSurfaceSize(const Size(390, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpBody(messages: recentMessages);
      await tester.pump();

      final state = bodyKey.currentState!;
      state.onRoomDataChangedForViewport(
        firstUnreadMessageId: null,
        messagesEmpty: false,
      );
      await _pumpUntilViewportDone(tester, bodyKey);

      final bottomPosition = _listScrollableState(tester).position;
      bottomPosition.jumpTo(bottomPosition.maxScrollExtent);
      await tester.pump();

      expect(state.isViewportScrollDone, isTrue);
      final pinnedBottom = _listScrollableState(tester).position;
      expect(
        pinnedBottom.pixels,
        greaterThan(pinnedBottom.maxScrollExtent - 80),
      );

      // Historical row and pending jump id arrive in one widget update.
      await pumpBody(
        messages: [historical, ...recentMessages],
        pendingJumpMessageId: 'historical-parent',
      );
      await tester.pump();

      final afterInsert = _listScrollableState(tester).position;
      expect(
        afterInsert.pixels,
        lessThan(afterInsert.maxScrollExtent - 40),
        reason:
            'auto-follow must not jump to the new bottom while pendingJumpMessageId is set',
      );

      final scrolled = await pumpWhileScrolling(
        tester,
        state.scrollToMessage('historical-parent'),
      );
      expect(scrolled, isTrue);

      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final finalPosition = _listScrollableState(tester).position;
      expect(
        finalPosition.pixels,
        lessThan(finalPosition.maxScrollExtent - 40),
        reason: 'viewport must land on the historical target, not the bottom',
      );
      expect(
        finalPosition.pixels,
        lessThan(pinnedBottom.pixels - 40),
        reason: 'scroll must move up from the bottom-scrolled position',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
