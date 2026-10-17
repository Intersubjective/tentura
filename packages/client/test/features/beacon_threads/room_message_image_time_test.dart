// A photo with a caption reads caption → photo → time: the time and read mark
// belong to the whole message, so they sit under the photo, not between the
// caption and the photo (#478).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _viewer = Profile(id: 'me', displayName: 'Me');

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => const Stream<ProfileState>.empty();
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      const Stream<Map<String, UserPresenceStatus>>.empty();
}

// Local time: the tile formats `toLocal()`.
final _sentAt = DateTime(2026, 10, 9, 23, 28);

Future<void> _pumpTile(WidgetTester tester, RoomMessage message) async {
  await tester.binding.setSurfaceSize(const Size(900, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: RoomMessageTile(
              message: message,
              myProfile: _viewer,
              onToggleReaction: (_, _) async {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the time of a captioned photo sits under the photo', (
    tester,
  ) async {
    await _pumpTile(
      tester,
      RoomMessage(
        id: 'm1',
        beaconId: 'b1',
        authorId: _viewer.id,
        author: _viewer,
        body: 'Here is the couch',
        createdAt: _sentAt,
        attachments: const [
          RoomMessageAttachment(
            id: 'a1',
            kind: BeaconRoomMessageAttachmentKind.image,
            position: 0,
            mime: 'image/jpeg',
            sizeBytes: 1,
            imageId: 'img-1',
            imageAuthorId: 'me',
          ),
        ],
      ),
    );

    final time = find.textContaining('23:28', findRichText: true);
    expect(time, findsOneWidget);
    final album = find.byType(RoomMessageInlineImageAlbum);
    expect(
      tester.getTopLeft(time).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(album).dy),
    );
    expect(
      tester.getBottomLeft(find.textContaining('Here is the couch')).dy,
      lessThanOrEqualTo(tester.getTopLeft(album).dy),
    );
  });
}
