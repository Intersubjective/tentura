import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/data/service/user_presence_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_room_repository.dart';
import 'package:tentura/features/beacon_room/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_room/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_room/domain/use_case/beacon_room_case.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_room/fake_coordination_item_case.dart';
import 'beacon_view_case_test_support.dart';

class _TrackingStackRouter extends Mock implements StackRouter {
  _TrackingStackRouter() {
    pagelessRoutesObserver = PagelessRoutesObserver();
  }

  int backCount = 0;
  int replacePathCount = 0;
  int pushPathCount = 0;
  int maybePopTopCount = 0;

  String currentUrlValue = '';

  late final PagelessRoutesObserver pagelessRoutesObserver;

  @override
  void back() => backCount++;

  @override
  Future<bool> maybePopTop<T extends Object?>([T? result]) {
    backCount++;
    maybePopTopCount++;
    return Future<bool>.value(true);
  }

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;

  @override
  String get currentUrl => currentUrlValue;

  @override
  Future<T?> replacePath<T extends Object?>(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) {
    replacePathCount++;
    currentUrlValue = path;
    return Future<T?>.value(null);
  }

  @override
  Future<T?> pushPath<T extends Object?>(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) {
    pushPathCount++;
    return Future<T?>.value(null);
  }
}

class _TestBeaconViewCubit extends Mock implements BeaconViewCubit {
  _TestBeaconViewCubit.loading() : _state = _loadingBeaconState() {
    _controller = StreamController<BeaconViewState>.broadcast();
    _controller.add(_state);
  }

  late BeaconViewState _state;
  late final StreamController<BeaconViewState> _controller;

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => _controller.stream;

  @override
  DateTime? roomReadThrough(String beaconId) => null;

  void completeLoad() {
    _state = _authorBeaconState();
    _controller.add(_state);
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(String userId) : _userId = userId;

  final String _userId;

  @override
  ProfileState get state => ProfileState(
    profile: Profile(id: _userId, displayName: 'Author'),
  );

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

class _FakeBeaconRoomRepository extends Fake implements BeaconRoomRepository {
  _FakeBeaconRoomRepository({required this.userId});

  final String userId;

  @override
  Stream<String> get beaconRoomRefresh => const Stream.empty();

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) async => const [];

  @override
  Future<List<BeaconParticipant>> fetchParticipants(String beaconId) async {
    if (userId.isEmpty) return const [];
    return [
      BeaconParticipant(
        id: 'p1',
        beaconId: beaconId,
        userId: userId,
        role: 0,
        status: 0,
        roomAccess: 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    ];
  }

  @override
  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async =>
      BeaconRoomState(beaconId: beaconId, updatedAt: DateTime.utc(2026));

  @override
  Future<DateTime> markRoomSeen({
    required String beaconId,
    required DateTime readThroughAt,
    String? threadItemId,
  }) async => readThroughAt;
}

class _FakeBeaconFactCardRepository extends Fake
    implements BeaconFactCardRepository {
  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async => [];
}

class _FakeBeaconRoomHintsRepository extends Fake
    implements BeaconRoomHintsRepository {}

class _FakePollingRepository extends Fake implements PollingRepository {}

const _kBeaconId = 'B1';
const _kMyUserId = 'me';

final _t = DateTime.utc(2026, 1, 1);

BeaconViewState _loadingBeaconState() {
  const me = Profile(id: _kMyUserId, displayName: 'Author');
  return BeaconViewState(
    status: const StateIsLoading(),
    beacon: Beacon(
      id: _kBeaconId,
      title: 'Test beacon',
      author: me,
      createdAt: _t,
      updatedAt: _t,
    ),
    myProfile: me,
  );
}

BeaconViewState _authorBeaconState() {
  const me = Profile(id: _kMyUserId, displayName: 'Author');
  return BeaconViewState(
    status: const StateIsSuccess(),
    beaconContentLoaded: true,
    beacon: Beacon(
      id: _kBeaconId,
      title: 'Test beacon',
      author: me,
      createdAt: _t,
      updatedAt: _t,
    ),
    myProfile: me,
  );
}

void _stubRouter(_TrackingStackRouter router, {required String currentUrl}) {
  router
    ..backCount = 0
    ..replacePathCount = 0
    ..pushPathCount = 0
    ..currentUrlValue = currentUrl;
}

void _registerCommonGetIt() {
  final getIt = GetIt.instance;
  getIt.registerSingleton<CoordinationItemCase>(
    const FakeCoordinationItemCaseForRoom(),
  );
  getIt.registerSingleton<InvalidationService>(FakeInvalidationService());
}

void _registerRoomGetIt() {
  _registerCommonGetIt();
  final getIt = GetIt.instance;
  final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId);
  final itemSync = CoordinationItemRoomSync();
  final roomCase = BeaconRoomCase(
    fakeRoom,
    _FakeBeaconFactCardRepository(),
    _FakePollingRepository(),
    _FakeBeaconRoomHintsRepository(),
    RoomReadWatermarkStore.testing(),
    const FakeCoordinationItemCaseForRoom(),
    env: const Env(),
    logger: Logger('beacon_view_navigation_test'),
  );

  getIt.registerSingleton<ProfileCubit>(_MockProfileCubit(_kMyUserId));
  getIt.registerSingleton<BeaconRoomCase>(roomCase);
  getIt.registerSingleton<CoordinationItemRoomSync>(itemSync);
  getIt.registerSingleton<PresenceRepository>(
    PresenceRepository(
      UserPresenceService.forTesting(
        messages: const Stream.empty(),
        connectionState: const Stream.empty(),
        send: (_) {},
      ),
    ),
  );
  getIt.registerSingleton<UiEffectPort>(FakeUiEffectPort());
  getIt.registerSingleton<ImageRepository>(ImageRepositoryMock());
}

Future<void> _pumpBeaconView(
  WidgetTester tester, {
  required _TrackingStackRouter router,
  required BeaconViewCubit cubit,
  String? viewTab,
  String? entry,
}) async {
  await tester.pumpWidget(
    RouterScope(
      controller: router,
      stateHash: 0,
      inheritableObserversBuilder: () => [],
      child: StackRouterScope(
        controller: router,
        stateHash: 0,
        child: MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider(create: (_) => ScreenCubit.local()),
                BlocProvider<BeaconViewCubit>.value(value: cubit),
              ],
              child: BeaconViewScreen(
                id: _kBeaconId,
                viewTab: viewTab,
                entry: entry,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpLoadedBeaconView(
  WidgetTester tester, {
  required _TrackingStackRouter router,
  required _TestBeaconViewCubit cubit,
  String? viewTab,
  String? entry,
}) async {
  await _pumpBeaconView(
    tester,
    router: router,
    cubit: cubit,
    viewTab: viewTab,
    entry: entry,
  );
  cubit.completeLoad();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  tearDown(() async {
    await GetIt.I.reset();
  });

  group('BeaconViewScreen navigation', () {
    testWidgets('in-app room entry does not push a new route', (tester) async {
      _registerRoomGetIt();
      final router = _TrackingStackRouter();
      _stubRouter(
        router,
        currentUrl:
            '$kPathBeaconView/$_kBeaconId?$kQueryBeaconEntry=$kBeaconEntryMyWork',
      );
      final cubit = _TestBeaconViewCubit.loading();
      addTearDown(cubit.close);

      await _pumpLoadedBeaconView(
        tester,
        router: router,
        cubit: cubit,
        entry: kBeaconEntryMyWork,
      );

      await tester.tap(find.byIcon(Icons.forum_rounded));
      await tester.pump();

      expect(router.pushPathCount, 0);
      expect(router.replacePathCount, 1);
    });

    testWidgets('room back closes overlay and stays on beacon', (tester) async {
      _registerRoomGetIt();
      final router = _TrackingStackRouter();
      _stubRouter(
        router,
        currentUrl:
            '$kPathBeaconView/$_kBeaconId?$kQueryBeaconEntry=$kBeaconEntryMyWork',
      );
      final cubit = _TestBeaconViewCubit.loading();
      addTearDown(cubit.close);

      await _pumpLoadedBeaconView(
        tester,
        router: router,
        cubit: cubit,
        entry: kBeaconEntryMyWork,
      );

      await tester.tap(find.text('Log'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.forum_rounded));
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(router.backCount, 0);
      expect(find.text('Log'), findsOneWidget);
    });

    testWidgets('root modal back closes modal without exiting room', (
      tester,
    ) async {
      _registerRoomGetIt();
      final router = _TrackingStackRouter();
      _stubRouter(
        router,
        currentUrl:
            '$kPathBeaconView/$_kBeaconId?$kQueryBeaconEntry=$kBeaconEntryMyWork',
      );
      final cubit = _TestBeaconViewCubit.loading();
      addTearDown(cubit.close);

      await _pumpLoadedBeaconView(
        tester,
        router: router,
        cubit: cubit,
        entry: kBeaconEntryMyWork,
      );

      await tester.tap(find.text('Log'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.forum_rounded));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);

      final context = tester.element(find.byType(BeaconViewScreen));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(
            content: Text('root modal'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('root modal'), findsOneWidget);

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(find.text('root modal'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(router.backCount, 0);
    });

    testWidgets('operational back pops beacon route once', (tester) async {
      _registerCommonGetIt();
      final router = _TrackingStackRouter();
      _stubRouter(
        router,
        currentUrl:
            '$kPathBeaconView/$_kBeaconId?$kQueryBeaconEntry=$kBeaconEntryMyWork',
      );
      final cubit = _TestBeaconViewCubit.loading();
      addTearDown(cubit.close);

      await _pumpLoadedBeaconView(
        tester,
        router: router,
        cubit: cubit,
        entry: kBeaconEntryMyWork,
      );

      await tester.tap(find.text('Log'));
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      await tester.pump();

      expect(router.backCount, 1);
      expect(router.maybePopTopCount, 1);
    });

    testWidgets(
      'deep-link room exit strips room from URL without popping route',
      (
        tester,
      ) async {
        _registerRoomGetIt();
        final router = _TrackingStackRouter();
        final roomUrl =
            '$kPathBeaconView/$_kBeaconId?$kQueryBeaconViewTab=room&$kQueryBeaconEntry=$kBeaconEntryDeepLink';
        _stubRouter(router, currentUrl: roomUrl);
        final cubit = _TestBeaconViewCubit.loading();
        addTearDown(cubit.close);

        await _pumpLoadedBeaconView(
          tester,
          router: router,
          cubit: cubit,
          viewTab: 'room',
          entry: kBeaconEntryDeepLink,
        );

        await tester.tap(find.byType(BackButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(router.backCount, 0);
        expect(router.replacePathCount, 1);
        expect(find.text('Items'), findsOneWidget);
      },
    );
  });
}
