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
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/inbox_screen.dart';
import 'package:tentura/features/inbox/ui/widget/activity_event_subcard_block.dart';
import 'package:tentura/features/inbox/ui/widget/activity_forward_row.dart';
import 'package:tentura/features/inbox/ui/widget/activity_offer_card.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/inbox/ui/widget/activity_watching_digest_row.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/features/inbox/ui/widget/tombstone_row.dart';
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
import 'activity_offers_test_support.dart';
import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;
import '../../support/noop_attention_actor_profiles.dart';

class _HarnessRouter extends Mock implements StackRouter {}

class _MockRootRouter extends Mock implements RootRouter {}

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

  final dismissedTombstones = <String>[];

  @override
  Future<void> dismissTombstone(String beaconId) async =>
      dismissedTombstones.add(beaconId);
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

class _FeedAttentionRepo extends ConfigurableActivityOffersAttentionRepo {
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

InboxItem _offerItem(String beaconId, {String? provenanceJson}) {
  final at = DateTime.utc(2026, 6, 20);
  return InboxItem(
    beaconId: beaconId,
    latestForwardAt: at,
    status: InboxItemStatus.needsMe,
    provenance: InboxProvenance.parse(provenanceJson),
    beacon: Beacon(
      id: beaconId,
      title: 'Offer $beaconId',
      author: const Profile(id: 'a', displayName: 'Anna'),
      createdAt: at,
      updatedAt: at,
    ),
  );
}

/// The forward note, the forwarder and the Request's author — without these
/// the card's §12.1 / A7 note assertions are vacuous, because the card has
/// nothing to draw a mini-card from.
String _provenanceJson({
  String senderId = 'sender-1',
  String senderName = 'Bai Yue',
  String note = 'You used to tinker with these, take a look',
}) =>
    '{"senders":[{"id":"$senderId","displayName":"$senderName",'
    '"notePreview":"$note","reasonSlugs":["repair"],"mr":0.4}],'
    '"totalDistinctSenders":1,"strongestNotePreview":"$note",'
    '"latestNoteForward":{"forwardId":"fw-$senderId","senderId":"$senderId",'
    '"displayName":"$senderName","notePreview":"$note",'
    '"forwardedAt":"2026-09-10T09:00:00Z","reasonSlugs":["repair"]}}';

AttentionReceipt _streamReceipt({
  required String id,
  AttentionItemKind itemKind = AttentionItemKind.receipt,
  AttentionForwardOutcome? forwardOutcome,
  int? digestCount,
  int? eventTotal,
  int? eventUnseenCount,
  List<AttentionReceipt> eventsPreview = const [],
  String? beaconId,
  String? provenanceJson,
  String beaconAuthorName = 'Anna',
}) => AttentionReceipt(
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
  eventTotal: eventTotal,
  eventUnseenCount: eventUnseenCount ?? (eventTotal == null ? null : 1),
  eventsPreview: eventsPreview,
  beaconId: beaconId ?? 'beacon-$id',
  provenanceJson: provenanceJson,
  beaconAuthorId: 'author-$id',
  beaconAuthorName: beaconAuthorName,
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
    actorProfiles: buildNoopAttentionActorProfiles(),
  );
  await offers.loadFirst();
  final stream = UpdatesFeedCubit(
    destinationId: AttentionFeedDestinationId.activityStream,
    attention: attention,
    setup: setup ?? NoopInviteAcceptedSetupPort(),
    realtime: sync.case_,
    logger: Logger('activity-stream-test'),
    actorProfiles: buildNoopAttentionActorProfiles(),
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

  final inboxCubit =
      inbox ??
      _TestInboxCubit(
        const InboxState(status: StateIsSuccess(), projectionLoaded: true),
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

void main() {
  testWidgets('render order: header, prompt, offer, then stream', (
    tester,
  ) async {
    final inboxRepo = FakeInboxRepository();
    final attentionRepo = _FeedAttentionRepo(
      firstPage: [
        _promptReceipt(),
        _streamReceipt(id: 'stream-1'),
      ],
    );
    wireActivityOffersV2(
      inbox: inboxRepo,
      attention: attentionRepo,
      items: [_offerItem('offer-1')],
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
    final inboxRepo = FakeInboxRepository();
    final attentionRepo = _FeedAttentionRepo(
      firstPage: const [],
      nextCursor: 'more',
    );
    wireActivityOffersV2(
      inbox: inboxRepo,
      attention: attentionRepo,
      items: firstPageOffers,
      nextCursor: 'more',
      totalCount: 25,
    );
    attentionRepo.secondOfferRows = [
      for (var i = 20; i < 25; i++) activityOfferSortRow(_offerItem('p$i')),
    ];
    final boot = await _boot(
      inboxRepo: inboxRepo,
      attentionRepo: attentionRepo,
    );
    addTearDown(boot.dispose);

    await _pumpStreamView(
      tester,
      boot: boot,
      logicalSize: const Size(360, 400),
    );
    expect(boot.offers.state.hasMore, isTrue);

    final scrollable = find.byType(CustomScrollView);
    // CHANGES IN U16b: spec §5 "Retire" — the pinned zone is now a card
    // (§6 anatomy), which is several times the height of the row the old
    // `ActivityOfferBoundedShell` drew. Twenty of them no longer fit inside
    // one fling of a 400 dp viewport, so reaching the end takes a bounded
    // series. The assertions themselves are unchanged: what is under test is
    // the *order* the two sources page in, not how far one gesture travels.
    Future<void> scrollToEnd() async {
      for (var i = 0; i < 40; i++) {
        await tester.fling(scrollable, const Offset(0, -800), 8000);
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        if (position.pixels >= position.maxScrollExtent) return;
      }
    }

    await scrollToEnd();

    expect(boot.attentionRepo.activityOffersCalls, greaterThanOrEqualTo(2));
    expect(boot.attentionRepo.fetchCalls, greaterThanOrEqualTo(1));

    attentionRepo.offerRows = const [];
    attentionRepo.offersNextCursor = null;

    await scrollToEnd();

    expect(boot.attentionRepo.fetchCalls, greaterThan(1));
  });

  testWidgets('itemKind dispatch renders correct row widgets', (tester) async {
    final inboxRepo = FakeInboxRepository();
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
        _streamReceipt(
          id: 'ra1',
          itemKind: AttentionItemKind.requestActivity,
          eventTotal: 1,
          eventsPreview: [
            _streamReceipt(id: 'ra1-child'),
          ],
        ),
      ],
    );
    wireActivityOffersV2(
      inbox: inboxRepo,
      attention: attentionRepo,
      items: const [],
      totalCount: 0,
    );
    final boot = await _boot(
      inboxRepo: inboxRepo,
      attentionRepo: attentionRepo,
    );
    addTearDown(boot.dispose);

    await _pumpStreamView(tester, boot: boot);

    // CHANGES IN U16b: spec §5 "Retire" — `ActivityForwardRow` is replaced by
    // `TombstoneRow` (§8) and the `requestActivity` tile-plus-sibling-block
    // pair by one `RequestAttentionCard` (§6). The four beacons here are
    // distinct, so nothing is folded: what changed is what each row is drawn
    // as, not how many there are.
    expect(find.byType(UpdatesFeedTile), findsOneWidget);
    expect(find.byType(ActivityForwardRow), findsNothing);
    expect(find.byType(TombstoneRow), findsOneWidget);
    expect(find.byType(RequestAttentionCard), findsOneWidget);
    // CHANGES IN U16b: correction 1, option (a) — the digest keeps its
    // `isInUnreadView` membership and its home in the overflow menu's
    // Watching collection; the primary stream does not draw it. Pinned in
    // `for_you_stream_entries_test.dart`, both halves together.
    expect(find.byType(ActivityWatchingDigestRow), findsNothing);
    // CHANGES IN U16b: D-171-5b / spec §6.2 — the event block now lives
    // *inside* the card under `timeline`, never beside a tile under
    // `paginate`. One block, and it is the card's.
    expect(find.byType(ActivityEventSubcardBlock), findsOneWidget);
    expect(
      tester
          .widget<ActivityEventSubcardBlock>(
            find.byType(ActivityEventSubcardBlock),
          )
          .overflowPolicy,
      AttentionBlockOverflowPolicy.timeline,
    );
  });

  testWidgets('360x640 at 1.3x: first offer card fully visible', (
    tester,
  ) async {
    final inboxRepo = FakeInboxRepository();
    final attentionRepo = _FeedAttentionRepo(
      firstPage: [_streamReceipt(id: 'below')],
    );
    final offer = _offerItem('first', provenanceJson: _provenanceJson());
    wireActivityOffersV2(
      inbox: inboxRepo,
      attention: attentionRepo,
      items: [offer],
      totalCount: 1,
    );
    attentionRepo.offerRows = [
      activityOfferSortRow(
        offer,
        eventTotal: 1,
        eventsPreview: [
          _streamReceipt(id: 'offer-event-1'),
        ],
      ),
    ];
    final boot = await _boot(
      inboxRepo: inboxRepo,
      attentionRepo: attentionRepo,
    );
    addTearDown(boot.dispose);

    await _pumpStreamView(
      tester,
      boot: boot,
      logicalSize: const Size(360, 640),
      textScale: 1.3,
    );

    // CHANGES IN U16b: spec §5 "Retire" — the pinned zone is the card's
    // `pinned` variant (§9), not `ActivityOfferCard`.
    final cardFinder = find.byType(RequestAttentionCard);
    expect(cardFinder, findsOneWidget);
    expect(find.byType(ActivityOfferCard), findsNothing);
    // The positive assertion first: a fixture that renders nothing satisfies
    // any "fits on screen" claim. This card must be *built* and must carry
    // the forward note, which is the whole regression #171 is about.
    expect(find.byKey(RequestAttentionCard.headerKey), findsOneWidget);
    expect(find.byType(AttentionMiniCard), findsOneWidget);
    expect(
      find.text('You used to tinker with these, take a look'),
      findsOneWidget,
    );
    final rect = tester.getRect(cardFinder);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(640));
  });

  // Core acceptance, not an optional step: a Request showing an offer card
  // *and* a grouped card *and* a forward row is the failure the unified card
  // exists to end. The server rules out three of the four collisions and not
  // this one — see `for_you_stream_entries.dart` for the clause behind each.
  testWidgets('one representative per Request across the whole surface', (
    tester,
  ) async {
    final inboxRepo = FakeInboxRepository();
    final attentionRepo = _FeedAttentionRepo(
      firstPage: [
        // A watching Request: `eligible_forward` emits the outcome row and
        // nothing on the `requestActivity` branch excludes it.
        _streamReceipt(
          id: 'dup-forward',
          beaconId: 'beacon-dup',
          itemKind: AttentionItemKind.forward,
          forwardOutcome: AttentionForwardOutcome.watching,
        ),
        _streamReceipt(
          id: 'dup-activity',
          beaconId: 'beacon-dup',
          itemKind: AttentionItemKind.requestActivity,
          eventTotal: 2,
          provenanceJson: _provenanceJson(),
          eventsPreview: [_streamReceipt(id: 'dup-child')],
        ),
        // And the same Request pinned, which is the third surface.
        _streamReceipt(
          id: 'pinned-activity',
          beaconId: 'offer-pinned',
          itemKind: AttentionItemKind.requestActivity,
          eventTotal: 1,
        ),
      ],
    );
    wireActivityOffersV2(
      inbox: inboxRepo,
      attention: attentionRepo,
      items: [_offerItem('offer-pinned', provenanceJson: _provenanceJson())],
      totalCount: 1,
    );
    final boot = await _boot(
      inboxRepo: inboxRepo,
      attentionRepo: attentionRepo,
    );
    addTearDown(boot.dispose);

    await _pumpStreamView(
      tester,
      boot: boot,
      logicalSize: const Size(360, 2400),
    );

    // Positive first: both Requests are on screen, as exactly one surface each.
    expect(find.byType(RequestAttentionCard), findsNWidgets(2));
    expect(find.byType(TombstoneRow), findsNothing);
    expect(find.byType(ActivityOfferCard), findsNothing);
    expect(find.textContaining('Title dup-activity'), findsOneWidget);
    expect(find.textContaining('Offer offer-pinned'), findsOneWidget);
  });

  // Owner decision B: answered-forward outcomes stay in For You as
  // dismissible tombstones. m0183 made every outcome kind dismissible, so
  // every kind wears the ×. One assertion per kind — a × wired for the kind
  // that happened to be tested is the defect shape this plan keeps hitting.
  for (final outcome in const [
    (value: AttentionForwardOutcome.helping, name: 'helping'),
    (value: AttentionForwardOutcome.watching, name: 'watching'),
    (value: AttentionForwardOutcome.notInterested, name: 'notInterested'),
    (value: AttentionForwardOutcome.closedBeforeResponse, name: 'closed'),
    (value: AttentionForwardOutcome.deletedBeforeResponse, name: 'deleted'),
  ]) {
    testWidgets('the ${outcome.name} tombstone has a × and it acts', (
      tester,
    ) async {
      final inboxRepo = FakeInboxRepository();
      final attentionRepo = _FeedAttentionRepo(
        firstPage: [
          _streamReceipt(
            id: 'tomb',
            itemKind: AttentionItemKind.forward,
            forwardOutcome: outcome.value,
            provenanceJson: _provenanceJson(),
          ),
        ],
      );
      wireActivityOffersV2(
        inbox: inboxRepo,
        attention: attentionRepo,
        items: const [],
        totalCount: 0,
      );
      final boot = await _boot(
        inboxRepo: inboxRepo,
        attentionRepo: attentionRepo,
      );
      addTearDown(boot.dispose);
      final inbox = _TestInboxCubit(
        const InboxState(status: StateIsSuccess(), projectionLoaded: true),
      );

      await _pumpStreamView(tester, boot: boot, inbox: inbox);

      expect(find.byType(TombstoneRow), findsOneWidget);
      expect(find.byKey(TombstoneRow.dismissKey), findsOneWidget);
      // The demotion scroll addresses the row by this identifier; a wrapper
      // that dropped it would strand `_isForwardRowInViewport` forever.
      expect(
        find.bySemanticsIdentifier(TestIds.activityForwardRow('beacon-tomb')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(TombstoneRow.dismissKey));
      await _pumpFrames(tester);

      expect(inbox.dismissedTombstones, ['beacon-tomb']);
    });
  }

  for (final outcome in const [
    (value: AttentionForwardOutcome.notInterested, restores: true),
    (value: AttentionForwardOutcome.helping, restores: false),
    (value: AttentionForwardOutcome.watching, restores: false),
    (value: AttentionForwardOutcome.closedBeforeResponse, restores: false),
    (value: AttentionForwardOutcome.deletedBeforeResponse, restores: false),
  ]) {
    // §8 — «Вернуть» re-pins a *declined* forward. Nothing else is restorable:
    // a helping or following Request was not turned away, and the two
    // before-response terminals are the author's act, not the viewer's.
    testWidgets('restore on ${outcome.value.name} is ${outcome.restores}', (
      tester,
    ) async {
      final inboxRepo = FakeInboxRepository();
      final attentionRepo = _FeedAttentionRepo(
        firstPage: [
          _streamReceipt(
            id: 'tomb',
            itemKind: AttentionItemKind.forward,
            forwardOutcome: outcome.value,
          ),
        ],
      );
      wireActivityOffersV2(
        inbox: inboxRepo,
        attention: attentionRepo,
        items: const [],
        totalCount: 0,
      );
      final boot = await _boot(
        inboxRepo: inboxRepo,
        attentionRepo: attentionRepo,
      );
      addTearDown(boot.dispose);

      await _pumpStreamView(tester, boot: boot);

      expect(find.byType(TombstoneRow), findsOneWidget);
      expect(
        find.byKey(TombstoneRow.restoreKey),
        outcome.restores ? findsOneWidget : findsNothing,
      );
    });
  }

  // §9 state matrix: the outcome a grouped card displaced comes back as the
  // card's relation chip, so suppressing the duplicate loses nothing.
  testWidgets('the suppressed outcome returns as the card\'s relation', (
    tester,
  ) async {
    final inboxRepo = FakeInboxRepository();
    final attentionRepo = _FeedAttentionRepo(
      firstPage: [
        _streamReceipt(
          id: 'f',
          beaconId: 'beacon-rel',
          itemKind: AttentionItemKind.forward,
          forwardOutcome: AttentionForwardOutcome.watching,
        ),
        _streamReceipt(
          id: 'ra',
          beaconId: 'beacon-rel',
          itemKind: AttentionItemKind.requestActivity,
          eventTotal: 1,
        ),
      ],
    );
    wireActivityOffersV2(
      inbox: inboxRepo,
      attention: attentionRepo,
      items: const [],
      totalCount: 0,
    );
    final boot = await _boot(
      inboxRepo: inboxRepo,
      attentionRepo: attentionRepo,
    );
    addTearDown(boot.dispose);

    await _pumpStreamView(tester, boot: boot, logicalSize: const Size(360, 900));

    expect(find.byType(RequestAttentionCard), findsOneWidget);
    expect(
      tester.widget<RequestAttentionCard>(find.byType(RequestAttentionCard))
          .relation,
      RequestAttentionRelation.following,
    );
  });

  // The repo's own trap: a long intro/header at narrow width and 2x text
  // silently stops a ListView building the items below it, with no overflow
  // error. So the assertion is that the named widgets are *built*, not that
  // nothing threw.
  testWidgets('360dp at 2x text: the card and the tombstone below it build', (
    tester,
  ) async {
    final inboxRepo = FakeInboxRepository();
    final attentionRepo = _FeedAttentionRepo(
      firstPage: [
        _streamReceipt(
          id: 'wide',
          beaconId: 'beacon-wide',
          itemKind: AttentionItemKind.requestActivity,
          eventTotal: 4,
          provenanceJson: _provenanceJson(
            note: 'Ты же с этим возился когда-то, глянь пожалуйста, '
                'там совсем немного работы осталось',
          ),
          eventsPreview: [
            _streamReceipt(id: 'wide-c1'),
            _streamReceipt(id: 'wide-c2'),
          ],
        ),
        _streamReceipt(
          id: 'after',
          itemKind: AttentionItemKind.forward,
          forwardOutcome: AttentionForwardOutcome.helping,
        ),
      ],
    );
    wireActivityOffersV2(
      inbox: inboxRepo,
      attention: attentionRepo,
      items: [
        _offerItem(
          'worst',
          provenanceJson: _provenanceJson(
            note: 'Ты же с этим возился когда-то, глянь пожалуйста',
          ),
        ),
      ],
      totalCount: 1,
    );
    final boot = await _boot(
      inboxRepo: inboxRepo,
      attentionRepo: attentionRepo,
    );
    addTearDown(boot.dispose);

    await _pumpStreamView(
      tester,
      boot: boot,
      logicalSize: const Size(360, 4000),
      textScale: 2,
    );

    expect(find.byType(RequestAttentionCard), findsNWidgets(2));
    expect(find.byType(TombstoneRow), findsOneWidget);
    expect(find.byKey(RequestAttentionCard.headerKey), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('60 offers and 120 stream items scroll without duplicate keys', (
    tester,
  ) async {
    final inboxRepo = FakeInboxRepository();
    final offers = [for (var i = 0; i < 60; i++) _offerItem('b$i')];
    final attentionRepo = _FeedAttentionRepo(
      firstPage: [for (var i = 0; i < 120; i++) _streamReceipt(id: 's$i')],
    );
    wireActivityOffersV2(
      inbox: inboxRepo,
      attention: attentionRepo,
      items: offers,
      totalCount: 60,
    );
    final boot = await _boot(
      inboxRepo: inboxRepo,
      attentionRepo: attentionRepo,
    );
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

    expect(seenOffers.length, greaterThanOrEqualTo(20));
    expect(seenOffers.length, lessThanOrEqualTo(60));
    expect(seenStream.length, 120);
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
  }) async => const AttentionFeed(
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
