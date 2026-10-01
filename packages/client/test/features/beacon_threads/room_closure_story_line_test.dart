// A22: system message kind 3 (`BeaconRoomSystemMessageKind.closureStory`) —
// the closure story written by the author. The server inserts it with the
// story as `body` and no payload. `RoomMessageTile` must render it as a
// system card in the room, not as an ordinary chat bubble:
//  - the story text is shown, without a sender name header;
//  - it is a system card: placed the same (centered) whether the viewer or
//    someone else wrote it, unlike chat bubbles that follow authorship.
// Today kind 3 falls through to the generic chat row, so this fails.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _viewer = Profile(id: 'viewer', displayName: 'Viewer');
const _author = Profile(id: 'u-anna', displayName: 'Anna Author');

const _story =
    'Мы собрали всё за выходные: Борис привёз лодку, Оля организовала '
    'людей, а Иван всю ночь чинил мотор. Без каждого из них ничего бы не '
    'вышло, спасибо вам. Отдельное спасибо тем, кто пришёл на разгрузку '
    'в субботу утром, когда никто уже не ждал помощи.';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

RoomMessage _storyMessage(Profile author) => RoomMessage(
  id: 'story-1',
  beaconId: 'b-story',
  authorId: author.id,
  author: author,
  body: _story,
  createdAt: DateTime.utc(2026, 9, 30, 12),
  systemMessageKind: BeaconRoomSystemMessageKind.closureStory,
);

Widget _harness(RoomMessage message) => MultiBlocProvider(
  providers: [
    BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
    BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
    BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
  ],
  child: MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('ru'),
    home: MediaQuery(
      data: const MediaQueryData(size: Size(400, 900)),
      child: TenturaResponsiveScope(
        child: Scaffold(
          body: SingleChildScrollView(
            child: RoomMessageTile(
              message: message,
              myProfile: _viewer,
              onToggleReaction: (_, _) async {},
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  Finder storyText() => find.textContaining(_story, findRichText: true);

  testWidgets('closureStory renders the story as a system card, not a chat '
      'bubble', (tester) async {
    // Ordinary bubbles sit left for others and right for the viewer; a system
    // card does not depend on who wrote the message.
    await tester.pumpWidget(_harness(_storyMessage(_author)));
    await tester.pumpAndSettle();
    expect(storyText(), findsOneWidget);
    final fromOther = tester.getCenter(storyText()).dx;
    // No sender chrome.
    expect(find.text('Anna Author'), findsNothing);
    expect(find.text('System'), findsNothing);

    await tester.pumpWidget(_harness(_storyMessage(_viewer)));
    await tester.pumpAndSettle();
    expect(storyText(), findsOneWidget);
    final fromViewer = tester.getCenter(storyText()).dx;

    expect(
      (fromOther - fromViewer).abs(),
      lessThan(2),
      reason:
          'story placed at dx=$fromOther (other) vs $fromViewer (viewer): '
          'a system card is not aligned by authorship',
    );
    // Centered in the tile like the other room system lines.
    final tileCenter = tester.getCenter(find.byType(RoomMessageTile)).dx;
    expect((fromViewer - tileCenter).abs(), lessThan(24));
  });
}
