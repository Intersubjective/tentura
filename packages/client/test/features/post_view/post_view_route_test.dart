import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_room_surface.dart';
import 'package:tentura/features/post_view/data/repository/beacon_kind_repository.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_view/beacon_view_case_test_support.dart';
import '../beacon_view/beacon_view_screen_harness.dart';

const _postId = 'Bpostroute001';
const _requestId = 'Brequestroute01';
const _viewer = Profile(id: 'Uviewer', displayName: 'Viewer');
const _author = Profile(id: 'Uauthor', displayName: 'Author');

Beacon _beacon(String id, BeaconKind kind) => Beacon(
  id: id,
  title: 'Route beacon',
  kind: kind,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  status: BeaconStatus.open,
  canReadContent: true,
  author: _author,
);

/// Serves only the beacon itself; every other repository call throws, which
/// proves the Post path never reaches Request-only data.
class _BeaconOnlyRepository implements BeaconRepository {
  _BeaconOnlyRepository(this.beacons);

  final Map<String, Beacon> beacons;
  final List<String> fetched = [];

  @override
  Stream<RepositoryEvent<Beacon>> get changes => const Stream.empty();

  @override
  Future<Beacon> fetchBeaconById(String id) async {
    fetched.add(id);
    return beacons[id]!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Request-only call: ${invocation.memberName}');
}

class _FakeBeaconKindRepository implements BeaconKindRepository {
  _FakeBeaconKindRepository(this.kinds);

  final Map<String, BeaconKind> kinds;
  final List<String> requested = [];
  final Completer<void> gate = Completer<void>();
  bool gated = false;

  @override
  Future<BeaconKind> fetchKind(String beaconId) async {
    requested.add(beaconId);
    if (gated) await gate.future;
    return kinds[beaconId]!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

/// Minimal router mounting the production host page and its operational child.
class _TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: BeaconViewRoute.page,
      path: '/beacon/view/:id',
      children: [
        AutoRoute(
          page: BeaconViewOperationalRoute.page,
          path: '',
          initial: true,
        ),
      ],
    ),
  ];
}

Future<void> _register<T extends Object>(T instance) async {
  if (GetIt.I.isRegistered<T>()) await GetIt.I.unregister<T>();
  GetIt.I.registerSingleton<T>(instance);
}

/// Pumps the real route for [id]. Request-only collaborators are registered
/// only when [withRequestCollaborators] is set, so a Post that touches them
/// fails with a GetIt error.
Future<void> _pumpRoute(
  WidgetTester tester, {
  required String id,
  required _FakeBeaconKindRepository kinds,
  required BeaconRepository beacons,
  bool withRequestCollaborators = false,
  bool withThrowingRequestCollaborators = false,
}) async {
  _requestOnlyTouches.clear();
  await registerBeaconViewHarnessGetIt(profile: _viewer);
  await _register<BeaconKindRepository>(kinds);
  await _register<BeaconRepository>(beacons);
  if (withThrowingRequestCollaborators) {
    await _register<BeaconHierarchyCase>(_ThrowingBeaconHierarchyCase());
  }
  if (withRequestCollaborators) {
    await _register<BeaconViewCase>(
      buildTestBeaconViewCase(beaconRepo: beacons as TrackingBeaconRepository),
    );
    await _register<BeaconHierarchyCase>(
      buildBeaconHierarchyCaseForTest(
        FakeBeaconHierarchyRepositoryPort(
          capabilities: const BeaconHierarchyCapabilities(
            canListChildren: false,
            canCreateChild: false,
          ),
        ),
        createCase: BeaconCreateCase(_NoopWritePort(), ImageRepository()),
        beacons: _NoopWritePort(),
        commandStore: InMemoryBeaconChildCommandStore(),
      ),
    );
  }
  addTearDown(() async {
    for (final unregister in [
      () => GetIt.I.unregister<BeaconKindRepository>(),
      () => GetIt.I.unregister<BeaconRepository>(),
      if (withRequestCollaborators) () => GetIt.I.unregister<BeaconViewCase>(),
      if (withRequestCollaborators || withThrowingRequestCollaborators)
        () => GetIt.I.unregister<BeaconHierarchyCase>(),
    ]) {
      await unregister();
    }
    await unregisterBeaconViewHarnessGetIt();
  });
  final router = _TestRouter();
  // A compact window throughout: surface and MediaQuery agree, so the route
  // does not render regular-window chrome (the rail) into a phone-wide box.
  tester.view
    ..physicalSize = kBeaconViewHarnessCompact
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    BlocProvider<ProfileCubit>.value(
      value: _ProfileCubit(),
      child: MaterialApp.router(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        builder: (_, child) => TenturaResponsiveScope(child: child!),
        routerConfig: router.config(
          deepLinkBuilder: (_) => DeepLink([BeaconViewRoute(id: id)]),
        ),
      ),
    ),
  );
}

/// Request-only collaborators: any touch is recorded and throws.
final List<String> _requestOnlyTouches = [];

class _ThrowingBeaconHierarchyCase implements BeaconHierarchyCase {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    _requestOnlyTouches.add('BeaconHierarchyCase.${invocation.memberName}');
    throw StateError('Request-only BeaconHierarchyCase touched');
  }
}

class _NoopWritePort implements BeaconWritePort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('kind-aware beacon route', () {
    testWidgets('shows the loading view until the beacon kind resolves', (
      tester,
    ) async {
      final kinds = _FakeBeaconKindRepository({_postId: BeaconKind.post})
        ..gated = true;
      final beacons = _BeaconOnlyRepository({
        _postId: _beacon(_postId, BeaconKind.post),
      });
      await _pumpRoute(tester, id: _postId, kinds: kinds, beacons: beacons);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.byType(PostViewScreen), findsNothing);
      expect(find.byType(BeaconViewScreen), findsNothing);

      kinds.gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(PostViewScreen), findsOneWidget);
    });

    testWidgets(
      'a Post id renders the Post screen with its room and never touches '
      'Request-only data',
      (tester) async {
        final kinds = _FakeBeaconKindRepository({_postId: BeaconKind.post});
        final beacons = _BeaconOnlyRepository({
          _postId: _beacon(_postId, BeaconKind.post),
        });
        await _pumpRoute(
          tester,
          id: _postId,
          kinds: kinds,
          beacons: beacons,
          withThrowingRequestCollaborators: true,
        );
        await tester.pumpAndSettle();

        expect(kinds.requested, contains(_postId));
        expect(_requestOnlyTouches, isEmpty);
        expect(find.byType(PostViewScreen), findsOneWidget);
        expect(find.byType(BeaconViewScreen), findsNothing);
        expect(find.byType(BeaconRoomSurface), findsOneWidget);
        expect(beacons.fetched, [_postId]);
        expect(tester.takeException(), isNull);

        final context = tester.element(find.byType(PostViewScreen));
        final surface = tester.widget<BeaconRoomSurface>(
          find.byType(BeaconRoomSurface),
        );
        expect(surface.host, same(context.read<PostViewCubit>()));
        expect(context.read<ThreadsCubit>(), isA<ThreadsCubit>());
        expect(
          context.read<ThreadHostCubit>().capabilities,
          const RoomCapabilities.post(),
        );
        expect(
          context.read<PostViewCubit>().capabilities,
          const RoomCapabilities.post(),
        );
      },
    );

    testWidgets('a Request id renders the Request screen', (tester) async {
      final kinds = _FakeBeaconKindRepository({
        _requestId: BeaconKind.request,
      });
      final beacons = TrackingBeaconRepository()
        ..fetchByIdHandler = (id) async => _beacon(id, BeaconKind.request);
      addTearDown(beacons.dispose);
      await _pumpRoute(
        tester,
        id: _requestId,
        kinds: kinds,
        beacons: beacons,
        withRequestCollaborators: true,
      );
      await tester.pumpAndSettle();

      expect(kinds.requested, contains(_requestId));
      expect(find.byType(BeaconViewScreen), findsOneWidget);
      expect(find.byType(PostViewScreen), findsNothing);
    });
  });

  group('PostViewCubit', () {
    late _BeaconOnlyRepository beacons;
    late PostViewCubit cubit;

    setUp(() {
      beacons = _BeaconOnlyRepository({
        _postId: _beacon(_postId, BeaconKind.post),
      });
      cubit = PostViewCubit(
        id: _postId,
        myProfile: _viewer,
        beaconRepository: beacons,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
    });

    test('is a RoomHost with Post capabilities', () {
      expect(cubit, isA<RoomHost>());
      expect(cubit.beaconId, _postId);
      expect(cubit.capabilities, const RoomCapabilities.post());
    });

    test('loads only the beacon itself and exposes author and status', () async {
      await cubit.fetch();
      await Future<void>.delayed(Duration.zero);

      expect(beacons.fetched, [_postId]);
      expect(cubit.author.id, _author.id);
      expect(cubit.status, BeaconStatus.open);
    });
  });

  group('PostViewScreen', () {
    testWidgets('renders the room surface under a plain app bar with back', (
      tester,
    ) async {
      final beacons = _BeaconOnlyRepository({
        _postId: _beacon(_postId, BeaconKind.post),
      });
      await registerBeaconViewHarnessGetIt(profile: _viewer);
      addTearDown(unregisterBeaconViewHarnessGetIt);
      final cubit = PostViewCubit(
        id: _postId,
        myProfile: _viewer,
        beaconRepository: beacons,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      await cubit.fetch();

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: BeaconViewResizableMediaQuery(
            size: kBeaconViewHarnessCompact,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<PostViewCubit>.value(value: cubit),
                BlocProvider<ThreadsCubit>(
                  create: (_) => ThreadsCubit(beaconId: _postId),
                ),
                BlocProvider<ThreadHostCubit>(
                  create: (_) => ThreadHostCubit(
                    beaconId: _postId,
                    capabilities: const RoomCapabilities.post(),
                  ),
                ),
              ],
              child: const PostViewScreen(id: _postId),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      final surface = tester.widget<BeaconRoomSurface>(
        find.byType(BeaconRoomSurface),
      );
      expect(surface.host, same(cubit));
    });
  });
}
