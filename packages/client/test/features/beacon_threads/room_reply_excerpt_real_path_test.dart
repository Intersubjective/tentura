import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';
import 'support/room_hint_wire_harness.dart';

void main() {
  testWidgets(
    'reply banner omits a combining sequence crossing the rune limit after loading a message',
    (tester) async {
      await usePhoneSurface(tester);
      await GetIt.I.reset();
      addTearDown(GetIt.I.reset);
      registerRoomCubitProfileCubit(roomHintWireViewerId);
      GetIt.I
        ..registerSingleton<ImageRepository>(ImageRepository())
        ..registerSingleton<ClipboardImageRepository>(
          ClipboardImageRepository(),
        );

      const prefix =
          'aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀'
          'aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀'
          'aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀';
      final server = RoomHintWireServer()
        ..messageRows = [
          roomHintWireMessageRow(
            id: 'Rparent000001',
            authorId: 'Uauthor000001',
            authorTitle: 'Анна',
            createdAt: '2026-06-30T12:00:00Z',
            body: '${prefix}e\u0301tail',
          ),
        ];
      final wire = (await tester.runAsync(() => RoomHintWire.start(server)))!;
      addTearDown(() => tester.runAsync(wire.close));
      final repository = RoomOverRealHintWireRepository(wire.repository);
      late RoomCubit cubit;
      await tester.runAsync(() async {
        cubit = roomCubitForTest(
          repository,
          realtimeSyncCase: RealtimeSyncCase(wire.realtime),
        );
        await awaitRoomCubitLoad(cubit).timeout(const Duration(seconds: 5));
        cubit.syncBeaconStatus(BeaconStatus.open);
      });
      addTearDown(() => tester.runAsync(cubit.close));
      expect(server.queried, contains('RoomMessageList'));
      // This parent came through HTTP -> Ferry -> repository mapper -> cubit.
      // No RoomMessage fixture or hand-built reply-target state is injected.
      final parent = cubit.state.messages.single;
      expect(parent.body, '${prefix}e\u0301tail');
      cubit.startReplyTo(parent);

      const viewer = Profile(id: roomHintWireViewerId, displayName: 'Я');
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<RoomCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(
              value: RoomBodyHarnessProfileCubit(viewer),
            ),
            BlocProvider<PresenceCubit>.value(
              value: RoomBodyHarnessPresenceCubit(),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('ru'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const TenturaResponsiveScope(
              child: Scaffold(body: BeaconRoomBody()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(
        find.text(lookupL10n(const Locale('ru')).beaconRoomReplyingTo('Анна')),
        findsOneWidget,
      );
      expect(find.text('$prefix…'), findsOneWidget);
      expect(find.text('${prefix}e…'), findsNothing);
    },
  );
}
