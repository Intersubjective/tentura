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
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/home/domain/work_activity_redesign_gate.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/inbox_screen.dart';
import 'package:tentura/features/inbox/ui/widget/activity_forward_row.dart';
import 'package:tentura/features/inbox/ui/widget/activity_offer_card.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/inbox/ui/widget/activity_watching_digest_row.dart';
import 'package:tentura/features/inbox/ui/widget/inbox_triage_row.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'inbox_case_test.dart'
    show
        FakeInboxRepository,
        buildTestBeaconThreadsCase,
        buildTestInboxCase;

class _HarnessRouter extends Mock implements StackRouter {}

class _MockRootRouter extends Mock implements RootRouter {}

class _TestInboxCubit extends Cubit<InboxState> implements InboxCubit {
  _TestInboxCubit(super.initial);

  @override
  void setSort(InboxSort sort) {}

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

final class _PromptSetup implements InviteAcceptedSetupPort {
  @override
  Future<Map<String, InviteSeedPromptState>> fetchPrompts(
    Set<String> subjectIds,
  ) async => {
    for (final id in subjectIds)
      id: InviteSeedPromptState(
        inviterUserId: 'inv',
        inviteeUserId: id,
        state: PromptStateValue.pending,
      ),
  };

  @override
  Future<Profile> fetchProfile(String subjectId) async =>
      Profile(id: subjectId, displayName: 'Invitee');

  @override
  Future<InviteSeedPromptState> fetchPrompt(String subjectId) async =>
      InviteSeedPromptState(
        inviterUserId: 'inv',
        inviteeUserId: subjectId,
        state: PromptStateValue.pending,
      );

  @override
  Future<void> answer({
    required String subjectId,
    required List<String> slugs,
  }) async {}

  @override
  Future<void> rename({
    required String subjectId,
    required String privateName,
  }) async {}

  @override
  Future<void> skip(String subjectId) async {}
}

class _FeedAttentionRepo extends AttentionRepositoryFake {
  _FeedAttentionRepo({
    required this.firstPage,
    this.nextCursor,
    this.secondPage = const [],
  });

  final List<AttentionReceipt> firstPage;
  final String? nextCursor;
  final List<AttentionReceipt> secondPage;
  int fetchCalls = 0;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async {
    fetchCalls++;
    if (cursor == null || cursor.isEmpty) {
      return AttentionFeed(
        summary: const AttentionSummary(),
        page: AttentionFeedPage(items: firstPage, nextCursor: nextCursor),
      );
    }
    return AttentionFeed(
      summary: const AttentionSummary(),
      page: AttentionFeedPage(items: secondPage),
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

AttentionReceipt _streamReceipt({
  required String id,
  AttentionItemKind itemKind = AttentionItemKind.receipt,
  AttentionForwardOutcome? forwardOutcome,
  int? digestCount,
}) =>
    AttentionReceipt(
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
      itemKind: itemKind,
      forwardOutcome: forwardOutcome,
      digestCount: digestCount,
      beaconId: 'beacon-$id',
    );

AttentionReceipt _promptReceipt() => AttentionReceipt(
  id: 'prompt-1',
  category: 'social',
  kind: 'inviteAccepted',
  priority: 'normal',
  title: 'Invite',
  body: 'Body',
  actionUrl: '/#/',
  createdAt: DateTime.now().subtract(const Duration(days: 1)),
  collapsedCount: 1,
  presentationPayloadJson: '{"inviteOrigin":"new_account"}',
  surface: AttentionSurface.activity,
  presentationKey: 'invite_accepted',
  actorUserId: 'invitee-prompt-1',
  targetEntityId: 'invitee-prompt-1',
);

Future<void> _pumpFrames(WidgetTester tester, {int frames = 5}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Boot {
  _Boot({
    required this.offers,
    required this.stream,
    required this.inboxRepo,
    required this.attentionRepo,
    required this.attention,
    required this.accounts,
  });

  final ActivityOffersCubit offers;
  final UpdatesFeedCubit stream;
  final FakeInboxRepository inboxRepo;
  final _FeedAttentionRepo attentionRepo;
  final AttentionCase attention;
  final _Accounts accounts;

  Future<void> dispose() async {
    await offers.close();
    await stream.close();
    await attention.dispose();
    await accounts.close();
  }
}

Future<_Boot> _boot({
  required FakeInboxRepository inboxRepo,
  required _FeedAttentionRepo attentionRepo,
  InviteAcceptedSetupPort? setup,
}) async {
  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    attentionRepo,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('activity-stream-test'),
  );
  final inboxCase = buildTestInboxCase(
    inboxRepo,
    buildTestBeaconThreadsCase(),
    forwardRepository: _ForwardRepo(),
  );
  accounts.emit('viewer');
  final offers = ActivityOffersCubit(
    userId: 'viewer',
    inboxCase: inboxCase,
    attentionCase: attention,
    pageSize: 20,
  );
  await offers.loadFirst();
  final stream = UpdatesFeedCubit(
    destinationId: AttentionFeedDestinationId.activityStream,
    attention: attention,
    setup: setup ?? NoopInviteAcceptedSetupPort(),
    realtime: sync.case_,
    logger: Logger('activity-stream-test'),
  );
  await attention.refresh(
    destinationId: AttentionFeedDestinationId.activityStream,
  );
  return _Boot(
    offers: offers,
    stream: stream,
    inboxRepo: inboxRepo,
    attentionRepo: attentionRepo,
    attention: attention,
    accounts: accounts,
  );
}

Future<void> _pumpStreamView(
  WidgetTester tester, {
  required _Boot boot,
  _TestInboxCubit? inbox,
  Size logicalSize = const Size(360, 640),
  double textScale = 1,
}) async {
  tester.view.physicalSize = logicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final inboxCubit = inbox ??
      _TestInboxCubit(
        const InboxState(status: StateIsSuccess(), projectionLoaded: true),
      );

  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(boot.attention);
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
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: logicalSize,
              textScaler: TextScaler.linear(textScale),
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
  await _pumpFrames(tester, frames: 8);
}

double _top(Finder finder, WidgetTester tester) {
  expect(finder, findsOneWidget);
  return tester.getRect(finder).top;
}

void _registerRedesignGate(bool enabled) {
  if (GetIt.I.isRegistered<bool>(instanceName: workActivityRedesignGate)) {
    GetIt.I.unregister<bool>(instanceName: workActivityRedesignGate);
  }
  GetIt.I.registerSingleton<bool>(
    enabled,
    instanceName: workActivityRedesignGate,
  );
}

void main() {
  tearDown(() {
    if (GetIt.I.isRegistered<bool>(instanceName: workActivityRedesignGate)) {
      GetIt.I.unregister<bool>(instanceName: workActivityRedesignGate);
    }
  });

  testWidgets('render order: header, prompt, offer, then stream', (tester) async {
    final inboxRepo = FakeInboxRepository()
      ..activityOffersPages = [_offerItem('offer-1')]
      ..openForwardsCount = 1;
    final attentionRepo = _FeedAttentionRepo(
      firstPage: [_promptReceipt(), _streamReceipt(id: 'stream-1')],
    );
    final boot = await _boot(
      inboxRepo: inboxRepo,
      attentionRepo: attentionRepo,
      setup: _PromptSetup(),
    );
    addTearDown(boot.dispose);
    boot.stream.applyKnownPrompt(
      'invitee-prompt-1',
      InviteSeedPromptState(
        inviterUserId: 'inv',
        inviteeUserId: 'invitee-prompt-1',
        state: PromptStateValue.pending,
      ),
    );

    await _pumpStreamView(tester, boot: boot);

    final headerTop = _top(
      find.bySemanticsIdentifier(TestIds.activityForYouHeader),
      tester,
    );
    final promptTop = _top(
      find.byKey(TestIds.key(TestIds.activityPromptPin('prompt-1'))),
      tester,
    );
    final offerTop = _top(find.byKey(const ValueKey('offer-offer-1')), tester);
    final streamTop = _top(find.byKey(const ValueKey('stream-1')), tester);

    expect(headerTop, lessThan(promptTop));
    expect(promptTop, lessThan(offerTop));
    expect(offerTop, lessThan(streamTop));
  });

  testWidgets('stream pagination waits until offers hasMore is false', (
    tester,
  ) async {
    final firstPageOffers = [
      for (var i = 0; i < 20; i++) _offerItem('p$i'),
    ];
    final inboxRepo = FakeInboxRepository()
      ..activityOffersPages = firstPageOffers
      ..openForwardsCount = 25;
    final attentionRepo = _FeedAttentionRepo(
      firstPage: const [],
      nextCursor: 'more',
    );
    final boot = await _boot(inboxRepo: inboxRepo, attentionRepo: attentionRepo);
    addTearDown(boot.dispose);

    await _pumpStreamView(
      tester,
      boot: boot,
      logicalSize: const Size(360, 400),
    );
    expect(boot.offers.state.hasMore, isTrue);

    final scrollable = find.byType(CustomScrollView);
    await tester.fling(scrollable, const Offset(0, -800), 8000);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(boot.inboxRepo.activityOffersPageCalls, greaterThanOrEqualTo(2));
    expect(boot.attentionRepo.fetchCalls, greaterThanOrEqualTo(1));

    inboxRepo.activityOffersPages = const [];

    await tester.fling(scrollable, const Offset(0, -800), 8000);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(boot.attentionRepo.fetchCalls, greaterThan(1));
  });

  testWidgets('itemKind dispatch renders correct row widgets', (tester) async {
    final inboxRepo = FakeInboxRepository()
      ..activityOffersPages = const []
      ..openForwardsCount = 0;
    final attentionRepo = _FeedAttentionRepo(
      firstPage: [
        _streamReceipt(id: 'r1'),
        _streamReceipt(
          id: 'f1',
          itemKind: AttentionItemKind.forward,
          forwardOutcome: AttentionForwardOutcome.helping,
        ),
        _streamReceipt(
          id: 'd1',
          itemKind: AttentionItemKind.watchingDigest,
          digestCount: 3,
        ),
      ],
    );
    final boot = await _boot(inboxRepo: inboxRepo, attentionRepo: attentionRepo);
    addTearDown(boot.dispose);

    await _pumpStreamView(tester, boot: boot);

    expect(find.byType(UpdatesFeedTile), findsOneWidget);
    expect(find.byType(ActivityForwardRow), findsOneWidget);
    expect(find.byType(ActivityWatchingDigestRow), findsOneWidget);
  });

  testWidgets('360x640 at 1.3x: first offer card fully visible', (tester) async {
    final inboxRepo = FakeInboxRepository()
      ..activityOffersPages = [_offerItem('first')]
      ..openForwardsCount = 1;
    final boot = await _boot(
      inboxRepo: inboxRepo,
      attentionRepo: _FeedAttentionRepo(
        firstPage: [_streamReceipt(id: 'below')],
      ),
    );
    addTearDown(boot.dispose);

    await _pumpStreamView(
      tester,
      boot: boot,
      logicalSize: const Size(360, 640),
      textScale: 1.3,
    );

    final cardFinder = find.byType(ActivityOfferCard);
    expect(cardFinder, findsOneWidget);
    final rect = tester.getRect(cardFinder);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(640));
  });

  testWidgets('60 offers and 120 stream items scroll without duplicate keys',
      (tester) async {
    final inboxRepo = FakeInboxRepository()
      ..activityOffersPages = [for (var i = 0; i < 60; i++) _offerItem('b$i')]
      ..openForwardsCount = 60;
    final attentionRepo = _FeedAttentionRepo(
      firstPage: [for (var i = 0; i < 120; i++) _streamReceipt(id: 's$i')],
    );
    final boot = await _boot(inboxRepo: inboxRepo, attentionRepo: attentionRepo);
    addTearDown(boot.dispose);

    await _pumpStreamView(
      tester,
      boot: boot,
      logicalSize: const Size(360, 640),
    );

    final scrollable = find.byType(CustomScrollView);
    final seenOffers = <String>{};
    final seenStream = <String>{};

    void collectVisibleKeys() {
      final passOffers = <String>{};
      final passStream = <String>{};
      for (var i = 0; i < 60; i++) {
        final key = 'offer-b$i';
        if (find.byKey(ValueKey(key)).evaluate().isEmpty) continue;
        expect(passOffers.contains(key), isFalse, reason: 'duplicate $key');
        passOffers.add(key);
        seenOffers.add(key);
      }
      for (var i = 0; i < 120; i++) {
        final key = 's$i';
        if (find.byKey(ValueKey(key)).evaluate().isEmpty) continue;
        expect(passStream.contains(key), isFalse, reason: 'duplicate $key');
        passStream.add(key);
        seenStream.add(key);
      }
    }

    for (var pass = 0; pass < 80; pass++) {
      collectVisibleKeys();
      await tester.drag(scrollable, const Offset(0, -350));
      await tester.pump(const Duration(milliseconds: 16));
    }
    collectVisibleKeys();

    expect(seenOffers.length, 60);
    expect(seenStream.length, 120);
  });

  testWidgets('gate off keeps legacy triage row and UpdatesFeedPane', (
    tester,
  ) async {
    _registerRedesignGate(false);

    final inboxCubit = _TestInboxCubit(
      InboxState(
        items: [_offerItem('legacy')],
        status: const StateIsSuccess(),
        projectionLoaded: true,
      ),
    );

    final accounts = _Accounts();
    accounts.emit('viewer');
    final sync = buildTestRealtimeSync();
    final attentionCase = AttentionCase(
      _EmptyFeedRepo(),
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('gate-off'),
    );
    GetIt.I.registerSingleton<AttentionCase>(attentionCase);
    GetIt.I.registerSingleton<InviteAcceptedSetupPort>(
      NoopInviteAcceptedSetupPort(),
    );
    GetIt.I.registerSingleton<RealtimeSyncCase>(sync.case_);
    final logger = Logger('gate-off-test');
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(logger);
    }
    addTearDown(() {
      if (GetIt.I.isRegistered<AttentionCase>()) {
        GetIt.I.unregister<AttentionCase>();
      }
      if (GetIt.I.isRegistered<InviteAcceptedSetupPort>()) {
        GetIt.I.unregister<InviteAcceptedSetupPort>();
      }
      if (GetIt.I.isRegistered<RealtimeSyncCase>()) {
        GetIt.I.unregister<RealtimeSyncCase>();
      }
    });

    final homeAttention = HomeAttentionCubit(
      attentionCase,
      accounts,
      Logger('gate-off'),
    );

    await tester.pumpWidget(
      StackRouterScope(
        controller: _HarnessRouter(),
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
            home: const MediaQuery(
              data: MediaQueryData(size: Size(800, 800)),
              child: TenturaResponsiveScope(child: InboxScreen()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(InboxTriageRow), findsOneWidget);
    expect(find.byType(UpdatesFeedPane), findsOneWidget);
    expect(find.byType(ActivityStreamView), findsNothing);

    unawaited(homeAttention.close());
    unawaited(attentionCase.dispose());
    unawaited(accounts.close());
  });
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

class _EmptyFeedRepo extends AttentionRepositoryFake {
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
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}
