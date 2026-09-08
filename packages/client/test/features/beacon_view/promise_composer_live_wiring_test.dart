// Closes a coverage gap: proves production wiring from BeaconViewCubit
// participant stream into the coordination composer opened via NOW surface CTA.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_surface.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

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

class _MockThreadsCubit extends Mock implements ThreadsCubit {
  _MockThreadsCubit(this._state);

  final ThreadsState _state;

  @override
  ThreadsState get state => _state;

  @override
  Stream<ThreadsState> get stream => Stream<ThreadsState>.value(_state);

  @override
  Future<void> fetch({bool silent = false}) async {}
}

class _DelayedRoomRepository extends FakeBeaconViewRoomRepository {
  _DelayedRoomRepository({required this.release, required super.participants});

  final Completer<void> release;

  @override
  Future<List<BeaconParticipant>> fetchParticipants(String beaconId) async {
    await release.future;
    return participants;
  }
}

class _TrackingPromiseCase extends FakeCoordinationItemCaseForRoom {
  String? createdBeaconId;
  String? createdTargetId;

  @override
  Future<CoordinationItem> createPromise({
    required String beaconId,
    required String title,
    required String targetPersonId,
    String? body,
    String? linkedMessageId,
    int? staleAfterDays,
  }) async {
    createdBeaconId = beaconId;
    createdTargetId = targetPersonId;
    return CoordinationItem(
      id: 'promise-1',
      beaconId: beaconId,
      kind: CoordinationItemKind.promise,
      status: CoordinationItemStatus.open,
      creatorId: targetPersonId,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 50,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  if (!condition()) {
    throw StateError('Condition not met after $maxPumps pumps');
  }
}

void main() {
  const authorId = 'Uauthor01';
  const beaconId = 'Bpromise01';
  const authorProfile = Profile(id: authorId, displayName: 'Author');

  Beacon myOpenBeacon() => Beacon(
    id: beaconId,
    title: 'My open request',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: BeaconStatus.open,
    canReadContent: true,
    author: authorProfile,
  );

  BeaconParticipant helper() => BeaconParticipant(
    id: 'P-helper',
    beaconId: beaconId,
    userId: 'Uhelper01',
    role: BeaconParticipantRoleBits.helper,
    status: BeaconParticipantStatusBits.committed,
    roomAccess: RoomAccessBits.admitted,
    userTitle: 'Helper Name',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  setUp(() {
    if (GetIt.I.isRegistered<CoordinationItemCase>()) {
      GetIt.I.unregister<CoordinationItemCase>();
    }
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<CoordinationItemCase>()) {
      await GetIt.I.unregister<CoordinationItemCase>();
    }
  });

  testWidgets(
    'real BeaconViewCubit feeds live participants into composer from NOW surface CTA',
    (tester) async {
      final trackingCase = _TrackingPromiseCase();
      GetIt.I.registerSingleton<CoordinationItemCase>(trackingCase);

      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => myOpenBeacon();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final roomRepo = _DelayedRoomRepository(
        release: release,
        participants: [helper()],
      );
      final case_ = buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        roomRepo: roomRepo,
      );
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: authorProfile,
        beaconViewCase: case_,
        coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      final threadsCubit = _MockThreadsCubit(
        const ThreadsState(status: StateIsSuccess()),
      );

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

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: MultiBlocProvider(
            providers: [
              BlocProvider<BeaconViewCubit>.value(value: cubit),
              BlocProvider<ThreadsCubit>.value(value: threadsCubit),
              BlocProvider<BeaconHierarchyCubit>.value(value: hierarchyCubit),
            ],
            child: Scaffold(
              body: BlocBuilder<BeaconViewCubit, BeaconViewState>(
                bloc: cubit,
                builder: (context, state) => BeaconNowSurface(
                  beaconViewCubit: cubit,
                  screenCubit: screenCubit,
                  beaconState: state,
                  onSurfaceSelected: (_) {},
                  onActivatePeopleTabAttention: () {},
                  onFocusCoordinationItem: (_) {},
                  onOpenGeneralThread: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await _pumpUntil(tester, () => cubit.state.beaconContentLoaded);
      await tester.pump();

      expect(cubit.state.canCoordinateInBeaconRoom, isTrue);
      expect(cubit.state.roomParticipantsLoaded, isFalse);
      expect(
        find.byKey(TestIds.key(TestIds.coordinationPromiseCreate)),
        findsOneWidget,
      );

      await tester.tap(find.byKey(TestIds.key(TestIds.coordinationPromiseCreate)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(TestIds.key(TestIds.coordinationComposerTitle)),
        findsOneWidget,
      );
      expect(find.byType(DropdownButtonFormField<String?>), findsNothing);
      expect(find.text('Helper Name'), findsNothing);

      release.complete();
      await _pumpUntil(tester, () => cubit.state.roomParticipantsLoaded);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(DropdownButtonFormField<String?>), findsOneWidget);
      expect(find.text('Helper Name'), findsWidgets);

      await tester.enterText(
        find.byKey(TestIds.key(TestIds.coordinationComposerTitle)),
        'I will ship it',
      );
      await tester.pump();

      final submit = find.byKey(TestIds.key(TestIds.coordinationComposerSubmit));
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await tester.tap(submit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(trackingCase.createdBeaconId, beaconId);
      expect(trackingCase.createdTargetId, 'Uhelper01');
    },
    skip: true, // Promise creation CTA retired from Discussion overview (Task 12).
  );
}
