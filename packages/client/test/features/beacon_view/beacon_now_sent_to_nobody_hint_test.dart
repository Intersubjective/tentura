// #484: a Request made live without sending is discoverable in the Field but
// was sent to nobody. Its author's Now panel says so in one line, and the line
// goes away once the author has forwarded it to someone (or when the Request
// is hidden from the Field, or the viewer is not the author).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_surface.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

const _author = Profile(id: 'Uauthor', displayName: 'Author');
const _bob = Profile(id: 'Ubob', displayName: 'Bob');
const _stranger = Profile(id: 'Ustranger', displayName: 'Stranger');
const _beaconId = 'Blive484';

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

class _MockThreadsCubit extends Mock implements ThreadsCubit {
  @override
  ThreadsState get state => const ThreadsState();

  @override
  Stream<ThreadsState> get stream => Stream<ThreadsState>.value(state);
}

/// Records pushes, like `_HarnessRouter` in beacon_now_surface_test.
class _RecordingRouter extends Mock implements StackRouter {
  final pushes = <PageRouteInfo>[];

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushes.add(route);
    return null;
  }
}

/// Forward reads that agree with each other: [sentTo] are the people the
/// author forwarded the Request to (empty = sent to nobody). Answers every
/// read a "has the author sent it to anyone" check could use. [reads] counts
/// them; with [failReads] every read throws.
class _ForwardsFake extends FakeBeaconViewForwardRepository {
  _ForwardsFake({
    required this.request,
    this.sentTo = const [],
    this.failReads = false,
  });

  final Beacon request;
  final List<Profile> sentTo;
  final bool failReads;
  int reads = 0;

  void _read() {
    reads++;
    if (failReads) throw Exception('forwards read failed');
  }

  List<ForwardEdge> get _edges => [
    for (final p in sentTo)
      ForwardEdge(
        id: 'edge-${p.id}',
        beaconId: request.id,
        createdAt: DateTime.utc(2026, 10, 19, 12),
        sender: request.author,
        recipient: p,
      ),
  ];

  @override
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) async {
    _read();
    return _edges;
  }

  @override
  Future<List<ForwardEdge>> fetchMyForwardEdges({
    required String beaconId,
    required String myUserId,
  }) async {
    _read();
    return [
      for (final e in _edges)
        if (e.sender.id == myUserId) e,
    ];
  }

  @override
  Future<bool> currentUserHasForwardedBeacon(String beaconId) async {
    _read();
    return sentTo.isNotEmpty;
  }

  @override
  Future<Map<String, List<String>>> fetchReasonsByBeacon({
    required String beaconId,
  }) async {
    _read();
    return const {};
  }

  BeaconInvolvementData _involvement() => (
    beacon: request,
    forwardedToIds: {for (final p in sentTo) p.id},
    helpOfferedIds: const <String>{},
    withdrawnIds: const <String>{},
    rejectedIds: const <String>{},
    watchingIds: const <String>{},
    onwardForwarderIds: const <String>{},
    myForwardedRecipientNotes: {for (final p in sentTo) p.id: ''},
    myForwardedRecipientEdgeIds: {for (final p in sentTo) p.id: 'edge-${p.id}'},
    myForwardedRecipientReadAts: {for (final p in sentTo) p.id: null},
    myForwardedRecipientHasOnwardChild: {for (final p in sentTo) p.id: false},
    myForwardedRecipientRejected: {for (final p in sentTo) p.id: false},
  );

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async {
    _read();
    return _involvement();
  }

  @override
  Future<BeaconInvolvementData> fetchInvolvementForBeacon(
    Beacon beacon,
  ) async {
    _read();
    return _involvement();
  }
}

Beacon _liveRequest({
  bool isDiscoverable = true,
  BeaconStatus status = BeaconStatus.open,
}) => Beacon(
  id: _beaconId,
  title: 'Need a ladder on Saturday',
  createdAt: DateTime.utc(2026, 10, 19),
  updatedAt: DateTime.utc(2026, 10, 19),
  startAt: DateTime.utc(2099, 6, 20, 12),
  status: status,
  viewerCanForward: true,
  isDiscoverable: isDiscoverable,
  author: _author,
);

/// Pumps the Now panel over a real `BeaconViewCubit` and lets its loads (and
/// any follow-up read the fix adds) settle.
Future<
  ({
    _ForwardsFake forwards,
    FakeUiEffectPort effects,
    BeaconViewCubit cubit,
    _RecordingRouter router,
  })
>
_pumpNow(
  WidgetTester tester, {
  required Profile viewer,
  required Beacon beacon,
  List<Profile> sentTo = const [],
  bool failForwardReads = false,
}) async {
  // A tall window, so the lazy CustomScrollView of the Now panel builds every
  // section (setSurfaceSize would not change MediaQuery).
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final forwards = _ForwardsFake(
    request: beacon,
    sentTo: sentTo,
    failReads: failForwardReads,
  );
  final effects = FakeUiEffectPort();
  final case_ = buildTestBeaconViewCase(
    beaconRepo: TrackingBeaconRepository()
      ..fetchByIdHandler = (_) async => beacon,
    forward: forwards,
  );
  final cubit = BeaconViewCubit(
    id: _beaconId,
    myProfile: viewer,
    beaconViewCase: case_,
    effects: effects,
  );
  addTearDown(cubit.close);

  final hierarchyCubit = BeaconHierarchyCubit(
    beaconId: _beaconId,
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

  final router = _RecordingRouter();

  await tester.pumpWidget(
    StackRouterScope(
      controller: router,
      stateHash: 0,
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: _MockProfileCubit(viewer)),
            BlocProvider<ThreadsCubit>.value(value: _MockThreadsCubit()),
            BlocProvider<BeaconHierarchyCubit>.value(value: hierarchyCubit),
          ],
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: BeaconNowSurface(
                beaconViewCubit: cubit,
                screenCubit: screenCubit,
                beaconState: cubit.state,
                onSurfaceSelected: (_) {},
                onActivatePeopleTabAttention: () {},
                onFocusCoordinationItem: (_) {},
                onOpenGeneralThread: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 30 && !cubit.state.beaconContextLoaded; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(cubit.state.beaconContextLoaded, isTrue);
  // Room for a follow-up forwards read after the first load.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return (forwards: forwards, effects: effects, cubit: cubit, router: router);
}

void main() {
  final l10n = lookupL10n(const Locale('en'));
  final hint = find.text(l10n.beaconLiveSentToNobodyHint, findRichText: true);

  group('#484 Now panel: live in the Field, sent to nobody yet', () {
    testWidgets('author of a discoverable Request sent to nobody sees it', (
      tester,
    ) async {
      await _pumpNow(tester, viewer: _author, beacon: _liveRequest());

      expect(hint, findsOneWidget);
    });

    testWidgets('guard: no line once the author has forwarded it', (
      tester,
    ) async {
      final pumped = await _pumpNow(
        tester,
        viewer: _author,
        beacon: _liveRequest(),
        sentTo: [_bob],
      );

      // Not vacuous: the author's forwards were actually read.
      expect(pumped.forwards.reads, greaterThan(0));
      expect(hint, findsNothing);
    });

    testWidgets('guard: a failed forwards read shows no line and no error', (
      tester,
    ) async {
      final pumped = await _pumpNow(
        tester,
        viewer: _author,
        beacon: _liveRequest(),
        failForwardReads: true,
      );

      // Unknown is not "sent to nobody": no line, and the background check
      // must not surface an error to the author.
      expect(hint, findsNothing);
      expect(pumped.effects.emitted.whereType<ShowError>(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('guard: no line on a Request that is no longer open', (
      tester,
    ) async {
      await _pumpNow(
        tester,
        viewer: _author,
        beacon: _liveRequest(status: BeaconStatus.closed),
      );

      expect(hint, findsNothing);
    });

    testWidgets('guard: no "in the Field" line when hidden from the Field', (
      tester,
    ) async {
      await _pumpNow(
        tester,
        viewer: _author,
        beacon: _liveRequest(isDiscoverable: false),
      );

      expect(hint, findsNothing);
    });

    testWidgets('guard: a viewer who is not the author sees no line', (
      tester,
    ) async {
      await _pumpNow(tester, viewer: _stranger, beacon: _liveRequest());

      expect(hint, findsNothing);
    });
  });

  // PR #608 review (ichorid): the line is an action, not a caption — tapping
  // it opens Forward for this Request.
  testWidgets('#484 tapping the sent-to-nobody line opens Forward', (
    tester,
  ) async {
    final pumped = await _pumpNow(
      tester,
      viewer: _author,
      beacon: _liveRequest(),
    );
    expect(hint, findsOneWidget);
    expect(pumped.router.pushes, isEmpty);

    await tester.tap(hint);
    await tester.pump();

    expect(pumped.router.pushes, hasLength(1));
    final route = pumped.router.pushes.single;
    expect(route, isA<ForwardBeaconRoute>());
    expect((route as ForwardBeaconRoute).args!.beaconId, _beaconId);
  });

  // PR #608 review (ichorid): the background "sent to anyone?" read is
  // one-shot per screen. After it failed, later content reloads must not
  // fire it again.
  testWidgets('#484 a failed silent forwards read is not retried on reload', (
    tester,
  ) async {
    final pumped = await _pumpNow(
      tester,
      viewer: _author,
      beacon: _liveRequest(),
      failForwardReads: true,
    );
    final afterFirstLoad = pumped.forwards.reads;
    // Not vacuous: the silent read did run (and failed) once.
    expect(afterFirstLoad, greaterThan(0));
    expect(pumped.cubit.state.forwardsLoaded, isFalse);

    for (var reload = 0; reload < 2; reload++) {
      final reloading = pumped.cubit.refreshAfterClosureReview();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await reloading;
      expect(pumped.cubit.state.beaconContentLoaded, isTrue);
    }

    expect(pumped.forwards.reads, afterFirstLoad);
    expect(hint, findsNothing);
    expect(pumped.effects.emitted.whereType<ShowError>(), isEmpty);
  });

  test('#484 the line is translated in every locale', () {
    final en = lookupL10n(const Locale('en')).beaconLiveSentToNobodyHint;
    final ru = lookupL10n(const Locale('ru')).beaconLiveSentToNobodyHint;
    expect(en, isNotEmpty);
    expect(ru, isNotEmpty);
    expect(ru, isNot(en));
  });
}
