import 'package:flutter/material.dart';
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

void main() {
  testWidgets(
    'pinned jump target survives auto-follow when bottom-scrolled',
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
      await tester.pump(const Duration(milliseconds: 100));

      final state = bodyKey.currentState!;
      final bottomPosition = _listScrollableState(tester).position;
      bottomPosition.jumpTo(bottomPosition.maxScrollExtent);
      await tester.pump();

      state.onRoomDataChangedForViewport(
        firstUnreadMessageId: null,
        messagesEmpty: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(state.isViewportScrollDone, isTrue);
      final pinnedBottom = _listScrollableState(tester).position;
      expect(
        pinnedBottom.pixels,
        greaterThan(pinnedBottom.maxScrollExtent - 80),
      );

      await pumpBody(
        messages: [historical, ...recentMessages],
        pendingJumpMessageId: 'historical-parent',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final afterInsert = _listScrollableState(tester).position;
      expect(
        afterInsert.pixels,
        lessThan(afterInsert.maxScrollExtent - 40),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
