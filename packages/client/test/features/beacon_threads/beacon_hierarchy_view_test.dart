import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_request_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_requests_section.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_hierarchy_parent_link.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_surface.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';

class _NoopBeaconWritePort implements BeaconWritePort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopImageRepo implements ImageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BeaconHierarchyCase _hierarchyCase(FakeBeaconHierarchyRepositoryPort port) =>
    buildBeaconHierarchyCaseForTest(
      port,
      createCase: BeaconCreateCase(_NoopBeaconWritePort(), _NoopImageRepo()),
      beacons: _NoopBeaconWritePort(),
      commandStore: InMemoryBeaconChildCommandStore(),
    );

BeaconHierarchySummary _summary({
  String id = 'child-1',
  String title = 'Child title',
  bool tombstone = false,
}) =>
    BeaconHierarchySummary(
      beaconId: id,
      title: title,
      status: BeaconStatus.open,
      publishedAt: DateTime.utc(2026, 1, 1),
      isTombstone: tombstone,
      owner: const BeaconHierarchyOwnerSummary(
        id: 'owner-1',
        displayName: 'Owner',
      ),
    );

BeaconViewState _beaconState({bool terminal = false}) {
  final now = DateTime.utc(2026, 1, 1);
  return BeaconViewState(
    beacon: Beacon(
      id: 'parent-1',
      title: 'Parent request',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: now,
      updatedAt: now,
      status: terminal ? BeaconStatus.closed : BeaconStatus.open,
    ),
    myProfile: const Profile(id: 'auth', displayName: 'Author'),
    roomParticipantsLoaded: true,
  );
}

class _FakeBeaconViewCubit extends Cubit<BeaconViewState> implements BeaconViewCubit {
  _FakeBeaconViewCubit(BeaconViewState initial) : super(initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap({
  required Widget child,
  required BeaconHierarchyCubit hierarchyCubit,
  BeaconViewCubit? beaconViewCubit,
}) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: MultiBlocProvider(
        providers: [
          BlocProvider<BeaconHierarchyCubit>.value(value: hierarchyCubit),
          if (beaconViewCubit != null)
            BlocProvider<BeaconViewCubit>.value(value: beaconViewCubit),
        ],
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets('empty eligible parent shows empty copy and create action', (
    tester,
  ) async {
    final cubit = BeaconHierarchyCubit(
      beaconId: 'parent-1',
      hierarchyCase: _hierarchyCase(FakeBeaconHierarchyRepositoryPort()),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      _wrap(
        hierarchyCubit: cubit,
        child: BeaconChildRequestsSection(beaconState: _beaconState()),
      ),
    );
    await cubit.load();
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconChildRequestsEmpty), findsOneWidget);
    expect(find.text(l10n.beaconCreateChildRequest), findsOneWidget);
    expect(find.text(l10n.beaconChildRequestsDeletedTitle), findsNothing);
  });

  testWidgets('terminal parent hides create action but lists children', (
    tester,
  ) async {
    final cubit = BeaconHierarchyCubit(
      beaconId: 'parent-1',
      hierarchyCase: _hierarchyCase(
        FakeBeaconHierarchyRepositoryPort(
          capabilities: const BeaconHierarchyCapabilities(
            canListChildren: true,
            canCreateChild: false,
          ),
          childrenByGroup: {
            BeaconHierarchyChildGroup.active: BeaconHierarchyPage(
              summaries: [_summary(title: 'Still readable')],
            ),
          },
        ),
      ),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      _wrap(
        hierarchyCubit: cubit,
        child: BeaconChildRequestsSection(
          beaconState: _beaconState(terminal: true),
        ),
      ),
    );
    await cubit.load();
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconCreateChildRequest), findsNothing);
    expect(find.text('Still readable'), findsOneWidget);
    expect(find.text(l10n.beaconChildRequestsDeletedTitle), findsNothing);
  });

  testWidgets('deleted fold is shown only when tombstones exist', (
    tester,
  ) async {
    final cubit = BeaconHierarchyCubit(
      beaconId: 'parent-1',
      hierarchyCase: _hierarchyCase(
        FakeBeaconHierarchyRepositoryPort(
          childrenByGroup: {
            BeaconHierarchyChildGroup.deleted: BeaconHierarchyPage(
              summaries: [_summary(id: 'gone', tombstone: true)],
            ),
          },
        ),
      ),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      _wrap(
        hierarchyCubit: cubit,
        child: BeaconChildRequestsSection(beaconState: _beaconState()),
      ),
    );
    await cubit.load();
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconChildRequestsDeletedTitle), findsOneWidget);
    expect(find.text(l10n.beaconDeletedChild), findsNothing);
  });

  testWidgets('deleted tombstone card is not tappable', (tester) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: BeaconChildRequestCard(
            summary: _summary(id: 'gone', tombstone: true),
            currentUserId: 'viewer',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.beaconDeletedChild), findsOneWidget);
    expect(tester.widget<BeaconChildRequestCard>(
      find.byType(BeaconChildRequestCard),
    ).summary.isTombstone, isTrue);
  });

  testWidgets('parent link states render expected copy', (tester) async {
    final l10n = await L10n.delegate.load(const Locale('en'));

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(
          body: Column(
            children: [
              BeaconHierarchyParentLink(
                reference: BeaconParentReference.none,
              ),
              BeaconHierarchyParentLink(
                reference: BeaconParentReference.unavailable,
              ),
              BeaconHierarchyParentLink(
                reference: BeaconParentReference(
                  state: BeaconParentReferenceState.available,
                  beaconId: 'parent-1',
                  title: 'Parent title',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.beaconParentUnavailable), findsOneWidget);
    expect(find.text('Parent title'), findsOneWidget);
  });

  testWidgets('evicting hierarchy access hides child section mid-session', (
    tester,
  ) async {
    final cubit = BeaconHierarchyCubit(
      beaconId: 'parent-1',
      hierarchyCase: _hierarchyCase(
        FakeBeaconHierarchyRepositoryPort(
          childrenByGroup: {
            BeaconHierarchyChildGroup.active: BeaconHierarchyPage(
              summaries: [_summary(title: 'Visible child')],
            ),
          },
        ),
      ),
    );
    addTearDown(cubit.close);

    final beaconViewCubit = _FakeBeaconViewCubit(_beaconState());
    addTearDown(beaconViewCubit.close);
    final screenCubit = ScreenCubit.local();
    addTearDown(screenCubit.close);

    await tester.pumpWidget(
      _wrap(
        hierarchyCubit: cubit,
        beaconViewCubit: beaconViewCubit,
        child: BeaconNowSurface(
          beaconViewCubit: beaconViewCubit,
          screenCubit: screenCubit,
          beaconState: beaconViewCubit.state,
          onSurfaceSelected: (_) {},
          onActivatePeopleTabAttention: () {},
          onFocusCoordinationItem: (_) {},
          onOpenGeneralThread: () {},
        ),
      ),
    );
    await cubit.load();
    await tester.pumpAndSettle();

    expect(find.text('Visible child'), findsOneWidget);

    cubit.evictHierarchyAccess();
    await tester.pumpAndSettle();

    expect(find.text('Visible child'), findsNothing);
  });
}
