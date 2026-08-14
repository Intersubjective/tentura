// Closes a coverage gap left after issue #103 Unit 4/5: the composer
// sheet's live-participant-stream reaction was proven in isolation
// (coordination_item_composer_sheet_test.dart, hand-built StreamController),
// and the cubit's roomParticipantsLoaded timing was proven in isolation
// (beacon_view_initial_load_test.dart) — but nothing exercised the actual
// production wiring in items_tab.dart that connects a real BeaconViewCubit's
// stream to a sheet opened via a real Promise CTA tap. This test drives
// that end to end: real BeaconViewCubit, real ItemsTab, real CTA tap.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/items_tab_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/items_tab_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/items_tab.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/fake_coordination_item_case.dart';
import 'beacon_view_case_test_support.dart';

class _MockItemsTabCubit extends Mock implements ItemsTabCubit {
  _MockItemsTabCubit(this._state);

  final ItemsTabState _state;

  @override
  ItemsTabState get state => _state;

  @override
  Stream<ItemsTabState> get stream => Stream<ItemsTabState>.value(_state);

  @override
  Future<void> fetch({bool silent = false}) async {}
}

/// Gates [fetchParticipants] on [release] instead of a real-time delay.
///
/// `testWidgets` runs on a controlled clock: a real `Future.delayed` timer
/// (as used by the plain `enrichmentDelay` constructor param on
/// [FakeBeaconViewRoomRepository]) never fires unless `tester.pump(duration)`
/// explicitly advances it, and even `Stream.timeout`'s own bail-out Timer is
/// subject to the same freeze — so awaiting it directly hangs the test
/// indefinitely rather than timing out. A [Completer], resolved via the
/// microtask queue, has no such dependency on wall-clock time.
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

/// Polls [condition] across bounded widget-test pumps instead of awaiting a
/// real `Stream`/`Timer`-based wait — see [_DelayedRoomRepository]'s doc
/// comment for why real timers are unsafe to await directly inside
/// `testWidgets`. Throws if [condition] never becomes true within
/// [maxPumps] iterations, so a genuine wiring break fails fast instead of
/// hanging.
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
    'real BeaconViewCubit feeds live participants into the sheet opened by '
    'tapping the actual Promise CTA (production wiring, not a hand-built '
    'stream)',
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

      final itemsTabCubit = _MockItemsTabCubit(const ItemsTabState());

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: MultiBlocProvider(
            providers: [
              BlocProvider<BeaconViewCubit>.value(value: cubit),
              BlocProvider<ItemsTabCubit>.value(value: itemsTabCubit),
            ],
            child: Scaffold(
              body: BlocBuilder<BeaconViewCubit, BeaconViewState>(
                bloc: cubit,
                builder: (context, state) => ItemsTab(
                  state: state,
                  onOpenItemThread: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      // Phase 1 only: content loaded, author CTA already visible, but the
      // real cubit's participants fetch is still gated on `release`.
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

      // Sheet is open, but the real cubit hasn't delivered participants yet:
      // the picker area must show its loading state, not a dropdown.
      expect(
        find.byKey(TestIds.key(TestIds.coordinationComposerBody)),
        findsOneWidget,
      );
      expect(find.byType(DropdownButtonFormField<String?>), findsNothing);
      expect(find.text('Helper Name'), findsNothing);

      // Let the real cubit's phase-2 fetch resolve. If items_tab.dart's
      // `beaconViewCubit.stream.map(...)` wiring into the already-open sheet
      // is correct, the picker updates in place with no reopen.
      release.complete();
      await _pumpUntil(tester, () => cubit.state.roomParticipantsLoaded);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(DropdownButtonFormField<String?>), findsOneWidget);
      expect(find.text('Helper Name'), findsWidgets);

      await tester.enterText(
        find.byKey(TestIds.key(TestIds.coordinationComposerBody)),
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
  );
}
