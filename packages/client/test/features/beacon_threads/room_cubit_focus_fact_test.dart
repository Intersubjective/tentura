// A room opened with the `focus_fact` route param (arrival at the source of
// a copied fact, plan §6.1) puts that fact in focus once its facts have
// loaded: RoomCubit sets pendingFactsFocusFactId after the first fact load,
// and the room body then opens the focused fact's actions sheet.
//
// `focusFactId` is the RoomCubit constructor argument that carries the
// route's focus_fact (the acceptance criteria build "a cubit with focus fact
// id F"); until it exists this file does not compile.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/burst_coalescer_test_timing.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';

const _kFocusFactId = 'Fsource-focus-1';
const _kFocusFactText = 'Key is under the mat, red door';

class _FactsRepository extends FakeBeaconFactCardRepository {
  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async => [
    BeaconFactCard(
      id: 'other-fact',
      beaconId: beaconId,
      factText: 'Another fact',
      visibility: 0,
      pinnedBy: 'Uoscar',
      pinnedByTitle: 'Oscar',
      createdAt: DateTime.utc(2026),
      status: 0,
    ),
    BeaconFactCard(
      id: _kFocusFactId,
      beaconId: beaconId,
      factText: _kFocusFactText,
      visibility: 0,
      pinnedBy: 'Ufiona',
      pinnedByTitle: 'Fiona',
      createdAt: DateTime.utc(2026),
      status: 0,
    ),
  ];
}

RoomCubit _cubit(FakeBeaconThreadsRepository fakeRoom, {String? focusFactId}) =>
    RoomCubit(
      beaconId: kRoomCubitFakeBeaconId,
      beaconRoomCase: BeaconThreadsCase(
        fakeRoom,
        _FactsRepository(),
        FakePollingRepository(),
        FakeBeaconRoomHintsRepository(),
        RoomReadWatermarkStore.testing(),
        buildTestRealtimeSync().case_,
      ),
      coordinationItemRoomSync: CoordinationItemRoomSync(),
      presenceRepository: roomCubitFakePresenceRepository(),
      effects: FakeUiEffectPort(),
      focusFactId: focusFactId,
    );

void main() {
  late FakeBeaconThreadsRepository fakeRoom;

  setUp(() {
    registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
    fakeRoom = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId);
    addTearDown(fakeRoom.dispose);
  });

  group('RoomCubit opened with focus_fact', () {
    test(
      'sets pendingFactsFocusFactId only after the first fact load',
      () async {
        final cubit = _cubit(fakeRoom, focusFactId: _kFocusFactId);
        addTearDown(cubit.close);
        expect(cubit.state.pendingFactsFocusFactId, isNull);

        final states = <RoomState>[];
        final sub = cubit.stream.listen(states.add);
        addTearDown(sub.cancel);

        await awaitRoomCubitLoad(cubit);
        await pumpAfterHintBurst();

        final focused = states
            .where((s) => s.pendingFactsFocusFactId == _kFocusFactId)
            .toList();
        expect(
          focused,
          isNotEmpty,
          reason: 'focus_fact never reached the room',
        );
        for (final s in focused) {
          expect(s.factCards.map((f) => f.id), contains(_kFocusFactId));
        }
        for (final s in states.where((s) => s.factCards.isEmpty)) {
          expect(s.pendingFactsFocusFactId, isNull);
        }
      },
    );

    test(
      'without focus_fact the route never sets pendingFactsFocusFactId',
      () async {
        final cubit = _cubit(fakeRoom);
        addTearDown(cubit.close);
        final states = <RoomState>[];
        final sub = cubit.stream.listen(states.add);
        addTearDown(sub.cancel);

        await awaitRoomCubitLoad(cubit);
        await pumpAfterHintBurst();

        expect(cubit.state.factCards, hasLength(2));
        expect(
          states.map((s) => s.pendingFactsFocusFactId),
          everyElement(isNull),
        );
      },
    );
  });

  testWidgets("the room body opens the focused fact's actions sheet after the "
      'first fact load', (tester) async {
    final getIt = GetIt.I;
    if (!getIt.isRegistered<ImageRepository>()) {
      getIt.registerSingleton<ImageRepository>(ImageRepository());
      addTearDown(() => getIt.unregister<ImageRepository>());
    }
    if (!getIt.isRegistered<ClipboardImageRepository>()) {
      getIt.registerSingleton<ClipboardImageRepository>(
        ClipboardImageRepository(),
      );
      addTearDown(() => getIt.unregister<ClipboardImageRepository>());
    }
    late RoomCubit cubit;
    await tester.runAsync(() async {
      cubit = _cubit(fakeRoom, focusFactId: _kFocusFactId);
    });
    addTearDown(() => tester.runAsync(cubit.close));

    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<RoomCubit>.value(value: cubit),
          BlocProvider<ProfileCubit>.value(
            value: RoomBodyHarnessProfileCubit(
              const Profile(id: kRoomCubitFakeMyUserId, displayName: 'Me'),
            ),
          ),
          BlocProvider<PresenceCubit>.value(
            value: RoomBodyHarnessPresenceCubit(),
          ),
        ],
        child: MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: const TenturaResponsiveScope(
            child: Scaffold(body: BeaconRoomBody()),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    final l10n = await L10n.delegate.load(const Locale('en'));
    final title = find.text(l10n.beaconRoomFactManageSheetTitle);
    expect(title, findsOneWidget);
    // The sheet is the focused fact's: its provenance names Fiona, who
    // pinned it, not Oscar, who pinned the other fact.
    final sheet = find
        .ancestor(of: title, matching: find.byType(SingleChildScrollView))
        .first;
    expect(
      find.descendant(of: sheet, matching: find.textContaining('Fiona')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.textContaining('Oscar')),
      findsNothing,
    );
  });
}
