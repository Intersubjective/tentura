import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/activity_forward_row.dart';
import 'package:tentura/features/inbox/ui/widget/activity_offer_card.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'activity_offers_test_support.dart';
import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;
import '../../support/noop_attention_actor_profiles.dart';

class _HarnessRouter extends Mock implements StackRouter {}

class _MockRootRouter extends Mock implements RootRouter {}

class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _ControllableForwardRepo implements ForwardRepository {
  final _helpOfferChanges = StreamController<HelpOfferEvent>.broadcast();
  final _forwardChanges = StreamController<String>.broadcast();
  final _forwardCommandCompleted = StreamController<String>.broadcast();

  @override
  Stream<HelpOfferEvent> get helpOfferChanges => _helpOfferChanges.stream;

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Stream<String> get forwardCommandCompleted => _forwardCommandCompleted.stream;

  void emitDeskChange(String beaconId) => _forwardChanges.add(beaconId);

  @override
  Future<void> dispose() async {
    await _helpOfferChanges.close();
    await _forwardChanges.close();
    await _forwardCommandCompleted.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MotionFeedRepo extends ConfigurableActivityOffersAttentionRepo {
  _MotionFeedRepo({this.streamHead = const []});

  List<AttentionReceipt> streamHead;
  String? forwardBeaconId;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async {
    if (cursor == null || cursor.isEmpty) {
      final items = <AttentionReceipt>[
        ...streamHead,
        if (forwardBeaconId != null) _forwardReceipt(forwardBeaconId!),
      ];
      return AttentionFeed(
        summary: const AttentionSummary(),
        page: AttentionFeedPage(items: items),
      );
    }
    return const AttentionFeed(
      summary: AttentionSummary(),
      page: AttentionFeedPage(),
    );
  }

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

AttentionReceipt _forwardReceipt(String beaconId) => AttentionReceipt(
  id: 'inbox:$beaconId',
  category: 'requestProgress',
  kind: 'relayReceived',
  priority: 'normal',
  title: 'Garden cleanup',
  body: 'Anna',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9, 10, 12),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  itemKind: AttentionItemKind.forward,
  forwardOutcome: AttentionForwardOutcome.watching,
  beaconId: beaconId,
);

AttentionReceipt _streamReceipt(String id) => AttentionReceipt(
  id: id,
  category: 'requestProgress',
  kind: 'relayReceived',
  priority: 'normal',
  title: 'Title $id',
  body: 'Body',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9, 10, 12),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  itemKind: AttentionItemKind.receipt,
);

InboxItem _offerItem(String beaconId) {
  final at = DateTime.utc(2026, 6, 20);
  return InboxItem(
    beaconId: beaconId,
    latestForwardAt: at,
    status: InboxItemStatus.needsMe,
    beacon: Beacon(
      id: beaconId,
      title: 'Offer $beaconId',
      author: const Profile(id: 'a', displayName: 'Anna'),
      createdAt: at,
      updatedAt: at,
    ),
  );
}

class _TestInboxCubit extends Cubit<InboxState> implements InboxCubit {
  _TestInboxCubit(
    super.initial, {
    this.inboxRepo,
    this.forwardRepo,
    this.feedRepo,
  });

  final FakeInboxRepository? inboxRepo;
  final _ControllableForwardRepo? forwardRepo;
  final _MotionFeedRepo? feedRepo;

  @override
  void clearPendingMovedNudge() {}

  @override
  Future<bool> fetch({bool showLoading = true, bool showError = true}) async =>
      true;

  @override
  Future<void> setWatching(String beaconId) async {
    inboxRepo?.openForwardByBeacon[beaconId] = null;
    feedRepo?.forwardBeaconId = beaconId;
    forwardRepo?.emitDeskChange(beaconId);
  }

  @override
  Future<void> stopWatching(String beaconId) async {}

  @override
  Future<void> reject(String beaconId, {String message = ''}) async {}

  @override
  Future<void> unreject(String beaconId) async {}

  @override
  Future<void> dismissTombstone(String beaconId) async {}
}

class _Boot {
  _Boot({
    required this.offers,
    required this.stream,
    required this.inboxRepo,
    required this.forwardRepo,
    required this.feedRepo,
    required this.attention,
    required this.accounts,
  });

  final ActivityOffersCubit offers;
  final UpdatesFeedCubit stream;
  final FakeInboxRepository inboxRepo;
  final _ControllableForwardRepo forwardRepo;
  final _MotionFeedRepo feedRepo;
  final AttentionCase attention;
  final _Accounts accounts;

  Future<void> dispose() async {
    await offers.close();
    await stream.close();
    await forwardRepo.dispose();
    await attention.dispose();
    await accounts.close();
  }
}

Future<_Boot> _boot({
  required FakeInboxRepository inboxRepo,
  required _MotionFeedRepo feedRepo,
  required _ControllableForwardRepo forwardRepo,
}) async {
  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    feedRepo,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('activity-live-motion-test'),
  );
  final inboxCase = buildTestInboxCase(
    inboxRepo,
    buildTestBeaconThreadsCase(),
    forwardRepository: forwardRepo,
  );
  accounts.emit('viewer');
  final offers = ActivityOffersCubit(
    userId: 'viewer',
    inboxCase: inboxCase,
    attentionCase: attention,
    pageSize: 20,
    actorProfiles: buildNoopAttentionActorProfiles(),
  );
  await offers.loadFirst();
  final stream = UpdatesFeedCubit(
    destinationId: AttentionFeedDestinationId.activityStream,
    attention: attention,
    setup: NoopInviteAcceptedSetupPort(),
    realtime: sync.case_,
    logger: Logger('activity-live-motion-test'),
    actorProfiles: buildNoopAttentionActorProfiles(),
  );
  return _Boot(
    offers: offers,
    stream: stream,
    inboxRepo: inboxRepo,
    forwardRepo: forwardRepo,
    feedRepo: feedRepo,
    attention: attention,
    accounts: accounts,
  );
}

Future<void> _pumpMotionView(
  WidgetTester tester, {
  required _Boot boot,
  _TestInboxCubit? inbox,
  Locale locale = const Locale('en'),
  bool disableAnimations = false,
  Size logicalSize = const Size(360, 640),
}) async {
  tester.view.physicalSize = logicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final inboxCubit =
      inbox ??
      _TestInboxCubit(
        const InboxState(status: StateIsSuccess(), projectionLoaded: true),
        inboxRepo: boot.inboxRepo,
        forwardRepo: boot.forwardRepo,
        feedRepo: boot.feedRepo,
      );

  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(boot.attention);
  ensureNoopAttentionActorProfilesRegistered();
  if (!GetIt.I.isRegistered<RootRouter>()) {
    GetIt.I.registerSingleton<RootRouter>(_MockRootRouter());
  }
  addTearDown(() {
    if (GetIt.I.isRegistered<AttentionCase>()) {
      GetIt.I.unregister<AttentionCase>();
    }
  });

  await tester.pumpWidget(
    StackRouterScope(
      controller: _HarnessRouter(),
      stateHash: 0,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ActivityOffersCubit>.value(value: boot.offers),
          BlocProvider<UpdatesFeedCubit>.value(value: boot.stream),
          BlocProvider<InboxCubit>.value(value: inboxCubit),
        ],
        child: MaterialApp(
          locale: locale,
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: logicalSize,
              disableAnimations: disableAnimations,
            ),
            child: const TenturaResponsiveScope(
              child: Scaffold(body: ActivityStreamView()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Rect _globalRect(Finder finder, WidgetTester tester) {
  expect(finder, findsOneWidget);
  return tester.getRect(finder);
}

Future<void> _pumpDeskDebounce(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('arrival at scroll offset 0 inserts offer with no pill', (
    tester,
  ) async {
    final forwardRepo = _ControllableForwardRepo();
    final inboxRepo = FakeInboxRepository();
    final feedRepo = _MotionFeedRepo();
    wireActivityOffersV2(
      inbox: inboxRepo,
      attention: feedRepo,
      items: [_offerItem('B1')],
    );
    final boot = await _boot(
      inboxRepo: inboxRepo,
      feedRepo: feedRepo,
      forwardRepo: forwardRepo,
    );
    addTearDown(boot.dispose);

    await _pumpMotionView(tester, boot: boot);

    final arrival = _offerItem('B-new');
    inboxRepo.openForwardByBeacon['B-new'] = arrival;
    forwardRepo.emitDeskChange('B-new');
    await _pumpDeskDebounce(tester);

    expect(boot.offers.state.items.first.beaconId, 'B-new');
    expect(
      find.bySemanticsIdentifier(TestIds.activityNewItemsPill),
      findsNothing,
    );
  });

  testWidgets(
    'arrival while scrolled away shows pill without shifting layout',
    (
      tester,
    ) async {
      final forwardRepo = _ControllableForwardRepo();
      final inboxRepo = FakeInboxRepository();
      final fillOffers = [
        _offerItem('B1'),
        for (var i = 0; i < 25; i++) _offerItem('fill-$i'),
      ];
      final feedRepo = _MotionFeedRepo(
        streamHead: [for (var i = 0; i < 30; i++) _streamReceipt('s$i')],
      );
      wireActivityOffersV2(
        inbox: inboxRepo,
        attention: feedRepo,
        items: fillOffers,
        totalCount: 26,
      );
      final boot = await _boot(
        inboxRepo: inboxRepo,
        feedRepo: feedRepo,
        forwardRepo: forwardRepo,
      );
      addTearDown(boot.dispose);

      await _pumpMotionView(tester, boot: boot);

      // The "for you" header scrolls out of view by construction of this test
      // (we drag past scrolledAwayThreshold), so it can't serve as the stable
      // reference widget — use an offer card that stays on screen instead.
      final reference = find.bySemanticsIdentifier(
        TestIds.activityOffer('fill-2'),
      );
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -ActivityStreamView.scrolledAwayThreshold - 40),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(boot.offers.state.heldBackIds, isEmpty);

      final before = _globalRect(reference, tester);

      final arrival = _offerItem('B-held');
      inboxRepo.openForwardByBeacon['B-held'] = arrival;
      forwardRepo.emitDeskChange('B-held');
      await _pumpDeskDebounce(tester, frames: 5);

      final after = _globalRect(reference, tester);
      expect(after, equals(before));
      expect(
        find.bySemanticsIdentifier(TestIds.activityNewItemsPill),
        findsOneWidget,
      );
      expect(boot.offers.state.heldBackIds, {'B-held'});
    },
  );

  testWidgets('watch demotion shows forward row with watching outcome (ru)', (
    tester,
  ) async {
    const beaconId = 'B-watch';
    final forwardRepo = _ControllableForwardRepo();
    final inboxRepo = FakeInboxRepository()
      ..openForwardByBeacon[beaconId] = _offerItem(beaconId);
    final feedRepo = _MotionFeedRepo();
    wireActivityOffersV2(
      inbox: inboxRepo,
      attention: feedRepo,
      items: [_offerItem(beaconId)],
    );
    final boot = await _boot(
      inboxRepo: inboxRepo,
      feedRepo: feedRepo,
      forwardRepo: forwardRepo,
    );
    addTearDown(boot.dispose);

    final inboxCubit = _TestInboxCubit(
      const InboxState(status: StateIsSuccess(), projectionLoaded: true),
      inboxRepo: inboxRepo,
      forwardRepo: forwardRepo,
      feedRepo: feedRepo,
    );

    await _pumpMotionView(
      tester,
      boot: boot,
      inbox: inboxCubit,
      locale: const Locale('ru'),
    );

    expect(find.byType(ActivityOfferCard), findsOneWidget);
    await tester.tap(find.text('Следить'));
    await _pumpDeskDebounce(tester, frames: 20);

    expect(find.byType(ActivityOfferCard), findsNothing);
    expect(find.byType(ActivityForwardRow), findsOneWidget);
    expect(find.text('Вы начали следить'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(TestIds.activityForwardRow(beaconId)),
      findsOneWidget,
    );
  });

  testWidgets('reduced motion completes demotion without animation frames', (
    tester,
  ) async {
    const beaconId = 'B-fast';
    final forwardRepo = _ControllableForwardRepo();
    final inboxRepo = FakeInboxRepository()
      ..openForwardByBeacon[beaconId] = _offerItem(beaconId);
    final feedRepo = _MotionFeedRepo();
    wireActivityOffersV2(
      inbox: inboxRepo,
      attention: feedRepo,
      items: [_offerItem(beaconId)],
    );
    final boot = await _boot(
      inboxRepo: inboxRepo,
      feedRepo: feedRepo,
      forwardRepo: forwardRepo,
    );
    addTearDown(boot.dispose);

    final inboxCubit = _TestInboxCubit(
      const InboxState(status: StateIsSuccess(), projectionLoaded: true),
      inboxRepo: inboxRepo,
      forwardRepo: forwardRepo,
      feedRepo: feedRepo,
    );

    await _pumpMotionView(
      tester,
      boot: boot,
      inbox: inboxCubit,
      disableAnimations: true,
    );

    await tester.tap(find.text('Follow'));
    await _pumpDeskDebounce(tester, frames: 10);

    expect(find.byType(ActivityOfferCard), findsNothing);
    expect(find.byType(ActivityForwardRow), findsOneWidget);
  });

  testWidgets('Показать on moved snackbar scrolls to demoted forward row', (
    tester,
  ) async {
    const beaconId = 'B-far';
    final forwardRepo = _ControllableForwardRepo();
    final inboxRepo = FakeInboxRepository()
      ..openForwardByBeacon[beaconId] = _offerItem(beaconId);
    final padOffers = [
      _offerItem(beaconId),
      for (var i = 0; i < 30; i++) _offerItem('pad-$i'),
    ];
    final feedRepo = _MotionFeedRepo(
      streamHead: [for (var i = 0; i < 40; i++) _streamReceipt('far-$i')],
    );
    wireActivityOffersV2(
      inbox: inboxRepo,
      attention: feedRepo,
      items: padOffers,
      totalCount: 31,
    );
    final boot = await _boot(
      inboxRepo: inboxRepo,
      feedRepo: feedRepo,
      forwardRepo: forwardRepo,
    );
    addTearDown(boot.dispose);

    final inboxCubit = _TestInboxCubit(
      const InboxState(status: StateIsSuccess(), projectionLoaded: true),
      inboxRepo: inboxRepo,
      forwardRepo: forwardRepo,
      feedRepo: feedRepo,
    );

    await _pumpMotionView(
      tester,
      boot: boot,
      inbox: inboxCubit,
      locale: const Locale('ru'),
      logicalSize: const Size(360, 400),
      // Instant scroll steps so «Показать» can reach off-screen lazy rows in tests.
      disableAnimations: true,
    );

    // Watch while B-far is still at the top of the pinned zone (offset 0).
    // The demoted forward row lands deep in the combined list (30 pads + stream),
    // outside this short viewport — snackbar path, not in-place reveal.
    // Multiple offer cards are loaded (31), each with its own "Watch" text —
    // scope the tap to the one card we care about rather than matching all.
    await tester.tap(
      find.descendant(
        of: find.bySemanticsIdentifier(TestIds.activityOffer(beaconId)),
        matching: find.text('Следить'),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(SnackBar).evaluate().isNotEmpty) break;
    }
    expect(
      boot.stream.state.items.any((r) => r.beaconId == beaconId),
      isTrue,
      reason: 'stream refresh should include demoted forward receipt',
    );

    // showSnackBar renders the message in RichText/TextSpan, not a Text widget.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('Перемещено в ленту'),
      ),
      findsOneWidget,
    );
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.action, isNotNull);
    final scrollable = find.byType(Scrollable).first;
    final beforeScroll = tester
        .state<ScrollableState>(scrollable)
        .position
        .pixels;
    // Snack bar lays out below the 400px test surface; fire the action directly.
    snackBar.action!.onPressed();
    final forwardRow = find.bySemanticsIdentifier(
      TestIds.activityForwardRow(beaconId),
    );
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (forwardRow.evaluate().isNotEmpty) break;
    }
    final afterScroll = tester
        .state<ScrollableState>(scrollable)
        .position
        .pixels;
    expect(afterScroll, greaterThan(beforeScroll));
    if (forwardRow.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        forwardRow,
        300,
        scrollable: scrollable,
      );
    }

    expect(forwardRow, findsOneWidget);
    final rowRect = tester.getRect(
      find.bySemanticsIdentifier(TestIds.activityForwardRow(beaconId)),
    );
    expect(rowRect.top, greaterThanOrEqualTo(0));
    expect(rowRect.bottom, lessThanOrEqualTo(400));
  });
}
