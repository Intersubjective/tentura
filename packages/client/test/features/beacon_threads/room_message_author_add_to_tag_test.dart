// The author of another person's chat message opens a small menu (Profile,
// Add to tag…) through a visible overflow button, a touch long press on the
// avatar and a mouse secondary tap on the avatar;
// "Add to tag…" opens the add-to-tag sheet of the message's author. The
// viewer's own messages and every message while the people-tags feature is off
// offer nothing, and a plain tap on the avatar still opens the profile.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/presence_avatar.dart';

import '../../support/add_to_tag_sheet_probe.dart';
import '../../support/fake_people_tags_repository.dart';
import '../../support/optional_gate_call.dart';
import '../../support/person_menu_open_way.dart';

const _viewer = Profile(id: 'U-viewer', displayName: 'Viewer');
const _peer = Profile(id: 'U-peer', displayName: 'Peer Person');

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

final _createdAt = DateTime.utc(2026, 10, 1, 12);

RoomMessage _messageBy(Profile author) => RoomMessage(
  id: 'm-${author.id}',
  beaconId: 'b1',
  authorId: author.id,
  author: author,
  body: 'Bring the ladder on Saturday',
  createdAt: _createdAt,
);

void main() {
  late PeopleTagsTestRig rig;

  setUp(() async {
    rig = await PeopleTagsTestRig.create(addToTagProbeRepository(_peer.id));
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  /// [peopleTagsEnabled] null leaves the tile's own default (the gate).
  Future<void> pumpTile(
    WidgetTester tester, {
    required Profile author,
    bool? peopleTagsEnabled,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final screenCubit = ScreenCubit.local();
    addTearDown(screenCubit.close);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
          BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
          BlocProvider<ScreenCubit>.value(value: screenCubit),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(
              child:
                  callWithPeopleTagsGate(
                        RoomMessageTile.new,
                        gate: peopleTagsEnabled,
                        named: {
                          #message: _messageBy(author),
                          #myProfile: _viewer,
                          #onReplyPressed: (RoomMessage _) {},
                          #onToggleReaction: (String _, String _) async {},
                        },
                      )!
                      as Widget,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final avatar = find.byType(PresenceAvatar);

  /// The visible control of the message author's menu: an overflow button
  /// drawn with the message, without hovering.
  final overflowButton = find.descendant(
    of: find.byType(RoomMessageTile),
    matching: find.byIcon(Icons.more_vert),
  );

  group('Chat author avatar: add to tag', () {
    for (final way in PersonMenuOpenWay.values) {
      testWidgets(
        'a ${way.name} opens a menu with Profile and Add to tag…',
        (tester) async {
          await pumpTile(tester, author: _peer, peopleTagsEnabled: true);
          expect(find.text('Add to tag…'), findsNothing);

          await way.open(tester, overflow: overflowButton, target: avatar);

          expect(find.text('Profile'), findsOneWidget);
          expect(find.text('Add to tag…'), findsOneWidget);
        },
      );

      testWidgets(
        'Add to tag… opened by ${way.name} opens the sheet for the author',
        (tester) async {
          await pumpTile(tester, author: _peer, peopleTagsEnabled: true);

          await way.open(tester, overflow: overflowButton, target: avatar);
          await tester.tap(find.text('Add to tag…'));

          await expectAddToTagSheetIsForPerson(
            tester,
            rig.repository,
            _peer.id,
          );
        },
      );
    }

    testWidgets('a plain tap on the avatar opens no menu', (tester) async {
      await pumpTile(tester, author: _peer, peopleTagsEnabled: true);

      await tester.tap(avatar);
      await tester.pumpAndSettle();

      expect(find.text('Add to tag…'), findsNothing);
    });

    testWidgets('the viewer own message has no avatar and no author menu', (
      tester,
    ) async {
      await pumpTile(tester, author: _viewer, peopleTagsEnabled: true);

      expect(avatar, findsNothing);
      expect(overflowButton, findsNothing);
      await expectNoPersonMenuFromGestures(
        tester,
        target: find.byType(RoomMessageTile),
        otherEntries: const ['Profile'],
      );
    });

    testWidgets('is absent when the feature is switched off', (tester) async {
      await pumpTile(tester, author: _peer, peopleTagsEnabled: false);

      expect(overflowButton, findsNothing);
      await expectNoPersonMenuFromGestures(
        tester,
        target: avatar,
        otherEntries: const ['Profile'],
      );
    });

    testWidgets('is absent by default while the feature gate is off', (
      tester,
    ) async {
      await pumpTile(tester, author: _peer);

      expect(overflowButton, findsNothing);
      await expectNoPersonMenuFromGestures(
        tester,
        target: avatar,
        otherEntries: const ['Profile'],
      );
    });
  });
}
