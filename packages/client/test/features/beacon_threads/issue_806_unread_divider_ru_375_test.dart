// #806: unread divider pill shows its full RU label at 375 px in Post chat.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_unread_divider.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../support/phone_surface.dart';

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'me', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _PresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

void main() {
  testWidgets(
    'RU 375×667: Post chat unread pill is whole and clear of bubbles',
    (
      tester,
    ) async {
      await usePhoneSurface(tester);
      const unreadCount = 2;
      final ru = lookupL10n(const Locale('ru'));
      final label = ru.beaconRoomUnreadDividerCount(unreadCount);

      final base = DateTime.utc(2026, 10, 30, 12);
      final read = RoomMessage(
        id: 'read',
        beaconId: 'post-1',
        authorId: 'peer',
        author: const Profile(id: 'peer', displayName: 'Peer'),
        body:
            'Read message with a tall bubble body that wraps on narrow phones.',
        createdAt: base,
      );
      final unread = RoomMessage(
        id: 'm1',
        beaconId: 'post-1',
        authorId: 'peer',
        author: const Profile(id: 'peer', displayName: 'Peer'),
        body: 'First unread notice line',
        createdAt: base.add(const Duration(minutes: 1)),
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: _ProfileCubit()),
            BlocProvider<PresenceCubit>.value(value: _PresenceCubit()),
          ],
          child: MaterialApp(
            locale: const Locale('ru'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(size: kPhoneSurface),
              child: TenturaResponsiveScope(
                child: Scaffold(
                  body: BasicChatBody(
                    messages: [read, unread],
                    myProfile: const Profile(id: 'me', displayName: 'Me'),
                    participants: const [],
                    isLoading: false,
                    imageRepository: ImageRepository(),
                    clipboardImageRepository: ClipboardImageRepository(),
                    enableComposerAttachments: false,
                    enableParticipantMentions: false,
                    onSend: (_, _) async => true,
                    onToggleReaction: (_, _) async {},
                    firstUnreadMessageId: 'm1',
                    unreadCount: unreadCount,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final divider = find.byType(RoomUnreadDivider);
      expect(divider, findsOneWidget);

      final labelFinder = find.descendant(
        of: divider,
        matching: find.text(label),
      );
      expect(labelFinder, findsOneWidget);

      final paragraph = tester.renderObject<RenderParagraph>(labelFinder);
      expect(paragraph.text.toPlainText(), label);
      expect(paragraph.didExceedMaxLines, isFalse);

      final dividerBox = tester.renderObject<RenderBox>(divider);
      final unreadTile = tester.renderObject<RenderBox>(
        find.byType(RoomMessageTile).last,
      );
      expect(
        dividerBox.localToGlobal(Offset.zero).dy + dividerBox.size.height,
        lessThanOrEqualTo(unreadTile.localToGlobal(Offset.zero).dy + 1),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
