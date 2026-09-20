import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/inbox_screen.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/inbox/ui/widget/for_you_empty_state.dart';
import 'package:tentura/ui/widget/caught_up_panel.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'inbox_case_test.dart'
    show
        FakeInboxRepository,
        buildTestBeaconThreadsCase,
        buildTestInboxCase;
import '../../support/noop_attention_actor_profiles.dart';

class _HarnessRouter extends Mock implements StackRouter {
  PageRouteInfo? lastPush;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    lastPush = route;
    return null;
  }
}

class _TestInboxCubit extends Cubit<InboxState> implements InboxCubit {
  _TestInboxCubit(super.initial);


  @override
  void clearPendingMovedNudge() {}

  @override
  Future<bool> fetch({bool showLoading = true, bool showError = true}) async =>
      true;

  @override
  Future<void> setWatching(String beaconId) async {}

  @override
  Future<void> stopWatching(String beaconId) async {}

  @override
  Future<void> reject(String beaconId, {String message = ''}) async {}

  @override
  Future<void> unreject(String beaconId) async {}

  @override
  Future<void> dismissTombstone(String beaconId) async {}
}

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _ForwardRepo implements ForwardRepository {
  final _helpOfferChanges = StreamController<HelpOfferEvent>.broadcast();
  final _forwardChanges = StreamController<String>.broadcast();
  final _forwardCommandCompleted = StreamController<String>.broadcast();

  @override
  Stream<HelpOfferEvent> get helpOfferChanges => _helpOfferChanges.stream;

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Stream<String> get forwardCommandCompleted => _forwardCommandCompleted.stream;

  @override
  Future<void> dispose() async {
    await _helpOfferChanges.close();
    await _forwardChanges.close();
    await _forwardCommandCompleted.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ChromeAttentionRepo extends AttentionRepositoryFake {
  _ChromeAttentionRepo({
    this.activityUnread = 0,
    this.sweepEligible = false,
    this.forYouDot = false,
    this.dismissAllResult,
    this.undoResult,
  });

  int activityUnread;

  /// CHANGES IN U16c-1: the header control is the **clear** axis (D02), so it
  /// is gated on this and not on [activityUnread] (the read axis) and not on
  /// [forYouDot] (which counts the pinned decision zone the sweep refuses to
  /// touch — owner decision A).
  bool sweepEligible;
  bool forYouDot;

  AttentionDismissAllResult? dismissAllResult;
  AttentionUndoResult? undoResult;

  AttentionSurface? lastMarkAllSurface;
  final dismissAllOperationIds = <String>[];
  String? lastUndoOperationId;
  String? lastUndoToken;

  @override
  Future<AttentionSurfaceSummary> surfaceSummary() async =>
      AttentionSurfaceSummary(
        activityUnreadTotal: activityUnread,
        myWorkUnreadTotal: 0,
        needsYouTotal: 0,
        forYouDot: forYouDot,
        forYouSweepEligible: sweepEligible,
      );

  @override
  Future<AttentionDismissAllResult> dismissAll({
    required String operationId,
    int? maxBatches,
  }) async {
    dismissAllOperationIds.add(operationId);
    sweepEligible = false;
    final canned = dismissAllResult;
    return canned == null
        ? AttentionDismissAllResult(
            operationId: operationId,
            status: AttentionOperationStatus.complete,
            appliedCount: 2,
          )
        : canned.copyWith(operationId: operationId);
  }

  @override
  Future<AttentionUndoResult> undo({
    required String operationId,
    required String undoToken,
  }) async {
    lastUndoOperationId = operationId;
    lastUndoToken = undoToken;
    return undoResult ??
        AttentionUndoResult(
          operationId: operationId,
          status: AttentionOperationStatus.complete,
          restoredReceiptIds: const ['r1', 'r2'],
        );
  }

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async =>
      const AttentionFeed(
        summary: AttentionSummary(),
        page: AttentionFeedPage(),
      );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async {
    lastMarkAllSurface = surface;
    activityUnread = 0;
    return 0;
  }

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

Future<void> _pumpInbox(
  WidgetTester tester, {
  required _ChromeAttentionRepo attentionRepo,
  required _HarnessRouter router,
}) async {
  const logicalSize = Size(800, 800);
  tester.view.physicalSize = logicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    attentionRepo,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('activity-chrome-test'),
  );
  accounts.emit('viewer');
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }

  final inboxRepo = FakeInboxRepository()..openForwardsCount = 0;
  final inboxCase = buildTestInboxCase(
    inboxRepo,
    buildTestBeaconThreadsCase(),
    forwardRepository: _ForwardRepo(),
  );

  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(attention);
  ensureNoopAttentionActorProfilesRegistered();
  GetIt.I.registerSingleton(inboxCase);
  GetIt.I.registerSingleton<InviteAcceptedSetupPort>(
    NoopInviteAcceptedSetupPort(),
  );
  GetIt.I.registerSingleton<RealtimeSyncCase>(sync.case_);
  if (!GetIt.I.isRegistered<Logger>()) {
    GetIt.I.registerSingleton<Logger>(Logger('activity-chrome-test'));
  }
  addTearDown(() async {
    await attention.dispose();
    await accounts.close();
    await sync.port.dispose();
    if (GetIt.I.isRegistered<AttentionCase>()) {
      GetIt.I.unregister<AttentionCase>();
    }
    if (GetIt.I.isRegistered<InboxCase>()) {
      GetIt.I.unregister<InboxCase>();
    }
    if (GetIt.I.isRegistered<InviteAcceptedSetupPort>()) {
      GetIt.I.unregister<InviteAcceptedSetupPort>();
    }
    if (GetIt.I.isRegistered<RealtimeSyncCase>()) {
      GetIt.I.unregister<RealtimeSyncCase>();
    }
    if (GetIt.I.isRegistered<Logger>()) {
      GetIt.I.unregister<Logger>();
    }
  });

  final inboxCubit = _TestInboxCubit(
    const InboxState(status: StateIsSuccess(), projectionLoaded: true),
  );
  final homeAttention = HomeAttentionCubit(
    attention,
    accounts,
    Logger('activity-chrome-test'),
  );

  await tester.pumpWidget(
    StackRouterScope(
      controller: router,
      stateHash: 0,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<InboxCubit>.value(value: inboxCubit),
          BlocProvider<HomeAttentionCubit>.value(value: homeAttention),
          BlocProvider(create: (_) => HomeTabReselectCubit()),
          BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
          BlocProvider(create: (_) => ScreenCubit.local()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(size: logicalSize),
            child: const TenturaResponsiveScope(child: InboxScreen()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Keyed, not found by icon: a header action found by its glyph is a finder
/// that keeps passing when the action behind it changes, which is exactly how
/// the read-axis control survived into a clear-axis surface.
const _dismissAllKey = 'inbox-dismiss-all';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tapDismissAll(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key(_dismissAllKey)));
  await _settle(tester);
}

void main() {

  // CHANGES IN U16c-1: these three asserted the *read* axis — `Icons.done_all`,
  // "Read all", `markAllSeen` and an `activityUnreadTotal` gate. D02 says For
  // You's header gesture is the **clear** axis, so the control, the signal and
  // the call all change together. Each rewritten assertion states the new
  // expectation positively: the sweep icon is present, the sweep was called,
  // and `markAllSeen` was **not**.

  testWidgets(
    'gate on: top bar uses Activity title and the Dismiss all control',
    (tester) async {
      final repo = _ChromeAttentionRepo(sweepEligible: true);
      final router = _HarnessRouter();
      await _pumpInbox(tester, attentionRepo: repo, router: router);

      final l10n = L10nEn();
      expect(find.text(l10n.inbox), findsOneWidget);
      expect(find.text(l10n.updatesTitle), findsNothing);
      expect(
        find.byIcon(Icons.done_all),
        findsNothing,
        reason: 'the read-axis control is gone, not merely relabelled',
      );

      final dismissAll = tester.widget<IconButton>(
        find.byKey(const Key(_dismissAllKey)),
      );
      expect(dismissAll.onPressed, isNotNull);
      expect(dismissAll.tooltip, l10n.inboxDismissAll);

      expect(find.byType(ActivityStreamView), findsOneWidget);
    },
  );

  testWidgets(
    'gate on: Dismiss all is disabled when the sweep would clear nothing',
    (tester) async {
      await _pumpInbox(
        tester,
        // The exact trap `forYouDot` sets: the tab is lit by an unanswered
        // forward, and the sweep would still capture nothing. A control gated
        // on the dot would be enabled here and do nothing when tapped.
        attentionRepo: _ChromeAttentionRepo(
          activityUnread: 7,
          forYouDot: true,
          sweepEligible: false,
        ),
        router: _HarnessRouter(),
      );

      final dismissAll = tester.widget<IconButton>(
        find.byKey(const Key(_dismissAllKey)),
      );
      expect(dismissAll.onPressed, isNull);
    },
  );

  testWidgets(
    'gate on: Dismiss all is enabled by sweep eligibility, not unread',
    (tester) async {
      // The mirror of the previous case: nothing unread on the read axis, but
      // the sweep has members. Gating on `activityUnreadTotal` would leave a
      // surface that can never reach zero.
      await _pumpInbox(
        tester,
        attentionRepo: _ChromeAttentionRepo(
          activityUnread: 0,
          sweepEligible: true,
        ),
        router: _HarnessRouter(),
      );

      final dismissAll = tester.widget<IconButton>(
        find.byKey(const Key(_dismissAllKey)),
      );
      expect(dismissAll.onPressed, isNotNull);
    },
  );

  testWidgets('gate on: Dismiss all sweeps and never marks seen', (
    tester,
  ) async {
    final repo = _ChromeAttentionRepo(activityUnread: 3, sweepEligible: true);
    await _pumpInbox(tester, attentionRepo: repo, router: _HarnessRouter());

    await _tapDismissAll(tester);

    expect(repo.dismissAllOperationIds, hasLength(1));
    expect(
      repo.lastMarkAllSurface,
      isNull,
      reason: 'clearing is not reading (§3) — the sweep must not mark seen',
    );
  });

  testWidgets('gate on: a completed sweep offers undo within the window', (
    tester,
  ) async {
    // §4: "an explicit dismissal can be undone for a short window."
    final repo = _ChromeAttentionRepo(
      sweepEligible: true,
      dismissAllResult: AttentionDismissAllResult(
        operationId: 'placeholder',
        status: AttentionOperationStatus.complete,
        appliedCount: 3,
        appliedReceiptIds: const ['r1', 'r2', 'r3'],
        undoToken: 'undo-token',
        undoDeadline: DateTime.now().add(const Duration(seconds: 30)),
      ),
    );
    await _pumpInbox(tester, attentionRepo: repo, router: _HarnessRouter());

    await _tapDismissAll(tester);

    final l10n = L10nEn();
    // The count is now stated twice on purpose — once in the transient snack
    // bar that carries Undo, once on the cleared state D18 rewards — so this
    // pins the snack bar's copy specifically.
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(l10n.inboxDismissAllCleared(3), findRichText: true),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.inboxDismissAllUndo), findsOneWidget);

    await tester.tap(find.text(l10n.inboxDismissAllUndo));
    await _settle(tester);

    expect(repo.lastUndoOperationId, repo.dismissAllOperationIds.single);
    expect(repo.lastUndoToken, 'undo-token');
    expect(find.text(l10n.inboxDismissAllUndone(2), findRichText: true), findsOneWidget);
  });

  testWidgets('gate on: a sweep with no undo token offers no undo', (
    tester,
  ) async {
    final repo = _ChromeAttentionRepo(
      sweepEligible: true,
      dismissAllResult: const AttentionDismissAllResult(
        operationId: 'placeholder',
        status: AttentionOperationStatus.complete,
        appliedCount: 1,
      ),
    );
    await _pumpInbox(tester, attentionRepo: repo, router: _HarnessRouter());

    await _tapDismissAll(tester);

    final l10n = L10nEn();
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(l10n.inboxDismissAllCleared(1), findRichText: true),
      ),
      findsOneWidget,
    );
    expect(
      find.text(l10n.inboxDismissAllUndo),
      findsNothing,
      reason: 'an undo affordance with no token is a lie',
    );
  });

  testWidgets('gate on: a partial sweep says so and offers to continue', (
    tester,
  ) async {
    // §4 _Avoid_: celebrating "all clear" after a partial sweep.
    final repo = _ChromeAttentionRepo(
      sweepEligible: true,
      dismissAllResult: const AttentionDismissAllResult(
        operationId: 'placeholder',
        status: AttentionOperationStatus.partial,
        appliedCount: 5,
        pendingCount: 4,
      ),
    );
    await _pumpInbox(tester, attentionRepo: repo, router: _HarnessRouter());

    await _tapDismissAll(tester);

    final l10n = L10nEn();
    expect(find.text(l10n.inboxDismissAllPartial(5), findRichText: true), findsOneWidget);
    expect(
      find.text(l10n.inboxDismissAllCleared(5), findRichText: true),
      findsNothing,
      reason: 'a bounded sweep that did not finish must not read as done',
    );

    await tester.tap(find.text(l10n.inboxDismissAllContinue));
    await _settle(tester);

    expect(
      repo.dismissAllOperationIds,
      hasLength(2),
      reason: 'resume is a second call…',
    );
    expect(
      repo.dismissAllOperationIds.toSet(),
      hasLength(1),
      reason: '…with the *same* operation id, or the server captures twice',
    );
  });

  testWidgets('gate on: a denied sweep fails honestly', (tester) async {
    final repo = _ChromeAttentionRepo(
      sweepEligible: true,
      dismissAllResult: const AttentionDismissAllResult(
        operationId: 'placeholder',
        status: AttentionOperationStatus.denied,
      ),
    );
    await _pumpInbox(tester, attentionRepo: repo, router: _HarnessRouter());

    await _tapDismissAll(tester);

    final l10n = L10nEn();
    expect(find.text(l10n.inboxDismissAllFailed, findRichText: true), findsOneWidget);
    expect(find.text(l10n.inboxDismissAllCleared(0), findRichText: true), findsNothing);
  });

  testWidgets('gate on: a refused undo says so and restores nothing', (
    tester,
  ) async {
    final repo = _ChromeAttentionRepo(
      sweepEligible: true,
      dismissAllResult: AttentionDismissAllResult(
        operationId: 'placeholder',
        status: AttentionOperationStatus.complete,
        appliedCount: 2,
        undoToken: 'undo-token',
        undoDeadline: DateTime.now().add(const Duration(seconds: 30)),
      ),
      undoResult: const AttentionUndoResult(
        operationId: 'placeholder',
        status: AttentionOperationStatus.denied,
        refusal: AttentionUndoRefusal.expired,
      ),
    );
    await _pumpInbox(tester, attentionRepo: repo, router: _HarnessRouter());

    await _tapDismissAll(tester);
    final l10n = L10nEn();
    await tester.tap(find.text(l10n.inboxDismissAllUndo));
    await _settle(tester);

    expect(find.text(l10n.inboxDismissAllUndoFailed, findRichText: true), findsOneWidget);
    expect(find.text(l10n.inboxDismissAllUndone(0), findRichText: true), findsNothing);
  });

  testWidgets(
    'gate on: an empty For You stream renders §4\'s empty state, once',
    (tester) async {
      // The positive assert: a fixture that renders nothing would satisfy any
      // "did not overflow" check, so this pins the keyed title and the exact
      // sentence — and pins that it is the *nothing here* voice, because this
      // harness has no pinned decision zone.
      await _pumpInbox(
        tester,
        attentionRepo: _ChromeAttentionRepo(),
        router: _HarnessRouter(),
      );

      final l10n = L10nEn();
      expect(find.byType(ForYouEmptyState), findsOneWidget);
      expect(find.byKey(ForYouEmptyState.titleKey), findsOneWidget);
      expect(find.text(l10n.forYouEmptyNothingHere), findsOneWidget);
      expect(
        find.text(l10n.forYouEmptyNothingNew),
        findsNothing,
        reason: 'nothing was cleared here, so nothing was "cleared"',
      );
    },
  );

  testWidgets(
    'gate on: a completed sweep leaves the reward, with the real number',
    (tester) async {
      // D18 — "after an explicit sweep, show the actual number cleared". The
      // sweep runs from the app bar and the empty state is in the body, so
      // this is also the proof the two are actually connected.
      final repo = _ChromeAttentionRepo(
        sweepEligible: true,
        dismissAllResult: const AttentionDismissAllResult(
          operationId: 'placeholder',
          status: AttentionOperationStatus.complete,
          appliedCount: 5,
        ),
      );
      await _pumpInbox(tester, attentionRepo: repo, router: _HarnessRouter());

      final l10n = L10nEn();
      expect(
        find.text(l10n.forYouEmptyNothingHere),
        findsOneWidget,
        reason: 'before the sweep this surface has never had anything',
      );

      await _tapDismissAll(tester);

      expect(find.byType(ForYouEmptyState), findsOneWidget);
      expect(find.byKey(CaughtUpPanel.illustrationKey), findsOneWidget);
      expect(find.text(l10n.forYouEmptyNothingNew), findsOneWidget);
      expect(find.text(l10n.forYouEmptyNothingNewHint), findsOneWidget);
      expect(
        find.text(l10n.inboxDismissAllCleared(5)),
        findsWidgets,
        reason: 'the number on the panel is the number the sweep applied',
      );
      expect(
        find.text(l10n.forYouEmptyNothingHere),
        findsNothing,
        reason: 'somebody who just cleared five rows was not told they never '
            'had any',
      );
    },
  );

  testWidgets(
    'gate on: a partial sweep reads as cleared but never celebrates',
    (tester) async {
      final repo = _ChromeAttentionRepo(
        sweepEligible: true,
        dismissAllResult: const AttentionDismissAllResult(
          operationId: 'placeholder',
          status: AttentionOperationStatus.partial,
          appliedCount: 5,
          pendingCount: 4,
        ),
      );
      await _pumpInbox(tester, attentionRepo: repo, router: _HarnessRouter());

      await _tapDismissAll(tester);

      final l10n = L10nEn();
      // The positive first: a screen that rendered nothing satisfies every
      // absence below on its own.
      expect(find.byType(ForYouEmptyState), findsOneWidget);
      expect(find.byKey(ForYouEmptyState.titleKey), findsOneWidget);
      expect(find.text(l10n.forYouEmptyNothingNew), findsOneWidget);
      expect(find.byKey(CaughtUpPanel.illustrationKey), findsNothing);
      expect(find.byKey(CaughtUpPanel.clearedKey), findsNothing);
    },
  );

  testWidgets('gate on: overflow includes notification history entry', (
    tester,
  ) async {
    final router = _HarnessRouter();
    await _pumpInbox(
      tester,
      attentionRepo: _ChromeAttentionRepo(),
      router: router,
    );

    final l10n = L10nEn();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(l10n.notificationHistoryTitle), findsOneWidget);

    await tester.tap(find.text(l10n.notificationHistoryTitle));
    await tester.pumpAndSettle();
    expect(router.lastPush, isA<UpdatesRoute>());
  });

}
