import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_state.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_request_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_requests_section.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_hierarchy_parent_link.dart';
import 'package:tentura/features/beacon_threads/ui/widget/threads_list.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/ui/bloc/state_base.dart';
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
    BeaconHierarchyCase(
      port,
      BeaconCreateCase(_NoopBeaconWritePort(), _NoopImageRepo()),
      _NoopBeaconWritePort(),
      InMemoryBeaconChildCommandStore(),
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

class _StaticThreadsCubit extends Cubit<ThreadsState> implements ThreadsCubit {
  _StaticThreadsCubit()
      : super(
          ThreadsState(
            threads: [
              RequestThread(
                threadId: RequestThread.generalId,
                kind: RequestThreadKind.general,
                unreadCount: 2,
                messageCount: 1,
                lastMessageAt: DateTime.utc(2026),
                lastMessageAuthorId: 'auth',
              ),
            ],
            resolvedUnreadByThreadId: {RequestThread.generalId: 2},
            status: const StateIsSuccess(),
          ),
        );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap({
  required Widget child,
  required BeaconHierarchyCubit hierarchyCubit,
  ThreadsCubit? threadsCubit,
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
          if (threadsCubit != null)
            BlocProvider<ThreadsCubit>.value(value: threadsCubit),
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

    final threadsCubit = _StaticThreadsCubit();
    addTearDown(threadsCubit.close);

    await tester.pumpWidget(
      _wrap(
        hierarchyCubit: cubit,
        threadsCubit: threadsCubit,
        child: ThreadsList(
          beaconState: _beaconState(),
          onOpenGeneral: () {},
        ),
      ),
    );
    await cubit.load();
    await tester.pumpAndSettle();

    expect(find.text('Visible child'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    cubit.evictHierarchyAccess();
    await tester.pumpAndSettle();

    expect(find.text('Visible child'), findsNothing);
    expect(find.text('2'), findsOneWidget);
  });
}
