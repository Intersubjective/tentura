// #1105: unsent Post reply survives leaving and reopening the room (same
// session); deep-link back tab is covered in browse_deep_link_post_owner_tab_test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/service/unsaved_changes_guard_impl.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/unsaved_changes_guard_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon_threads/data/service/beacon_room_composer_draft_store.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';
import 'support/room_hint_wire_harness.dart';

const _longRuReply =
    'Черновик ответа в чате поста с длинным русским текстом, который '
    'должен целиком остаться в поле после выхода из комнаты и повторного '
    'открытия в той же сессии, без обрезки и переполнения.';

BeaconParticipant _admitted(String userId, String title) => BeaconParticipant(
  id: 'p-$userId',
  beaconId: kRoomCubitFakeBeaconId,
  userId: userId,
  userTitle: title,
  role: BeaconParticipantRoleBits.addressee,
  status: 0,
  roomAccess: RoomAccessBits.admitted,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Finder _composerField() => find.descendant(
  of: find.byType(BeaconRoomComposer),
  matching: find.byType(TextField),
);

Future<void> _pumpPostRoom(
  WidgetTester tester, {
  required RoomCubit cubit,
  required Profile viewer,
}) async {
  final getIt = GetIt.I;
  if (!getIt.isRegistered<ImageRepository>()) {
    getIt.registerSingleton<ImageRepository>(ImageRepository());
  }
  if (!getIt.isRegistered<ClipboardImageRepository>()) {
    getIt.registerSingleton<ClipboardImageRepository>(
      ClipboardImageRepository(),
    );
  }

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
          child: Scaffold(
            body: BeaconRoomBody(
              capabilities: RoomCapabilities.post(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('#1105 post reply draft', () {
    testWidgets('RU 375×667: type, leave room, reopen keeps long reply text', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      resetBeaconRoomComposerDraftStoreForTest();
      await GetIt.I.reset();
      GetIt.I.registerSingleton<UnsavedChangesGuardPort>(
        UnsavedChangesGuard(),
      );

      final server = RoomHintWireServer();
      late RoomHintWire wire;
      await tester.runAsync(() async {
        wire = await RoomHintWire.start(server);
      });
      addTearDown(() => tester.runAsync(wire.close));

      final repo = RoomOverRealHintWireRepository(wire.repository)
        ..participants = [
          _admitted(roomHintWireViewerId, 'Мария'),
        ];

      const viewer = Profile(
        id: roomHintWireViewerId,
        displayName: 'Мария',
      );
      registerRoomCubitProfileCubit(roomHintWireViewerId);

      late RoomCubit first;
      await tester.runAsync(() async {
        first = roomCubitForTest(
          repo,
          effects: FakeUiEffectPort(),
          realtimeSyncCase: RealtimeSyncCase(wire.realtime),
        );
        await awaitRoomCubitLoad(first);
        first.syncBeaconStatus(BeaconStatus.open);
      });
      addTearDown(() => first.close());

      await _pumpPostRoom(tester, cubit: first, viewer: viewer);
      await tester.enterText(_composerField(), _longRuReply);
      await tester.pump();

      expect(readBeaconRoomComposerDraft(kRoomCubitFakeBeaconId), _longRuReply);

      await tester.runAsync(() => first.close());
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      late RoomCubit second;
      await tester.runAsync(() async {
        second = roomCubitForTest(
          repo,
          effects: FakeUiEffectPort(),
          realtimeSyncCase: RealtimeSyncCase(wire.realtime),
        );
        await awaitRoomCubitLoad(second);
        second.syncBeaconStatus(BeaconStatus.open);
      });
      addTearDown(() => second.close());

      await _pumpPostRoom(tester, cubit: second, viewer: viewer);

      final field = tester.widget<TextField>(_composerField());
      expect(field.controller?.text, _longRuReply);
      expect(find.textContaining('Черновик ответа'), findsOneWidget);

      final size = tester.getSize(find.byType(BeaconRoomComposer));
      expect(size.width, lessThanOrEqualTo(375));
      expect(tester.takeException(), isNull);
    });

    test('successful send clears in-memory draft', () async {
      resetBeaconRoomComposerDraftStoreForTest();
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fake = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId);
      final cubit = roomCubitForTest(fake);
      await awaitRoomCubitLoad(cubit);
      cubit
        ..syncBeaconStatus(BeaconStatus.open)
        ..composerTextChanged(_longRuReply);
      expect(readBeaconRoomComposerDraft(kRoomCubitFakeBeaconId), _longRuReply);

      await cubit.sendMessage(body: _longRuReply);
      expect(readBeaconRoomComposerDraft(kRoomCubitFakeBeaconId), isNull);
      await cubit.close();
    });
  });
}
