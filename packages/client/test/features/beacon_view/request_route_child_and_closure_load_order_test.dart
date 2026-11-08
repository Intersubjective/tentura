// What the Request route sends to load and refresh its child Requests and the
// closure result card, and in which order.
//
// The route is opened exactly as navigation opens it on a cold link
// (BeaconViewRoute, BeaconViewScope with its cubits, BeaconViewScreen) over
// the production cases, repositories, Ferry link chain and RemoteApiService;
// only HTTP is faked (GraphqlRoundTripServer, which holds responses back in
// rounds). Two requests in the same round both started before either was
// answered; a request in a later round started after every request of the
// earlier rounds was answered. The longest chain of requests that each start
// after the previous one ended is computed by [_depth] from that order.
//
// Operation timeline on main (after #545 PR B), measured with this harness:
//   open, all four cases:  r1 BeaconKindFetch; r2 BeaconFetchById, threads,
//                          parent reference, BeaconHierarchyCapabilities;
//                          r3 every read that needs the Request's access
//                          (involvement, offers, forwards of a live Request's
//                          author, final check of a closed one) and the
//                          three BeaconChildren groups together.
//                          Kind -> last child group: 3 rounds. Already minimal
//                          (capabilities gate the groups, the route scope only
//                          exists after the kind answer). The open takes 3
//                          rounds, except helper + closed: 5, because the
//                          closure result card (shown to a non-author who
//                          offered help) sends ClosureResultForViewer in r4
//                          and its own ClosureState in r5.
//   silent refresh:        capabilities, then active, finished, deleted one
//                          after another (4 rounds), then the parent
//                          reference. This is the 6-deep serial chain the
//                          issue reports (Kind -> FetchById -> capabilities ->
//                          3 groups) once the open and the refresh run back
//                          to back; the cause is the three awaited
//                          _loadGroup calls in BeaconHierarchyCubit
//                          ._runSilentRefresh (the initial _runLoad already
//                          uses Future.wait, and so does the explicit
//                          load(silent: true), which is _runLoad without the
//                          loading status: that call is already parallel,
//                          the serial path is the one hints and catch-ups
//                          take).
//
// Result of each assertion group on main before the fix (this file was run
// against it):
//   open window, each read once, groups together (4 cases)       pass (guard)
//   open depth 3 (author live/closed, helper live)               pass (guard)
//   open depth 4 (helper closed; 5 on main)                      FAIL
//   forwards join the access wave at the open (all 4)            pass (guard)
//   hint / catch-up silent refresh, depth 2 (8 tests)            FAIL (4 rounds)
//   hint reloads neither Request nor forwards (4)                pass (guard)
//   catch-up reloads Request once, forwards in the access wave:
//     author live                                                FAIL: the reload
//       reads the Request (r9), its access reads (r10), and only then the
//       forward lists (r11); at the open they share the access round
//     other three cases (they read no forward list)              pass
//   closure result + final check overlap (helper closed)         FAIL (r4, r5)
//   closure reads of live Requests, author closed overlap        pass (guard)
//   explicit load(silent: true) parallel                         pass (guard)
// No assertion in this file sees a repeated BeaconChildren, BeaconFetchById
// or forward read: main sends each once per open and once per trigger, so
// the repeat-load criterion is protected (guards) but not red here.

// Who starts a second load: nothing in the open itself. Left idle for 7 s the
// route sends every read once (see the idle-window tests below). A second
// hierarchy / BeaconFetchById / ForwardEdgesFetch / ForwardReasonsFetch load
// is started by a realtime signal arriving after the open, through these
// listeners that all fan out from RealtimeSyncCase:
//   BeaconHierarchyCubit._catchUpsSub, ._hierarchyChangesSub and
//   ._localHierarchyChangesSub -> _scheduleSilentRefresh -> _runSilentRefresh
//   (capabilities + three groups, serial);
//   BeaconViewCubit._catchUpsSub, ._beaconChangesSub, ._forwardChangesSub,
//   ._helpOfferChangesSub -> _requestFullRefresh (BeaconFetchById, forwards,
//   access reads). A catch-up (socket reconnect, tab visible again, server
//   `catch_up` control message) reaches both cubits at once, which is why a
//   reload shows up as a second full set of reads a few seconds in. Which
//   signal arrives in production 2-6 s after open cannot be produced by this
//   harness (no socket); the tests inject the two signals that reach the
//   hierarchy cubit and check the refresh they cause.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/author_invite_case.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/author_invite_repository.dart';
import 'package:tentura/features/beacon/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_plan/data/repository/beacon_plan_repository.dart';
import 'package:tentura/features/beacon_plan/domain/use_case/beacon_plan_case.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_state.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/features/post_view/data/repository/beacon_kind_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart'
    show InMemoryBeaconChildCommandStore;
import '../../support/graphql_round_trip_server.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'request_open_round_trips_support.dart';

class _SignedInProfileCubit extends Mock implements ProfileCubit {
  _SignedInProfileCubit(this._profile);

  final Profile _profile;

  @override
  ProfileState get state => ProfileState(profile: _profile);

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

class _RequestRouteRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      usesPathAsKey: true,
      page: BeaconViewRoute.page,
      path: '$kPathBeaconView/:id',
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

/// A change after the route settled that makes the Request reload something.
enum _Trigger {
  /// The server says the Request's child list changed.
  hierarchyHint,

  /// The realtime socket resynchronised (tab visible again, reconnect).
  catchUp,
}

typedef _Call = ({int index, int round, String name});

/// What the route did, from the first request to the end of the window.
typedef _Opened = ({
  GraphqlRoundTripServer server,

  /// Number of HTTP requests sent before the trigger (the open itself).
  int openCalls,
  BeaconHierarchyState hierarchy,

  /// Whether the child list showed a loading state after the trigger. A
  /// silent refresh never does; an explicit load does.
  bool refreshShowedLoading,
});

/// Every operation sent, in send order, with the round it was sent in.
List<_Call> _operations(GraphqlRoundTripServer server) => [
  for (final (i, call) in server.calls.indexed)
    for (final name in call.operationNames)
      (index: i, round: call.round, name: name),
];

List<_Call> _named(Iterable<_Call> calls, String name) => [
  for (final call in calls)
    if (call.name == name) call,
];

Set<int> _roundsOf(Iterable<_Call> calls) => {for (final c in calls) c.round};

/// Length of the longest chain of requests in [calls] where each one starts
/// after the previous one was answered, computed from start/end order.
///
/// The harness answers a round atomically: every request of round r is
/// answered at the same instant, and a request sent after that instant is in
/// round r + 1 or later. So a request of round r occupies [r, r + 1) and one
/// request precedes another exactly when its round is smaller.
int _depth(Iterable<_Call> calls) {
  final sorted = calls.toList()..sort((a, b) => a.round.compareTo(b.round));
  final chainEndingAt = <int>[];
  var longest = 0;
  for (var i = 0; i < sorted.length; i++) {
    var best = 1;
    for (var j = 0; j < i; j++) {
      final answeredBeforeStart = sorted[j].round + 1 <= sorted[i].round;
      if (answeredBeforeStart && chainEndingAt[j] + 1 > best) {
        best = chainEndingAt[j] + 1;
      }
    }
    chainEndingAt.add(best);
    if (best > longest) longest = best;
  }
  return longest;
}

/// A server for [viewerId] viewing the Request, who can list its child groups
/// (one child per group) and, being a helper, has offered help.
GraphqlRoundTripServer _server({
  required String viewerId,
  required BeaconStatus status,
}) {
  final base = openRoundsServer(viewerId: viewerId, status: status);
  return GraphqlRoundTripServer(
    viewerId: viewerId,
    overrides: (type, field, operation) => switch ((type, field)) {
      ('v2_BeaconHierarchyCapabilities', 'canListChildren') => true,
      ('v2_BeaconHierarchyCapabilities', 'canCreateChild') => false,
      ('v2_BeaconHierarchyCapabilities', 'denialCode') => null,
      ('v2_BeaconHierarchyPage', 'summaries') => GraphqlRoundTripServer.oneRow,
      ('v2_BeaconHierarchyPage', 'nextCursor') => null,
      // The helper's own offer, so the closed Request shows their result.
      ('query_root', 'helpOffersWithCoordination')
          when viewerId == kOpenRoundsHelperId =>
        GraphqlRoundTripServer.oneRow,
      ('v2_HelpOfferWithCoordinationRow', 'userId') || ('v2_user', 'id')
          when operation == 'HelpOffersWithCoordination' =>
        viewerId,
      ('v2_HelpOfferWithCoordinationRow', 'beaconId') => kOpenRoundsBeaconId,
      _ => base.overrides!(type, field, operation),
    },
  );
}

/// Opens the Request route as [viewerId] (a cold deep link), answers every
/// read until the route is idle, then optionally fires [trigger] and answers
/// every read it causes. Each idle window is 7 s of fake time, long enough to
/// catch a reload that starts a few seconds after the open.
Future<_Opened> _open(
  WidgetTester tester, {
  required String viewerId,
  required BeaconStatus status,
  _Trigger? trigger,
}) async {
  final server = _server(viewerId: viewerId, status: status);
  final effects = FakeUiEffectPort();
  late _Opened opened;
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await http.runWithClient(() async {
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
    );
    final realtime = buildTestRealtimeSync();
    final router = _RequestRouteRouter();
    await GetIt.I.reset();
    try {
      await remote.setSessionAuth();
      final wired = buildWiredBeaconViewCase(remote, realtime);
      final images = ImageRepository();
      final profile = _SignedInProfileCubit(
        Profile(id: viewerId, displayName: 'Viewer'),
      );
      final screen = ScreenCubit(effects);
      GetIt.I
        ..registerSingleton<UiEffectPort>(effects)
        ..registerSingleton<ProfileCubit>(profile)
        ..registerSingleton<ScreenCubit>(screen)
        ..registerSingleton<ImageRepository>(images)
        ..registerSingleton<ClipboardImageRepository>(
          ClipboardImageRepository(),
        )
        ..registerSingleton<BeaconKindRepository>(
          BeaconKindRepository(remote),
        )
        ..registerSingleton<BeaconViewCase>(wired.viewCase)
        ..registerSingleton<BeaconThreadsCase>(wired.threadsCase)
        ..registerSingleton<ClosureCase>(
          ClosureCase(
            ClosureRepository(remote),
            env: const Env(),
            logger: Logger('request-route-load-order'),
          ),
        )
        ..registerSingleton<BeaconHierarchyCase>(
          BeaconHierarchyCase(
            BeaconHierarchyRepository(remote),
            BeaconCreateCase(wired.beacons, images),
            wired.beacons,
            InMemoryBeaconChildCommandStore(),
            realtime.case_,
          ),
        )
        ..registerSingleton<BeaconPlanCase>(
          BeaconPlanCase(
            BeaconPlanRepository(remote, realtime.port),
            env: const Env(),
            logger: Logger('request-route-load-order'),
          ),
        )
        ..registerSingleton<AuthorInviteCase>(
          AuthorInviteCase(
            AuthorInviteRepository(remote),
            env: const Env(),
            logger: Logger('request-route-load-order'),
          ),
        );
      await tester.pumpWidget(
        MaterialApp.router(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => MultiBlocProvider(
            providers: [
              BlocProvider<ScreenCubit>.value(value: screen),
              BlocProvider<ProfileCubit>.value(value: profile),
            ],
            child: child!,
          ),
          routerConfig: router.config(
            deepLinkBuilder: (_) => const DeepLink.path(
              '$kPathBeaconView/$kOpenRoundsBeaconId',
            ),
          ),
        ),
      );
      Future<void> idle() => server.drain(
        settle: const Duration(seconds: 7),
        timeout: const Duration(seconds: 120),
        wait: () => tester.pump(const Duration(milliseconds: 10)),
      );

      // The window is quiet again only once the trigger's own reads started:
      // let the cubits' debounce timers run before waiting for idle.
      Future<void> afterTrigger() async {
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        await idle();
      }

      await idle();
      final openCalls = server.calls.length;
      final hierarchyCubit = tester
          .element(find.byType(BeaconViewScreen))
          .read<BeaconHierarchyCubit>();
      var refreshShowedLoading = false;
      final loadingWatch = hierarchyCubit.stream.listen((state) {
        if (state.status is StateIsLoading ||
            state.active.loading ||
            state.finished.loading ||
            state.deleted.loading) {
          refreshShowedLoading = true;
        }
      });
      switch (trigger) {
        case _Trigger.hierarchyHint:
          realtime.port.emitChange(
            const RealtimeEntityChange(
              kind: RealtimeEntityKind.beaconHierarchy,
              aggregateId: kOpenRoundsBeaconId,
              operation: RealtimeOperation.update,
              source: RealtimeChangeSource.serverInvalidation,
            ),
          );
          await afterTrigger();
        case _Trigger.catchUp:
          realtime.port.emitCatchUp(
            accountId: viewerId,
            reason: RealtimeCatchUpReason.webVisibilityRestored,
          );
          await afterTrigger();
        case null:
      }
      await tester.pump();
      unawaited(loadingWatch.cancel());
      opened = (
        server: server,
        openCalls: openCalls,
        hierarchy: hierarchyCubit.state,
        refreshShowedLoading: refreshShowedLoading,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await realtime.port.dispose();
      await remote.close();
      await GetIt.I.reset();
    }
  }, () => server.client);
  return opened;
}

void _expectChildGroupsShown(_Opened opened) {
  final trace = opened.server.describe();
  expect(opened.hierarchy.capabilities?.canListChildren, isTrue, reason: trace);
  expect(opened.hierarchy.active.items, hasLength(1), reason: trace);
  expect(opened.hierarchy.finished.items, hasLength(1), reason: trace);
  expect(opened.hierarchy.deleted.items, hasLength(1), reason: trace);
}

/// The silent refresh of the child list that the trigger caused after the
/// open: capabilities, then the three groups together (depth 2, pinned).
void _expectParallelSilentRefresh(_Opened opened) {
  final trace = opened.server.describe();
  final after = _operations(
    opened.server,
  ).where((c) => c.index >= opened.openCalls).toList();
  final children = _named(after, 'BeaconChildren');
  final hierarchyReads = after.where(
    (c) =>
        c.name == 'BeaconChildren' || c.name == 'BeaconHierarchyCapabilities',
  );

  expect(
    opened.refreshShowedLoading,
    isFalse,
    reason:
        'The trigger must reach the silent refresh (load(silent: true)), '
        'which never shows a loading state.\n$trace',
  );
  expect(
    _named(after, 'BeaconHierarchyCapabilities'),
    isNotEmpty,
    reason: 'The refresh checked no capabilities.\n$trace',
  );
  expect(children, isNotEmpty, reason: 'The refresh loaded no groups.\n$trace');
  expect(
    _roundsOf(children),
    hasLength(1),
    reason:
        'The active, finished and deleted groups of the refresh wait for '
        'each other instead of starting before any of them completes.\n'
        '$trace',
  );
  expect(
    _depth(hierarchyReads),
    2,
    reason:
        'A child-list refresh is capabilities, then one parallel step '
        '(4 rounds before).\n$trace',
  );
  expect(_depth(hierarchyReads), lessThan(6), reason: trace);
  _expectChildGroupsShown(opened);
}

/// The Request read of one load (its BeaconFetchById) is the access query:
/// it returns what the viewer may read. Every read that needs the answer
/// starts in the round after it, which is the access wave. Forward lists
/// join that wave when they start in it or earlier, instead of after it.
void _expectForwardsJoinAccessWave(List<_Call> load, String trace) {
  final request = _named(load, 'BeaconFetchById');
  expect(request, hasLength(1), reason: trace);
  final accessWave = request.single.round + 1;
  for (final name in ['ForwardEdgesFetch', 'ForwardReasonsFetch']) {
    for (final call in _named(load, name)) {
      expect(
        call.round,
        lessThanOrEqualTo(accessWave),
        reason:
            '$name starts in round ${call.round + 1}, after the access wave '
            '(round ${accessWave + 1}, the round after the Request read was '
            'answered) had begun.\n'
            '$trace',
      );
    }
  }
}

/// What one trigger reloads, besides the child groups: a catch-up reloads the
/// Request once (BeaconFetchById, and the forward lists the open also read,
/// each once); a hierarchy hint concerns only the child list and reloads
/// none of them.
void _expectDetailReloads(_Opened opened, _Trigger trigger) {
  final trace = opened.server.describe();
  final all = _operations(opened.server);
  final atOpen = all.where((c) => c.index < opened.openCalls).toList();
  final after = all.where((c) => c.index >= opened.openCalls).toList();
  final reloadsOnce = trigger == _Trigger.catchUp;

  expect(
    _named(after, 'BeaconFetchById'),
    hasLength(reloadsOnce ? 1 : 0),
    reason: trace,
  );
  for (final name in ['ForwardEdgesFetch', 'ForwardReasonsFetch']) {
    expect(
      _named(after, name),
      hasLength(reloadsOnce ? _named(atOpen, name).length : 0),
      reason: '$name\n$trace',
    );
  }
  expect(
    _named(after, 'BeaconHierarchyCapabilities'),
    hasLength(1),
    reason: trace,
  );
  expect(
    _named(after, 'BeaconChildren').length,
    lessThanOrEqualTo(3),
    reason: trace,
  );
  if (reloadsOnce) _expectForwardsJoinAccessWave(after, trace);
}

/// Wherever a load reads the closure result, the final check is read
/// together with it, not before or after it was answered.
void _expectClosureReadsOverlap(List<_Call> calls, String trace) {
  final state = _named(calls, 'ClosureState');
  for (final result in _named(calls, 'ClosureResultForViewer')) {
    expect(
      state.any((s) => s.round == result.round),
      isTrue,
      reason:
          'No ClosureState read starts together with '
          'ClosureResultForViewer: one is answered before the other starts.\n'
          '$trace',
    );
  }
}

/// One row per case: who views, what state, what the open does today.
typedef _Case = ({
  String label,
  String viewerId,
  BeaconStatus status,

  /// ForwardEdgesFetch and ForwardReasonsFetch calls of one open, where the
  /// open reads them for sure (the author's live Request); null: at most once
  /// (the other cases read no forward list today).
  int? forwardCalls,

  /// Round trips the whole open takes after the fix. Helper + closed has the
  /// closure result card: Kind, Request, access wave, then the card's reads.
  int openDepth,
});

void main() {
  final cases = <_Case>[
    (
      label: 'author, live',
      viewerId: kOpenRoundsAuthorId,
      status: BeaconStatus.open,
      forwardCalls: 1,
      openDepth: 3,
    ),
    (
      label: 'author, closed',
      viewerId: kOpenRoundsAuthorId,
      status: BeaconStatus.closed,
      forwardCalls: null,
      openDepth: 3,
    ),
    (
      label: 'helper, live',
      viewerId: kOpenRoundsHelperId,
      status: BeaconStatus.open,
      forwardCalls: null,
      openDepth: 3,
    ),
    (
      label: 'helper, closed',
      viewerId: kOpenRoundsHelperId,
      status: BeaconStatus.closed,
      forwardCalls: null,
      openDepth: 4,
    ),
  ];

  group('Request route open: child groups, repeat loads and depth', () {
    for (final c in cases) {
      testWidgets(
        'child groups start together and every read happens exactly once '
        'in the seven seconds after the open (${c.label})',
        (tester) async {
          final opened = await _open(
            tester,
            viewerId: c.viewerId,
            status: c.status,
          );
          final trace = opened.server.describe();
          final calls = _operations(opened.server);

          // Three groups, one call each, all started before any answered.
          expect(
            _named(calls, 'BeaconChildren'),
            hasLength(3),
            reason: 'One call per group.\n$trace',
          );
          expect(
            _roundsOf(_named(calls, 'BeaconChildren')),
            hasLength(1),
            reason: trace,
          );
          expect(
            _named(calls, 'BeaconHierarchyCapabilities'),
            hasLength(1),
            reason: trace,
          );
          expect(_named(calls, 'BeaconFetchById'), hasLength(1), reason: trace);
          for (final name in ['ForwardEdgesFetch', 'ForwardReasonsFetch']) {
            expect(
              _named(calls, name),
              c.forwardCalls == null
                  ? hasLength(lessThanOrEqualTo(1))
                  : hasLength(c.forwardCalls),
              reason: '$name\n$trace',
            );
          }
          _expectChildGroupsShown(opened);
        },
      );

      testWidgets(
        'the open spans exactly ${c.openDepth} dependent rounds, from the '
        'kind check to the last read (${c.label})',
        (tester) async {
          final opened = await _open(
            tester,
            viewerId: c.viewerId,
            status: c.status,
          );
          final calls = _operations(opened.server);
          final trace = opened.server.describe();

          expect(_depth(calls), c.openDepth, reason: trace);
          expect(_depth(calls), lessThan(6), reason: trace);
          _expectForwardsJoinAccessWave(calls, trace);
          // Kind -> last child group is the chain the issue is about.
          final lastGroupRound = _named(
            calls,
            'BeaconChildren',
          ).map((c) => c.round).reduce((a, b) => a > b ? a : b);
          expect(
            _depth(calls.where((c) => c.round <= lastGroupRound)),
            3,
            reason: trace,
          );
        },
      );

      testWidgets(
        'a changed child list refreshes silently: capabilities, then all '
        'three groups together (${c.label})',
        (tester) async {
          final opened = await _open(
            tester,
            viewerId: c.viewerId,
            status: c.status,
            trigger: _Trigger.hierarchyHint,
          );
          _expectParallelSilentRefresh(opened);
        },
      );

      testWidgets(
        'a realtime catch-up refreshes the child list silently: '
        'capabilities, then all three groups together (${c.label})',
        (tester) async {
          final opened = await _open(
            tester,
            viewerId: c.viewerId,
            status: c.status,
            trigger: _Trigger.catchUp,
          );
          _expectParallelSilentRefresh(opened);
        },
      );

      testWidgets(
        'a changed child list does not reload the Request or its forward '
        'lists (${c.label})',
        (tester) async {
          final opened = await _open(
            tester,
            viewerId: c.viewerId,
            status: c.status,
            trigger: _Trigger.hierarchyHint,
          );
          _expectDetailReloads(opened, _Trigger.hierarchyHint);
        },
      );

      testWidgets(
        'a realtime catch-up reloads the Request and its forward lists once, '
        'the forward lists with the access wave (${c.label})',
        (tester) async {
          final opened = await _open(
            tester,
            viewerId: c.viewerId,
            status: c.status,
            trigger: _Trigger.catchUp,
          );
          _expectDetailReloads(opened, _Trigger.catchUp);
        },
      );
    }
  });

  group('Request route open: closure reads', () {
    for (final (label, viewerId) in [
      ('author', kOpenRoundsAuthorId),
      ('helper', kOpenRoundsHelperId),
    ]) {
      testWidgets(
        'a live Request opened by its $label reads no closure state or '
        'result',
        (tester) async {
          final opened = await _open(
            tester,
            viewerId: viewerId,
            status: BeaconStatus.open,
          );
          final calls = _operations(opened.server);
          expect(
            _named(calls, 'ClosureState'),
            isEmpty,
            reason: opened.server.describe(),
          );
          expect(
            _named(calls, 'ClosureResultForViewer'),
            isEmpty,
            reason: opened.server.describe(),
          );
        },
      );
    }

    for (final c in cases.where((c) => c.status == BeaconStatus.closed)) {
      testWidgets(
        'the closure result and the final check never wait for each other '
        '(${c.label})',
        (tester) async {
          final opened = await _open(
            tester,
            viewerId: c.viewerId,
            status: c.status,
          );
          final calls = _operations(opened.server);
          // The result card is built for a non-author who offered help, so
          // the author's open has no result read to overlap with.
          expect(
            _named(calls, 'ClosureResultForViewer'),
            c.viewerId == kOpenRoundsHelperId ? hasLength(1) : isEmpty,
            reason: opened.server.describe(),
          );
          _expectClosureReadsOverlap(calls, opened.server.describe());
        },
      );
    }
  });

  group('BeaconHierarchyCubit explicit silent load', () {
    // Guard: load(silent: true) runs the initial-load path, already parallel.
    test(
      'load(silent: true) starts the active, finished and deleted groups '
      'before any of them is answered',
      () async {
        final server = _server(
          viewerId: kOpenRoundsAuthorId,
          status: BeaconStatus.open,
        );
        late BeaconHierarchyState shown;
        await http.runWithClient(() async {
          final remote = RemoteApiService(
            const Env(),
            const WebSocketClientRealtimeSocketFactory(),
          );
          final realtime = buildTestRealtimeSync();
          try {
            await remote.setSessionAuth();
            final beacons = BeaconRepository(remote, realtime.port);
            final cubit = BeaconHierarchyCubit(
              beaconId: kOpenRoundsBeaconId,
              hierarchyCase: BeaconHierarchyCase(
                BeaconHierarchyRepository(remote),
                BeaconCreateCase(beacons, ImageRepository()),
                beacons,
                InMemoryBeaconChildCommandStore(),
                realtime.case_,
              ),
            );
            unawaited(cubit.load());
            await server.drain();
            final initialCalls = server.calls.length;
            unawaited(cubit.load(silent: true));
            await server.drain();
            shown = cubit.state;
            final refresh = _operations(
              server,
            ).where((c) => c.index >= initialCalls).toList();
            final trace = server.describe();
            final children = _named(refresh, 'BeaconChildren');

            expect(children, hasLength(3), reason: trace);
            expect(
              _roundsOf(children),
              hasLength(1),
              reason:
                  'The silent refresh awaits each group before starting '
                  'the next.\n$trace',
            );
            expect(_depth(refresh), 2, reason: trace);
            await cubit.close();
          } finally {
            await realtime.port.dispose();
            await remote.close();
          }
        }, () => server.client);

        expect(shown.active.items, hasLength(1));
        expect(shown.finished.items, hasLength(1));
        expect(shown.deleted.items, hasLength(1));
      },
    );
  });
}
