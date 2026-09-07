import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_surface.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/fake_coordination_item_case.dart';
import 'beacon_view_case_test_support.dart';

class _NoopBeaconWritePort implements BeaconWritePort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopImageRepo implements ImageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _HarnessRouter extends Mock implements StackRouter {
  int pushCount = 0;
  PageRouteInfo? lastPush;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushCount++;
    lastPush = route;
    return null;
  }
}

BeaconHierarchySummary _childSummary({
  String id = 'child-1',
  String title = 'Child request',
}) =>
    BeaconHierarchySummary(
      beaconId: id,
      title: title,
      status: BeaconStatus.open,
      publishedAt: DateTime.utc(2026, 1, 1),
      isTombstone: false,
      owner: const BeaconHierarchyOwnerSummary(
        id: 'owner-1',
        displayName: 'Owner',
      ),
    );

Widget _wrap({
  required Widget child,
  required BeaconViewCubit beaconViewCubit,
  required BeaconHierarchyCubit hierarchyCubit,
  required StackRouter router,
}) {
  return StackRouterScope(
    controller: router,
    stateHash: 0,
    child: MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(
            value: _MockProfileCubit(beaconViewCubit.state.myProfile),
          ),
          BlocProvider<BeaconHierarchyCubit>.value(value: hierarchyCubit),
        ],
        child: TenturaResponsiveScope(
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
}

void main() {
  const myProfile = Profile(id: 'Uauthor', displayName: 'Author');
  const beaconId = 'parent-1';

  Beacon readableBeacon() => Beacon(
    id: beaconId,
    title: 'Facts beacon',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    startAt: DateTime.utc(2099, 6, 20, 12),
    status: BeaconStatus.open,
    canReadContent: true,
    author: myProfile,
  );

  testWidgets('header card renders in BeaconNowSurface', (tester) async {
    final case_ = buildTestBeaconViewCase(
      beaconRepo: TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon(),
    );
    final cubit = BeaconViewCubit(
      id: beaconId,
      myProfile: myProfile,
      beaconViewCase: case_,
      coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);

    final hierarchyCubit = BeaconHierarchyCubit(
      beaconId: beaconId,
      hierarchyCase: buildBeaconHierarchyCaseForTest(
        FakeBeaconHierarchyRepositoryPort(
          capabilities: const BeaconHierarchyCapabilities(
            canListChildren: false,
            canCreateChild: false,
          ),
        ),
        createCase: BeaconCreateCase(_NoopBeaconWritePort(), _NoopImageRepo()),
        beacons: _NoopBeaconWritePort(),
        commandStore: InMemoryBeaconChildCommandStore(),
      ),
    );
    addTearDown(hierarchyCubit.close);

    final screenCubit = ScreenCubit.local();
    addTearDown(screenCubit.close);
    final router = _HarnessRouter();

    await tester.pumpWidget(
      _wrap(
        router: router,
        beaconViewCubit: cubit,
        hierarchyCubit: hierarchyCubit,
        child: BeaconNowSurface(
          beaconViewCubit: cubit,
          screenCubit: screenCubit,
          beaconState: cubit.state,
          onSurfaceSelected: (_) {},
          onActivatePeopleTabAttention: () {},
          onFocusCoordinationItem: (_) {},
          onOpenGeneralThread: () {},
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 30 && !cubit.state.beaconContextLoaded; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.byType(BeaconOperationalHeaderCard), findsOneWidget);
  });

  testWidgets('child request cards render below header and navigate on tap', (
    tester,
  ) async {
    final case_ = buildTestBeaconViewCase(
      beaconRepo: TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon(),
    );
    final cubit = BeaconViewCubit(
      id: beaconId,
      myProfile: myProfile,
      beaconViewCase: case_,
      coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);

    final hierarchyCubit = BeaconHierarchyCubit(
      beaconId: beaconId,
      hierarchyCase: buildBeaconHierarchyCaseForTest(
        FakeBeaconHierarchyRepositoryPort(
          capabilities: const BeaconHierarchyCapabilities(
            canListChildren: true,
            canCreateChild: false,
          ),
          childrenByGroup: {
            BeaconHierarchyChildGroup.active: BeaconHierarchyPage(
              summaries: [_childSummary(title: 'Fix the fence')],
            ),
          },
        ),
        createCase: BeaconCreateCase(_NoopBeaconWritePort(), _NoopImageRepo()),
        beacons: _NoopBeaconWritePort(),
        commandStore: InMemoryBeaconChildCommandStore(),
      ),
    );
    addTearDown(hierarchyCubit.close);

    final screenCubit = ScreenCubit.local();
    addTearDown(screenCubit.close);
    final router = _HarnessRouter();

    await tester.pumpWidget(
      _wrap(
        router: router,
        beaconViewCubit: cubit,
        hierarchyCubit: hierarchyCubit,
        child: BeaconNowSurface(
          beaconViewCubit: cubit,
          screenCubit: screenCubit,
          beaconState: cubit.state,
          onSurfaceSelected: (_) {},
          onActivatePeopleTabAttention: () {},
          onFocusCoordinationItem: (_) {},
          onOpenGeneralThread: () {},
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 30 && !cubit.state.beaconContextLoaded; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await hierarchyCubit.load();
    await tester.pumpAndSettle();

    final headerFinder = find.byType(BeaconOperationalHeaderCard);
    final childFinder = find.text('Fix the fence');
    expect(headerFinder, findsOneWidget);
    expect(childFinder, findsOneWidget);

    final headerY = tester.getTopLeft(headerFinder).dy;
    final childY = tester.getTopLeft(childFinder).dy;
    expect(childY, greaterThan(headerY));

    await tester.tap(childFinder);
    await tester.pump();
    expect(router.pushCount, 1);
    expect(router.lastPush, isA<BeaconViewRoute>());
    expect((router.lastPush! as BeaconViewRoute).args!.id, 'child-1');
  });
}
