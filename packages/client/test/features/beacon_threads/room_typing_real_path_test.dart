// Typing indicator in a Request's discussion (#766) over the real transport
// path: a server frame enters the socket, crosses the real RemoteApiService
// and BeaconThreadsRepository into the room cubit and shows up as text above
// the composer; the viewer's composer edits leave as the server's
// `room_typing` message frame. Only the socket and the token endpoint are
// faked (see support/room_typing_wire_harness.dart).
//
// Contract beyond room_typing_cubit_test.dart: `BeaconThreadsRepository` keeps
// its constructor (remote client, realtime port) and reads/sends typing frames
// through that same remote client's websocket. The wire shapes are the
// server's (packages/server .../websocket_path_room_typing.dart):
//   to the server  {"type":"message","path":"room_typing",
//                   "payload":{"intent":"start"|"stop","beacon_id":<id>}}
//   from the server {"type":"subscription","path":"room_typing",
//                   "payload":{"beacon_id","user_id","typing":bool}}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../support/people_tags_widget_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';
import 'support/room_typing_wire_harness.dart';

BeaconParticipant _member(String userId, String name) => BeaconParticipant(
  id: 'p-$userId',
  beaconId: kRoomCubitFakeBeaconId,
  userId: userId,
  userTitle: name,
  role: 0,
  status: 0,
  roomAccess: 1,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Finder _composerField() => find.descendant(
  of: find.byType(BeaconRoomComposer),
  matching: find.byType(TextField),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('typing over the real websocket stack', () {
    late RoomTypingWire wire;
    late RoomCubit cubit;

    Future<void> pumpRoom(WidgetTester tester) async {
      await GetIt.I.reset();
      // The viewer is the account the socket authenticates as, so a filter on
      // "me" is checked against the real signed-in id.
      registerRoomCubitProfileCubit(roomTypingWireViewerId);
      wire = (await tester.runAsync(RoomTypingWire.start))!;
      addTearDown(() => tester.runAsync(wire.close));

      final repo = RoomOverRealTypingRepository(wire.repository)
        ..participants = [
          _member(roomTypingWireViewerId, 'Me'),
          _member('u-ben', 'Ben'),
          _member('u-cara', 'Cara'),
        ];
      cubit = roomCubitForTest(
        repo,
        effects: FakeUiEffectPort(),
        realtimeSyncCase: RealtimeSyncCase(wire.realtime),
      );
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

    Future<void> serverRelays(
      WidgetTester tester,
      String userId, {
      required bool typing,
      String beaconId = kRoomCubitFakeBeaconId,
    }) async {
      await tester.runAsync(() async {
        wire.relayFromServer(
          beaconId: beaconId,
          userId: userId,
          typing: typing,
        );
      });
      await settleRoomTypingWire(tester);
    }

    testWidgets(
      'frames from the server turn into one name, then a count, then nothing',
      (tester) async {
        await pumpRoom(tester);
        expect(find.textContaining('typing…'), findsNothing);

        await serverRelays(tester, 'u-ben', typing: true);
        expect(find.text('Ben is typing…'), findsOneWidget);

        await serverRelays(tester, 'u-cara', typing: true);
        expect(find.text('2 people are typing…'), findsOneWidget);
        expect(find.text('Ben is typing…'), findsNothing);

        await serverRelays(tester, 'u-cara', typing: false);
        expect(find.text('Ben is typing…'), findsOneWidget);

        await serverRelays(tester, 'u-ben', typing: false);
        expect(find.textContaining('typing…'), findsNothing);
      },
    );

    testWidgets('a frame naming the signed-in viewer is never shown', (
      tester,
    ) async {
      await pumpRoom(tester);

      await serverRelays(tester, roomTypingWireViewerId, typing: true);
      expect(find.textContaining('typing…'), findsNothing);

      // Someone else typing alongside is still shown by name, not counted
      // with the viewer.
      await serverRelays(tester, 'u-ben', typing: true);
      expect(find.text('Ben is typing…'), findsOneWidget);

      // Ben is still listed, so his expiry timer is live: leave the room
      // before the test ends, as the app does when the screen closes.
      await tester.runAsync(cubit.close);
    });

    testWidgets('frames for another request or in a bad shape show nothing', (
      tester,
    ) async {
      await pumpRoom(tester);

      await serverRelays(
        tester,
        'u-ben',
        typing: true,
        beaconId: 'some-other-request',
      );
      await tester.runAsync(() async {
        wire
          ..receiveRaw({
            'type': 'subscription',
            'path': 'room_typing',
            'payload': {'beacon_id': kRoomCubitFakeBeaconId, 'typing': true},
          })
          ..receiveRaw({
            'type': 'subscription',
            'path': 'room_typing',
            'payload': {
              'beacon_id': kRoomCubitFakeBeaconId,
              'user_id': 'u-ben',
              'typing': 'yes',
            },
          })
          ..receiveRaw({
            'type': 'subscription',
            'path': 'room_typing',
            'payload': 'garbage',
          });
      });
      await settleRoomTypingWire(tester);

      expect(find.textContaining('typing…'), findsNothing);
    });

    testWidgets(
      'the viewer typing leaves as one start frame for this request',
      (tester) async {
        await pumpRoom(tester);

        await tester.enterText(_composerField(), 'h');
        await tester.enterText(_composerField(), 'he');
        await tester.enterText(_composerField(), 'hel');
        await settleRoomTypingWire(tester);

        expect(wire.socket.typingFramesSent, [
          {
            'type': 'message',
            'path': 'room_typing',
            'payload': {'intent': 'start', 'beacon_id': kRoomCubitFakeBeaconId},
          },
        ]);
      },
    );

    testWidgets('emptying the composer leaves as a stop frame', (tester) async {
      await pumpRoom(tester);

      await tester.enterText(_composerField(), 'hello');
      await settleRoomTypingWire(tester);
      await tester.enterText(_composerField(), '');
      await settleRoomTypingWire(tester);

      expect(
        [
          for (final f in wire.socket.typingFramesSent)
            (f['payload'] as Map)['intent'],
        ],
        ['start', 'stop'],
      );
    });

    testWidgets('sending the message leaves as a stop frame', (tester) async {
      await pumpRoom(tester);

      await tester.enterText(_composerField(), 'hello');
      await settleRoomTypingWire(tester);
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      await settleRoomTypingWire(tester);

      expect(
        [
          for (final f in wire.socket.typingFramesSent)
            (f['payload'] as Map)['intent'],
        ],
        ['start', 'stop'],
      );
    });
  });
}
