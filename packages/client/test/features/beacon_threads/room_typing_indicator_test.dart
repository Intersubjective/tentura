// Typing indicator in a Request's discussion (#766), the widget half.
//
// "Ben is typing…" (or "N people are typing…") sits above the composer while
// other members type, and the composer's own edits are what make the viewer
// show up as typing for everyone else. The state contract (`typingUserIds`)
// and the cubit/repository names are described in room_typing_cubit_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';
import 'support/room_typing_fake_repository.dart';

const _ben = Profile(id: 'u-ben', displayName: 'Ben');
const _cara = Profile(id: 'u-cara', displayName: 'Cara');
const _benRu = Profile(id: 'u-ben', displayName: 'Бен');

RoomState _roomWithTyping(
  List<Profile> members,
  List<String> typingUserIds,
) => roomBodyState().copyWith(
  participants: [
    for (final member in members)
      roomBodyAdmittedParticipant(beaconId: 'b1', profile: member),
  ],
  participantsLoaded: true,
  typingUserIds: typingUserIds,
);

Finder _composerField() => find.descendant(
  of: find.byType(BeaconRoomComposer),
  matching: find.byType(TextField),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('typing indicator above the composer', () {
    testWidgets('one typist is named', (tester) async {
      await pumpBeaconRoomBody(
        tester,
        roomState: _roomWithTyping([_ben, _cara], [_ben.id]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ben is typing…'), findsOneWidget);
    });

    testWidgets('two typists collapse to a count', (tester) async {
      await pumpBeaconRoomBody(
        tester,
        roomState: _roomWithTyping([_ben, _cara], [_ben.id, _cara.id]),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 people are typing…'), findsOneWidget);
      expect(find.textContaining('Ben is typing'), findsNothing);
    });

    testWidgets('the line follows the room: one name, then two, then none', (
      tester,
    ) async {
      final cubit = await pumpBeaconRoomBody(
        tester,
        roomState: _roomWithTyping([_ben, _cara], const []),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('typing…'), findsNothing);

      cubit.emitHarnessState(cubit.state.copyWith(typingUserIds: [_ben.id]));
      await tester.pumpAndSettle();
      expect(find.text('Ben is typing…'), findsOneWidget);

      cubit.emitHarnessState(
        cubit.state.copyWith(typingUserIds: [_ben.id, _cara.id]),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 people are typing…'), findsOneWidget);
      expect(find.text('Ben is typing…'), findsNothing);

      cubit.emitHarnessState(cubit.state.copyWith(typingUserIds: const []));
      await tester.pumpAndSettle();
      expect(find.textContaining('typing…'), findsNothing);
    });

    testWidgets('the line sits above the composer', (tester) async {
      await pumpBeaconRoomBody(
        tester,
        roomState: _roomWithTyping([_ben], [_ben.id]),
      );
      await tester.pumpAndSettle();

      final line = find.text('Ben is typing…');
      expect(line, findsOneWidget);
      expect(
        tester.getBottomLeft(line).dy,
        lessThanOrEqualTo(tester.getTopLeft(_composerField()).dy),
      );
    });

    testWidgets('a name that is not a participant still counts as a person', (
      tester,
    ) async {
      await pumpBeaconRoomBody(
        tester,
        roomState: _roomWithTyping([_ben], ['u-author-without-row', _ben.id]),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 people are typing…'), findsOneWidget);
    });

    group('phone 375×667, Russian', () {
      Future<void> pumpRu(
        WidgetTester tester,
        List<String> typing, {
        List<Profile> members = const [_benRu],
      }) async {
        await usePhoneSurface(tester);
        await pumpBeaconRoomBody(
          tester,
          width: kPhoneSurface.width,
          height: kPhoneSurface.height,
          locale: const Locale('ru'),
          roomState: _roomWithTyping(members, typing),
        );
        await tester.pumpAndSettle();
      }

      void expectRenderedInFull(WidgetTester tester, String text) {
        final finder = find.text(text);
        expect(finder, findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'no layout overflow');
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        expect(paragraph.didExceedMaxLines, isFalse, reason: 'not clipped');
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(kPhoneSurface.width));
      }

      testWidgets('one typist reads «Бен печатает…»', (tester) async {
        await pumpRu(tester, [_benRu.id]);

        expectRenderedInFull(tester, 'Бен печатает…');
      });

      testWidgets('two typists take the «человека» form', (tester) async {
        await pumpRu(tester, ['u-1', 'u-2']);

        expectRenderedInFull(tester, '2 человека печатают…');
      });

      testWidgets('five typists take the «человек» form', (tester) async {
        await pumpRu(tester, ['u-1', 'u-2', 'u-3', 'u-4', 'u-5']);

        expectRenderedInFull(tester, '5 человек печатают…');
      });
    });
  });

  group('typing through the composer and the real cubit', () {
    late RoomTypingFakeRepository repo;
    late RoomCubit cubit;

    setUp(() async {
      await GetIt.I.reset();
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      repo = RoomTypingFakeRepository()
        ..participants = [
          BeaconParticipant(
            id: 'p-me',
            beaconId: kRoomCubitFakeBeaconId,
            userId: kRoomCubitFakeMyUserId,
            userTitle: 'Me',
            role: 0,
            status: 0,
            roomAccess: 1,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
          BeaconParticipant(
            id: 'p-ben',
            beaconId: kRoomCubitFakeBeaconId,
            userId: 'u-ben',
            userTitle: 'Ben',
            role: 0,
            status: 0,
            roomAccess: 1,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        ];
    });

    Future<void> pumpRoom(WidgetTester tester) async {
      cubit = roomCubitForTest(repo, effects: FakeUiEffectPort());
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
      cubit.syncBeaconStatus(BeaconStatus.open);

      GetIt.I
        ..registerSingleton<ImageRepository>(ImageRepository())
        ..registerSingleton<ClipboardImageRepository>(
          ClipboardImageRepository(),
        );
      final profileCubit = GetIt.I<ProfileCubit>();
      await tester.binding.setSurfaceSize(const Size(390, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpPeopleTagsWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<RoomCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(value: profileCubit),
            BlocProvider<PresenceCubit>.value(
              value: RoomBodyHarnessPresenceCubit(),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const MediaQuery(
              data: MediaQueryData(size: Size(390, 720)),
              child: TenturaResponsiveScope(
                child: Scaffold(body: BeaconRoomBody()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('a relayed intent shows the name, a relayed stop removes it', (
      tester,
    ) async {
      await pumpRoom(tester);
      expect(find.text('Ben is typing…'), findsNothing);

      repo.relay('u-ben');
      await tester.pumpAndSettle();
      expect(find.text('Ben is typing…'), findsOneWidget);

      repo.relay('u-ben', typing: false);
      await tester.pumpAndSettle();
      expect(find.text('Ben is typing…'), findsNothing);
    });

    testWidgets('typing in the composer sends one intent per burst', (
      tester,
    ) async {
      await pumpRoom(tester);

      await tester.enterText(_composerField(), 'h');
      await tester.enterText(_composerField(), 'he');
      await tester.enterText(_composerField(), 'hel');
      await tester.pump();

      expect(repo.intents, [true]);
      expect(repo.intentBeaconIds, [kRoomCubitFakeBeaconId]);
    });

    testWidgets('emptying the composer stops typing', (tester) async {
      await pumpRoom(tester);

      await tester.enterText(_composerField(), 'hello');
      await tester.pump();
      await tester.enterText(_composerField(), '');
      await tester.pump();

      expect(repo.intents, [true, false]);
    });

    testWidgets('sending the message stops typing', (tester) async {
      await pumpRoom(tester);

      await tester.enterText(_composerField(), 'hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(repo.createMessageCalls, 1);
      expect(repo.intents, [true, false]);
    });
  });
}
