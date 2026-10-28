// The Questions screen keeps the app navigation rail (#726), as the Request
// page does; compact windows get no rail and back still leaves Questions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/home/ui/widget/home_rail_account_footer.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_threads/support/room_body_harness.dart'
    show RoomBodyHarnessPresenceCubit;
import 'fake_lobby_port.dart';

final class _FakeProfileCubit extends Fake implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'Unina', displayName: 'Nina'),
  );

  @override
  Stream<ProfileState> get stream => const Stream.empty();

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

class _TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: BeaconLobbyRoute.page, initial: true),
  ];
}

Future<void> _pumpFrames(WidgetTester tester) async {
  // Bounded: the Questions chat hosts animations that never settle.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<_TestRouter> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await GetIt.I.reset();
  addTearDown(GetIt.I.reset);
  final profileCubit = _FakeProfileCubit();
  final presenceCubit = RoomBodyHarnessPresenceCubit();
  // The Questions chat is the room chat on the Questions thread.
  GetIt.I
    ..registerSingleton<BeaconLobbyCase>(
      lobbyCaseFor(FakeLobbyPort(viewerId: 'Unina'), FakeRealtimeSyncPort()),
    )
    ..registerSingleton<UiEffectPort>(RecordingEffects())
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<PresenceCubit>(presenceCubit)
    ..registerSingleton<BeaconThreadsCase>(
      roomCubitMakeCase(FakeBeaconThreadsRepository(userId: 'Unina')),
    )
    ..registerSingleton<BeaconFactCardRepository>(
      FakeBeaconFactCardRepository(),
    )
    ..registerSingleton<CoordinationItemRoomSync>(CoordinationItemRoomSync())
    ..registerSingleton<PresenceRepository>(roomCubitFakePresenceRepository())
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());
  final router = _TestRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: profileCubit),
        BlocProvider<PresenceCubit>.value(value: presenceCubit),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) =>
            TenturaResponsiveScope(child: child ?? const SizedBox.shrink()),
        routerConfig: router.config(
          deepLinkBuilder: (_) => DeepLink([
            BeaconLobbyRoute(beaconId: 'B0'),
            BeaconLobbyRoute(beaconId: 'B1'),
          ]),
        ),
      ),
    ),
  );
  await _pumpFrames(tester);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  return router;
}

void main() {
  testWidgets('wide window: the rail with the account footer', (tester) async {
    await _pump(tester, const Size(1280, 800));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(HomeRailAccountFooter), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('compact window: no rail, back leaves Questions', (
    tester,
  ) async {
    final router = await _pump(tester, const Size(390, 800));

    expect(find.byType(NavigationRail), findsNothing);
    expect(router.stack, hasLength(2));
    await tester.tap(find.byTooltip('Back'));
    await _pumpFrames(tester);
    expect(router.stack, hasLength(1));
  });
}
