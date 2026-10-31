import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_actor_profiles_case.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/domain/use_case/author_invite_case.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/features/inbox/ui/widget/activity_invite_card.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/activity_offer_bounded_shell.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/inbox/ui/widget/activity_watching_digest_row.dart';
import 'package:tentura/features/inbox/ui/widget/for_you_empty_state.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/attention/ui/widget/request_attention_timeline_sheet.dart';
import 'package:tentura/features/inbox/ui/widget/post_attention_row.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/features/inbox/ui/widget/tombstone_row.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';
import 'package:tentura/ui/widget/undo_snack_bar.dart';
import 'package:tentura/ui/widget/caught_up_panel.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/test_realtime_sync.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'author_invite_test_support.dart';
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
  Future<void> dismiss(String beaconId, {String note = ''}) async {}

  final rejected = <({String beaconId, String message})>[];

  @override
  Future<void> reject(String beaconId, {String message = ''}) async =>
      rejected.add((beaconId: beaconId, message: message));

  @override
  Future<void> unreject(String beaconId) async {}

  final dismissedTombstones = <String>[];

  @override
  Future<void> dismissTombstone(String beaconId) async =>
      dismissedTombstones.add(beaconId);
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
  });

  final List<AttentionReceipt> firstPage;
  final String? nextCursor;
  final List<AttentionReceipt> secondPage = const [];
  int fetchCalls = 0;
  final List<String> historyCalls = [];

  @override
  Future<AttentionFeedPage> requestHistory({
    required String beaconId,
    String? cursor,
    int limit = 20,
  }) async {
    historyCalls.add(beaconId);
    return const AttentionFeedPage();
  }

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

  final List<String> markSeenCalls = [];

  @override
  Future<int> markSeen(List<String> ids) async {
    markSeenCalls.addAll(ids);
    return 0;
  }

  final List<String> markUnseenCalls = [];

  @override
  Future<int> markUnseen(List<String> ids) async {
    markUnseenCalls.addAll(ids);
    return 0;
  }

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
  DateTime? createdAt,
  int? beaconKind,
  bool requiresAction = false,
  DateTime? seenAt,
}) => AttentionReceipt(
  id: id,
  category: 'requestProgress',
  kind: 'relayReceived',
  priority: 'normal',
  title: 'Title $id',
  body: 'Body',
  actionUrl: '/#/',
  createdAt: createdAt ?? DateTime.utc(2026, 9, 10, 12),
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
  beaconKind: beaconKind,
  requiresAction: requiresAction,
  seenAt: seenAt,
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
  AuthorInviteCase? authorInviteCase,
  AttentionActorProfilesCase? actorProfiles,
  UiEffectPort? effects,
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
    actorProfiles: actorProfiles ?? buildNoopAttentionActorProfiles(),
    authorInviteCase: authorInviteCase,
    effects: effects,
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
  Locale locale = const Locale('en'),

  /// When set, the effects cubits emit on it reach the person as they do in
  /// the app (snack bars), through the real [UiEffectHandler].
  UiEffectPort? shownEffects,
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
          locale: locale,
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: logicalSize,
              textScaler: TextScaler.linear(textScale),
            ),
            child: TenturaResponsiveScope(
              child: shownEffects == null
                  ? const Scaffold(body: ActivityStreamView())
                  : UiEffectHandler(
                      effects: shownEffects,
                      child: const Scaffold(body: ActivityStreamView()),
                    ),
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

/// A snack bar line a person reads; its icon glyphs are `RichText`s too.
bool _isCopy(String line) => RegExp(r'\p{L}', unicode: true).hasMatch(line);

void main() {
  // U17b — the Timeline entry is one API. Both For You cards used to answer
  // "show me what happened here" differently: the pinned card pushed the
  // Request detail, and the stream card went through `openFromUpdate`, whose
  // destination map can route a receipt to a profile or the review screen.
  testWidgets('both For You cards open the same Request timeline', (
    tester,
  ) async {
    final inboxRepo = FakeInboxRepository();
    final attentionRepo = _FeedAttentionRepo(
      firstPage: [
        _streamReceipt(
          id: 'stream-1',
          beaconId: 'beacon-stream',
          itemKind: AttentionItemKind.requestActivity,
          eventTotal: 2,
          eventsPreview: [_streamReceipt(id: 'stream-c1')],
        ),
      ],
    );
    wireActivityOffersV2(
      inbox: inboxRepo,
      attention: attentionRepo,
      items: [_offerItem('beacon-pinned')],
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
      logicalSize: const Size(400, 2000),
    );

    final cards = tester
        .widgetList<RequestAttentionCard>(find.byType(RequestAttentionCard))
        .toList();
    expect(cards.length, 2, reason: 'the pinned card and the stream card');

    for (final card in cards) {
      card.onOpenTimeline();
      await tester.pumpAndSettle();
      expect(
        find.byType(RequestAttentionTimelineSheet),
        findsOneWidget,
        reason:
            "every attention surface reaches §9's timeline, not a route "
            'of its own',
      );
      final sheet = tester.widget<RequestAttentionTimelineSheet>(
        find.byType(RequestAttentionTimelineSheet),
      );
      expect(sheet.beaconId, card.beacon.id);
      Navigator.of(
        tester.element(find.byType(RequestAttentionTimelineSheet)),
      ).pop();
      await tester.pumpAndSettle();
    }

    expect(
      attentionRepo.historyCalls,
      ['beacon-pinned', 'beacon-stream'],
      reason: "and each one asks for its own Request's history",
    );
  });

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

    // CHANGES IN U16c-2: the pin key alone survived the retirement of
    // `ActivityOfferCard.prompt` without anything asserting the *card* it
    // wrapped, so flipping `activityOfferBoundedShell` off broke no test.
    // The pin is a bounded offer-shell card; say so where the stream builds it.
    expect(
      find.descendant(
        of: find.byKey(TestIds.key(TestIds.activityPromptPin('prompt-1'))),
        matching: find.byType(ActivityOfferBoundedShell),
      ),
      findsOneWidget,
    );
  });

  // #721: «You're caught up» sat right under an invite prompt that still
  // offered «Add details». Like Updates, a pinned prompt is content.
  testWidgets('#721 no caught-up state under a pending invite prompt', (
    tester,
  ) async {
    final inboxRepo = FakeInboxRepository();
    final attentionRepo = _FeedAttentionRepo(firstPage: [_promptReceipt()]);
    wireActivityOffersV2(
      inbox: inboxRepo,
      attention: attentionRepo,
      items: const [],
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

    // The positive first: the prompt with its action is on screen.
    expect(
      find.byKey(TestIds.key(TestIds.activityPromptPin('prompt-1'))),
      findsOneWidget,
    );
    expect(find.byType(ForYouEmptyState), findsNothing);
    expect(find.byType(CaughtUpPanel), findsNothing);
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
    expect(find.byType(TombstoneRow), findsOneWidget);
    expect(find.byType(RequestAttentionCard), findsOneWidget);
    // CHANGES IN U16b: correction 1, option (a) — the digest keeps its
    // `isInUnreadView` membership and its home in the overflow menu's
    // Watching collection; the primary stream does not draw it. Pinned in
    // `for_you_stream_entries_test.dart`, both halves together.
    expect(find.byType(ActivityWatchingDigestRow), findsNothing);
    // CHANGES IN #189 rev 2: the card draws its events as zones — a «вам»
    // row per sender and one change line — with the footer opening the
    // Timeline (D-171-5b). A general child is the change line.
    expect(
      find.byKey(RequestAttentionCard.changeLineKey),
      findsOneWidget,
    );
    expect(
      find.byKey(RequestAttentionCard.footerTimelineKey),
      findsOneWidget,
    );
  });

  // #476 — one Activity list, one age format and one trailing control. The
  // tombstone and the Request card speak the short card age («6m», #189
  // rev 2); the plain feed tile beside them said «7m ago» and wore a ⋮
  // where every other Activity row wears the ×.
  group('#476 Activity rows read the same', () {
    Future<_Boot> bootTileAndTombstone() async {
      final now = DateTime.now();
      final inboxRepo = FakeInboxRepository();
      final attentionRepo = _FeedAttentionRepo(
        firstPage: [
          _streamReceipt(
            id: 'r1',
            createdAt: now.subtract(const Duration(minutes: 7, seconds: 20)),
          ),
          _streamReceipt(
            id: 'f1',
            itemKind: AttentionItemKind.forward,
            forwardOutcome: AttentionForwardOutcome.helping,
            provenanceJson: _provenanceJson(),
            createdAt: now.subtract(const Duration(minutes: 6, seconds: 20)),
          ),
        ],
      );
      wireActivityOffersV2(
        inbox: inboxRepo,
        attention: attentionRepo,
        items: const [],
        totalCount: 0,
      );
      return _boot(inboxRepo: inboxRepo, attentionRepo: attentionRepo);
    }

    testWidgets('a feed tile shows the same short age as the tombstone', (
      tester,
    ) async {
      final boot = await bootTileAndTombstone();
      addTearDown(boot.dispose);

      await _pumpStreamView(tester, boot: boot);

      final tile = find.byType(UpdatesFeedTile);
      final tombstone = find.byType(TombstoneRow);
      expect(tile, findsOneWidget);
      expect(tombstone, findsOneWidget);

      // Precondition: the tombstone already reads the card age.
      expect(
        find.descendant(of: tombstone, matching: find.text('6m')),
        findsOneWidget,
      );
      // The tile beside it must read the same way, not «7m ago».
      expect(
        find.descendant(of: tile, matching: find.text('7m')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.textContaining('ago')),
        findsNothing,
      );
      expect(find.text('7m ago'), findsNothing);
    });

    testWidgets('a feed tile ends in the same × as the tombstone, not a ⋮', (
      tester,
    ) async {
      final boot = await bootTileAndTombstone();
      addTearDown(boot.dispose);
      final inbox = _TestInboxCubit(
        const InboxState(projectionLoaded: true),
      );

      await _pumpStreamView(tester, boot: boot, inbox: inbox);

      final tile = find.byType(UpdatesFeedTile);
      expect(tile, findsOneWidget);
      expect(find.byKey(TombstoneRow.dismissKey), findsOneWidget);

      // No overflow menu on the Activity tile: no ⋮.
      expect(
        find.descendant(of: tile, matching: find.byIcon(Icons.more_vert)),
        findsNothing,
      );
      expect(
        find.descendant(of: tile, matching: find.byIcon(Icons.more_horiz)),
        findsNothing,
      );

      // The tile's trailing control is the ×, labelled like the tombstone's.
      final tileDismiss = find.descendant(
        of: tile,
        matching: find.byTooltip(L10nEn().attentionEventDismiss),
      );
      expect(tileDismiss, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.byIcon(Icons.close)),
        findsOneWidget,
      );

      await tester.tap(tileDismiss);
      await _pumpFrames(tester);

      // The × marks this receipt seen (the stream's markSeen, as the
      // tombstone's × does) — and nothing else.
      expect(boot.attentionRepo.markSeenCalls, contains('r1'));
      expect(boot.attentionRepo.markSeenCalls, isNot(contains('f1')));
      expect(inbox.dismissedTombstones, isEmpty);
    });

    testWidgets('a Post row shows the same short age as the tombstone', (
      tester,
    ) async {
      final now = DateTime.now();
      final inboxRepo = FakeInboxRepository();
      final attentionRepo = _FeedAttentionRepo(
        firstPage: [
          _streamReceipt(
            id: 'p1',
            itemKind: AttentionItemKind.requestActivity,
            beaconKind: kBeaconKindPost,
            beaconId: 'post-1',
            eventTotal: 1,
            eventsPreview: [
              _streamReceipt(
                id: 'p1-event',
                beaconId: 'post-1',
                createdAt: now.subtract(
                  const Duration(minutes: 7, seconds: 20),
                ),
              ),
            ],
            createdAt: now.subtract(const Duration(minutes: 7, seconds: 20)),
          ),
          _streamReceipt(
            id: 'f1',
            itemKind: AttentionItemKind.forward,
            forwardOutcome: AttentionForwardOutcome.helping,
            provenanceJson: _provenanceJson(),
            createdAt: now.subtract(const Duration(minutes: 6, seconds: 20)),
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

      final post = find.byType(PostAttentionRow);
      final tombstone = find.byType(TombstoneRow);
      expect(post, findsOneWidget);
      expect(tombstone, findsOneWidget);

      // Precondition: the tombstone already reads the card age.
      expect(
        find.descendant(of: tombstone, matching: find.text('6m')),
        findsOneWidget,
      );
      // The Post row beside it must read the same way, not «7m ago».
      expect(
        find.descendant(of: post, matching: find.text('7m')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: post, matching: find.textContaining('ago')),
        findsNothing,
      );
    });

    // A live obligation is not cleared by markSeen (#336: the clear half
    // runs only for active-optional receipts), so a × there would leave the
    // row in place — a broken ×. Such a tile ends in neither a × nor a ⋮;
    // its way out is «Mark done», and Mark unread stays on long-press.
    testWidgets('a tile that requires action has no × and no ⋮, and Mark '
        'unread stays on long-press', (tester) async {
      final now = DateTime.now();
      final inboxRepo = FakeInboxRepository();
      final attentionRepo = _FeedAttentionRepo(
        firstPage: [
          _streamReceipt(
            id: 'ra',
            requiresAction: true,
            seenAt: now.subtract(const Duration(minutes: 1)),
            createdAt: now.subtract(const Duration(minutes: 7, seconds: 20)),
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

      final tile = find.byType(UpdatesFeedTile);
      expect(tile, findsOneWidget);
      // Its way out is the inline «Mark done».
      expect(
        find.descendant(
          of: tile,
          matching: find.text(L10nEn().updatesMarkDone),
        ),
        findsOneWidget,
      );
      // No × (markSeen would not clear it) …
      expect(
        find.descendant(
          of: tile,
          matching: find.byTooltip(L10nEn().attentionEventDismiss),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: tile, matching: find.byIcon(Icons.close)),
        findsNothing,
      );
      // … and no ⋮ either: Activity rows do not wear one.
      expect(
        find.descendant(of: tile, matching: find.byIcon(Icons.more_vert)),
        findsNothing,
      );

      // Mark unread is still one long-press away.
      // Press on the headline line (top of the row body), clear of the
      // inline «Mark done» button.
      final rowBody = find
          .descendant(of: tile, matching: find.byType(InkWell))
          .first;
      await tester.longPressAt(
        tester.getTopLeft(rowBody) + const Offset(12, 8),
      );
      await _pumpFrames(tester);
      final markUnread = find.text(L10nEn().updatesMarkUnseen);
      expect(markUnread, findsOneWidget);
      await tester.tap(markUnread);
      await _pumpFrames(tester);
      expect(boot.attentionRepo.markUnseenCalls, contains('ra'));
    });
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

    // CHANGES IN U16b/U16c-2: spec §5 "Retire" — the pinned zone is the
    // card's `pinned` variant (§9). The `ActivityOfferCard` absence assertion
    // retired with the widget in U16c-2; the positive claims below carry it.
    final cardFinder = find.byType(RequestAttentionCard);
    expect(cardFinder, findsOneWidget);
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
    expect(find.textContaining('Title dup-activity'), findsOneWidget);
    expect(find.textContaining('Offer offer-pinned'), findsOneWidget);
  });

  // Owner decision B: answered-forward outcomes stay in For You as
  // dismissible tombstones. m0183 made every outcome kind dismissible, so
  // every kind wears the ×. One assertion per kind — a × wired for the kind
  // that happened to be tested is the defect shape this plan keeps hitting.
  for (final outcome in _dismissibleOutcomeCases) {
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
  testWidgets("the suppressed outcome returns as the card's relation", (
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

    await _pumpStreamView(
      tester,
      boot: boot,
      logicalSize: const Size(360, 900),
    );

    expect(find.byType(RequestAttentionCard), findsOneWidget);
    expect(
      tester
          .widget<RequestAttentionCard>(find.byType(RequestAttentionCard))
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
            note:
                'Ты же с этим возился когда-то, глянь пожалуйста, '
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

  // U19 — release blocker 4, "every outcome kind dismissible", is proved by
  // the loop above and by `attention_outcome_dismissible_pg_test`. Both loops
  // are hand-written lists, so a sixth `AttentionForwardOutcome` would be
  // dismissible-untested and silently so. The enum is the source of truth for
  // how many kinds there are; this is the one assertion that says so.
  test('the dismissible-per-kind loop covers the whole enum', () {
    expect(
      {for (final c in _dismissibleOutcomeCases) c.value},
      AttentionForwardOutcome.values.toSet(),
      reason:
          'add the new outcome kind to the tombstone × loop here and to '
          'attention_outcome_dismissible_pg_test, or it ships untested',
    );
  });

  // U16c-1 deferred this and U19 delivers it.
  //
  // §4: "Because Dismiss all leaves decisions alone, a cleared For You can
  // still show its pinned zone." Every existing test of that sentence asserts
  // the predicate (`forYouEmptyKind`) or pumps `ForYouEmptyState` with a kind
  // handed to it. Neither proves the **assembled** surface computes
  // `hasPinnedZone: true` — and it cannot, because the pinned zone comes from
  // `offersState.items`, which the attention feed does not drive. An empty
  // attention page with a live pinned decision is precisely the combination a
  // predicate test cannot reach.
  testWidgets('nothing new, with the pinned decision still on screen', (
    tester,
  ) async {
    final l10n = L10nEn();
    final inboxRepo = FakeInboxRepository();
    // No rows at all on the attention side: the stream is swept clean.
    final attentionRepo = _FeedAttentionRepo(firstPage: const []);
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
      logicalSize: const Size(360, 1600),
    );

    // Positive first: the decision the sweep refused to answer is still here.
    expect(find.byType(RequestAttentionCard), findsOneWidget);
    expect(find.textContaining('Offer offer-pinned'), findsOneWidget);

    // And the surface speaks in the cleared voice, not the empty one.
    expect(find.byType(ForYouEmptyState), findsOneWidget);
    expect(find.byKey(CaughtUpPanel.titleKey), findsOneWidget);
    expect(find.text(l10n.forYouEmptyNothingNew), findsOneWidget);
    expect(
      find.text(l10n.forYouEmptyNothingHere),
      findsNothing,
      reason:
          'a surface still holding a decision has not never-had-anything; '
          'that is the sentence hasPinnedZone exists to prevent',
    );
    expect(
      find.byKey(CaughtUpPanel.clearedKey),
      findsNothing,
      reason: 'no explicit sweep ran here, so there is no number to claim',
    );
  });

  group('«Для вас» invite card (plan D3)', () {
    const inviter = Profile(id: 'Uinviter', displayName: 'Oleg');

    Future<({_Boot boot, FakeAuthorInvitePort port, FakeUiEffectPort effects})>
    bootWithInvite() async {
      final inboxRepo = FakeInboxRepository();
      final attentionRepo = _FeedAttentionRepo(firstPage: const []);
      final items = [_offerItem('B-invite'), _offerItem('B-plain')];
      wireActivityOffersV2(
        inbox: inboxRepo,
        attention: attentionRepo,
        items: items,
      );
      attentionRepo.offerRows = [
        for (final item in items)
          activityOfferSortRow(item).copyWith(
            inviteId: item.beaconId == 'B-invite' ? 'I1' : null,
          ),
      ];
      final port = FakeAuthorInvitePort()
        ..pending = [
          PendingAuthorInvite(
            id: 'I1',
            beaconId: 'B-invite',
            beaconTitle: 'Offer B-invite',
            inviterId: inviter.id,
            createdAt: DateTime.utc(2026, 10, 11),
            note: 'You have a ladder',
          ),
        ];
      final effects = FakeUiEffectPort();
      final boot = await _boot(
        inboxRepo: inboxRepo,
        attentionRepo: attentionRepo,
        authorInviteCase: buildAuthorInviteCase(port),
        actorProfiles: buildActorProfiles(const [inviter]),
        effects: effects,
      );
      return (boot: boot, port: port, effects: effects);
    }

    final inviteCard = find.byType(ActivityInviteCard);

    testWidgets('a row with inviteId renders the invite card', (tester) async {
      final (:boot, :port, :effects) = await bootWithInvite();
      addTearDown(boot.dispose);
      await _pumpStreamView(
        tester,
        boot: boot,
        logicalSize: const Size(360, 1600),
      );

      expect(inviteCard, findsOneWidget);
      expect(find.text('Oleg invites you to help'), findsOneWidget);
      expect(find.text('You have a ladder'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text("Can't make it"), findsOneWidget);
      // The other pinned row keeps the ordinary Request card.
      expect(find.byType(RequestAttentionCard), findsOneWidget);
      expect(find.textContaining('Offer B-plain'), findsOneWidget);
    });

    testWidgets('«Accept» answers the invite and the row leaves the zone', (
      tester,
    ) async {
      final (:boot, :port, :effects) = await bootWithInvite();
      addTearDown(boot.dispose);
      await _pumpStreamView(
        tester,
        boot: boot,
        logicalSize: const Size(360, 1600),
      );

      await tester.tap(find.byKey(const Key('ActivityInviteCard.Accept')));
      await _pumpFrames(tester);

      expect(port.accepted, ['I1']);
      expect(inviteCard, findsNothing);
      expect(find.textContaining('Offer B-plain'), findsOneWidget);
    });

    testWidgets('a refused accept puts the invite card back', (tester) async {
      final (:boot, :port, :effects) = await bootWithInvite();
      addTearDown(boot.dispose);
      port.error = const AuthorInviteNotPendingException('withdrawn');
      await _pumpStreamView(
        tester,
        boot: boot,
        logicalSize: const Size(360, 1600),
      );

      await tester.tap(find.byKey(const Key('ActivityInviteCard.Accept')));
      await _pumpFrames(tester);

      expect(inviteCard, findsOneWidget);
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
    });

    testWidgets("«Can't make it» goes through the decline dialog", (
      tester,
    ) async {
      final (:boot, :port, :effects) = await bootWithInvite();
      addTearDown(boot.dispose);
      await _pumpStreamView(
        tester,
        boot: boot,
        logicalSize: const Size(360, 1600),
      );

      await tester.tap(find.byKey(const Key('ActivityInviteCard.Decline')));
      await _pumpFrames(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Away that weekend');
      await tester.tap(find.text(L10nEn().buttonOk));
      await _pumpFrames(tester);

      expect(port.declined, ['I1']);
      expect(inviteCard, findsNothing);
      expect(
        boot.inboxRepo.lastSetStatus?.rejectionMessage,
        'Away that weekend',
      );
    });
  });

  // #725 (QA 2026-10-26, step 5): a viewer whose author invitation to this
  // Request is answered «Can't make it» can meet the plain Request card again
  // (restored, re-forwarded, or after a reload). Its ⋮ said "Can't help" and
  // opened "Can't help?", and the row then said "You said you can't make it":
  // two wordings on one route. On an invited viewer's card the route keeps
  // the invitation's words; a forwarded Request keeps "Can't help?".
  group("#725 the card ⋮ on an invited viewer's Request", () {
    Future<({_Boot boot, _TestInboxCubit inbox})> bootCards(
      WidgetTester tester, {
      required bool declinedInvite,
    }) async {
      final inboxRepo = FakeInboxRepository();
      final attentionRepo = _FeedAttentionRepo(firstPage: const []);
      final items = [_offerItem('B-725')];
      wireActivityOffersV2(
        inbox: inboxRepo,
        attention: attentionRepo,
        items: items,
      );
      attentionRepo.offerRows = [
        activityOfferSortRow(
          items.single,
        ).copyWith(declinedInvite: declinedInvite),
      ];
      final boot = await _boot(
        inboxRepo: inboxRepo,
        attentionRepo: attentionRepo,
        authorInviteCase: buildAuthorInviteCase(FakeAuthorInvitePort()),
      );
      final inbox = _TestInboxCubit(
        const InboxState(projectionLoaded: true),
      );
      await _pumpStreamView(
        tester,
        boot: boot,
        inbox: inbox,
        logicalSize: const Size(360, 1600),
      );
      return (boot: boot, inbox: inbox);
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: find.byType(RequestAttentionCard),
          matching: find.byIcon(Icons.more_vert),
        ),
      );
      await _pumpFrames(tester);
    }

    final l10n = L10nEn();

    testWidgets("an answered invitation: «Can't make it» → "
        "«Can't make it?», never «Can't help»", (tester) async {
      final (:boot, :inbox) = await bootCards(tester, declinedInvite: true);
      addTearDown(boot.dispose);
      expect(find.byType(ActivityInviteCard), findsNothing);

      await openMenu(tester);
      expect(find.text(l10n.inviteDecline), findsOneWidget);
      expect(find.text(l10n.actionCantHelp), findsNothing);

      await tester.tap(find.text(l10n.inviteDecline));
      await _pumpFrames(tester);
      expect(find.text(l10n.inviteDeclineDialogTitle), findsOneWidget);
      expect(find.text(l10n.rejectionDialogTitle), findsNothing);

      await tester.enterText(find.byType(TextField), 'Still away');
      await tester.tap(find.text(l10n.buttonOk));
      await _pumpFrames(tester);
      expect(inbox.rejected, [(beaconId: 'B-725', message: 'Still away')]);
    });

    testWidgets("a forwarded Request keeps «Can't help» → «Can't help?»", (
      tester,
    ) async {
      final (:boot, :inbox) = await bootCards(tester, declinedInvite: false);
      addTearDown(boot.dispose);

      await openMenu(tester);
      expect(find.text(l10n.actionCantHelp), findsOneWidget);
      expect(find.text(l10n.inviteDecline), findsNothing);

      await tester.tap(find.text(l10n.actionCantHelp));
      await _pumpFrames(tester);
      expect(find.text(l10n.rejectionDialogTitle), findsOneWidget);
      expect(find.text(l10n.inviteDeclineDialogTitle), findsNothing);

      await tester.tap(find.text(l10n.buttonOk));
      await _pumpFrames(tester);
      expect(inbox.rejected, [(beaconId: 'B-725', message: '')]);
    });
  });

  // #797: «Can't make it» is easy to hit by mistake; right after it the person
  // gets a snack bar with Undo, and the invitation card comes back.
  group("Undo after «Can't make it» on the invite card", () {
    // An error bar logs through the app's Logger.
    setUp(() {
      if (!GetIt.I.isRegistered<Logger>()) {
        GetIt.I.registerSingleton<Logger>(Logger('undo-test'));
      }
    });
    tearDown(() async {
      if (GetIt.I.isRegistered<Logger>()) await GetIt.I.unregister<Logger>();
    });

    const inviter = Profile(id: 'Uinviter', displayName: 'Oleg');

    Future<({_Boot boot, FakeAuthorInvitePort port, FakeUiEffectPort effects})>
    bootWithInvite() async {
      final inboxRepo = FakeInboxRepository();
      final attentionRepo = _FeedAttentionRepo(firstPage: const []);
      final items = [_offerItem('B-invite'), _offerItem('B-plain')];
      wireActivityOffersV2(
        inbox: inboxRepo,
        attention: attentionRepo,
        items: items,
      );
      attentionRepo.offerRows = [
        for (final item in items)
          activityOfferSortRow(item).copyWith(
            inviteId: item.beaconId == 'B-invite' ? 'I1' : null,
          ),
      ];
      final port = FakeAuthorInvitePort()
        ..pending = [
          PendingAuthorInvite(
            id: 'I1',
            beaconId: 'B-invite',
            beaconTitle: 'Offer B-invite',
            inviterId: inviter.id,
            createdAt: DateTime.utc(2026, 10, 11),
            note: 'You have a ladder',
          ),
        ];
      final effects = FakeUiEffectPort();
      final boot = await _boot(
        inboxRepo: inboxRepo,
        attentionRepo: attentionRepo,
        authorInviteCase: buildAuthorInviteCase(port),
        actorProfiles: buildActorProfiles(const [inviter]),
        effects: effects,
      );
      return (boot: boot, port: port, effects: effects);
    }

    /// «Can't make it» → the dialog → OK, as a person does it.
    Future<void> declineThroughDialog(
      WidgetTester tester, {
      required String ok,
    }) async {
      await tester.tap(find.byKey(const Key('ActivityInviteCard.Decline')));
      await _pumpFrames(tester);
      await tester.enterText(find.byType(TextField), 'Away that weekend');
      await tester.tap(find.text(ok));
      // An action snack bar is shown after the next frame; a test with no
      // animation running has to ask for it (the app always has one).
      tester.binding.scheduleFrame();
      await _pumpFrames(tester);
    }

    final inviteCard = find.byType(ActivityInviteCard);
    final undo = find.descendant(
      of: find.byType(SnackBar),
      matching: find.byType(SnackBarAction),
    );
    // The bar's message is a RichText; the action label is a Text (a RichText
    // too), so this finds both.
    final snackBarTexts = find.descendant(
      of: find.byType(SnackBar),
      matching: find.byType(RichText),
    );

    String lineOf(RichText text) => text.text.toPlainText();

    testWidgets("after «Can't make it» the snack bar offers Undo, and "
        'tapping it brings the invite card back', (tester) async {
      final (:boot, :port, :effects) = await bootWithInvite();
      addTearDown(boot.dispose);
      await _pumpStreamView(
        tester,
        boot: boot,
        logicalSize: const Size(360, 1600),
        shownEffects: effects,
      );

      await declineThroughDialog(tester, ok: L10nEn().buttonOk);

      expect(port.declined, ['I1']);
      expect(inviteCard, findsNothing);
      expect(undo, findsOneWidget);
      expect(
        find.descendant(of: undo, matching: find.text('Undo')),
        findsOneWidget,
      );
      expect(port.revertedDeclines, isEmpty, reason: 'nothing undone yet');

      await tester.tap(undo);
      await _pumpFrames(tester);

      expect(port.revertedDeclines, ['I1']);
      expect(inviteCard, findsOneWidget);
      expect(find.text('Oleg invites you to help'), findsOneWidget);
      expect(find.text('You have a ladder'), findsOneWidget);
      expect(
        find.byKey(const Key('ActivityInviteCard.Accept')),
        findsOneWidget,
      );
    });

    testWidgets('the Undo snack bar is the shared long-lived Undo bar: it is '
        'not pinned, leaves on its own, and the decline stands', (
      tester,
    ) async {
      final (:boot, :port, :effects) = await bootWithInvite();
      addTearDown(boot.dispose);
      await _pumpStreamView(
        tester,
        boot: boot,
        logicalSize: const Size(360, 1600),
        shownEffects: effects,
      );
      await declineThroughDialog(tester, ok: L10nEn().buttonOk);
      expect(undo, findsOneWidget);

      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.duration, kUndoSnackBarDuration);
      expect(bar.persist, isFalse);

      // Still up just before the Undo window ends: a shorter bar is wrong.
      await tester.pump(kUndoSnackBarDuration - const Duration(seconds: 2));
      expect(undo, findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(port.revertedDeclines, isEmpty);
      expect(inviteCard, findsNothing);
    });

    // A refusal (the Request closed meanwhile, the invitation replaced) reads
    // as a translated sentence, never a raw key or the exception's own text.
    for (final (locale, language) in [
      (const Locale('en'), 'English'),
      (const Locale('ru'), 'Russian'),
    ]) {
      testWidgets('a refused Undo tells the person in $language, in plain '
          'words', (tester) async {
        final (:boot, :port, :effects) = await bootWithInvite();
        addTearDown(boot.dispose);
        port.revertError = const AuthorInviteRequestNotOpenException();
        await _pumpStreamView(
          tester,
          boot: boot,
          logicalSize: const Size(360, 1600),
          locale: locale,
          shownEffects: effects,
        );
        final ok = locale.languageCode == 'ru'
            ? L10nRu().buttonOk
            : L10nEn().buttonOk;
        await declineThroughDialog(tester, ok: ok);
        expect(undo, findsOneWidget);
        final undoLabel = locale.languageCode == 'ru' ? 'Отменить' : 'Undo';

        await tester.tap(undo);
        await _pumpFrames(tester);

        expect(port.revertedDeclines, ['I1']);
        expect(inviteCard, findsNothing);
        // The Undo bar gave way to the error bar.
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(undoLabel),
          ),
          findsNothing,
        );
        final lines = [
          for (final text in tester.widgetList<RichText>(snackBarTexts))
            lineOf(text).trim(),
        ].where(_isCopy).toList();
        expect(lines, isNotEmpty, reason: 'the refusal is told');
        final message = lines.first;
        expect(
          message,
          isNot(matches(RegExp(r'^[a-z]+(?:[A-Z][a-z0-9]*)+$'))),
          reason: 'no raw l10n key',
        );
        for (final raw in ['Exception', 'Instance of', 'AuthorInvite']) {
          expect(message, isNot(contains(raw)));
        }
        expect(message.split(RegExp(r'\s+')).length, greaterThan(2));
        expect(message, endsWith('.'));
        expect(
          message,
          locale.languageCode == 'ru'
              ? matches(RegExp('[А-Яа-я]'))
              : isNot(matches(RegExp('[А-Яа-я]'))),
          reason: 'the sentence is in the app language',
        );
      });
    }

    // Fix completeness step 4: QA's phone, in Russian.
    testWidgets('375×667 in Russian: the Undo snack bar renders in full '
        'and works', (tester) async {
      await usePhoneSurface(tester);
      final (:boot, :port, :effects) = await bootWithInvite();
      addTearDown(boot.dispose);
      await _pumpStreamView(
        tester,
        boot: boot,
        logicalSize: kPhoneSurface,
        locale: const Locale('ru'),
        shownEffects: effects,
      );

      await declineThroughDialog(tester, ok: L10nRu().buttonOk);

      expect(port.declined, ['I1']);
      expect(undo, findsOneWidget);
      expect(
        find.descendant(of: undo, matching: find.text('Отменить')),
        findsOneWidget,
      );
      final bar = tester.getRect(find.byType(SnackBar));
      expect(bar.left, greaterThanOrEqualTo(0));
      expect(bar.right, lessThanOrEqualTo(kPhoneSurface.width));
      expect(bar.bottom, lessThanOrEqualTo(kPhoneSurface.height));
      final action = tester.getRect(undo);
      expect(action.left, greaterThanOrEqualTo(bar.left));
      expect(action.right, lessThanOrEqualTo(bar.right));
      // The message beside the action is whole: no ellipsis, in Russian.
      final lines = [
        for (final text in tester.widgetList<RichText>(snackBarTexts))
          lineOf(text).trim(),
      ].where(_isCopy);
      expect(lines.length, greaterThan(1), reason: 'message and action');
      for (final line in lines) {
        expect(line, isNot(endsWith('…')));
        expect(line, matches(RegExp('[А-Яа-я]')));
      }
      expect(tester.takeException(), isNull);

      await tester.tap(undo);
      await _pumpFrames(tester);

      expect(port.revertedDeclines, ['I1']);
      expect(inviteCard, findsOneWidget);
      expect(find.text('Принять'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// The cases the tombstone × loop runs. Hoisted so the exhaustiveness guard
/// reads the same list the loop does, rather than a third copy of it.
const _dismissibleOutcomeCases =
    <({AttentionForwardOutcome value, String name})>[
      (value: AttentionForwardOutcome.helping, name: 'helping'),
      (value: AttentionForwardOutcome.watching, name: 'watching'),
      (value: AttentionForwardOutcome.notInterested, name: 'notInterested'),
      (value: AttentionForwardOutcome.closedBeforeResponse, name: 'closed'),
      (value: AttentionForwardOutcome.deletedBeforeResponse, name: 'deleted'),
    ];

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}
