import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_lobby/ui/bloc/beacon_lobby_entry_cubit.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

import '../../domain/attention/attention_case_test_support.dart';
import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';
import '../beacon_lobby/fake_lobby_port.dart' show FakeLobbyPort;
import '../beacon_threads/room_cubit_fakes.dart' as discussion;
import '../beacon_view/beacon_view_case_test_support.dart' as detail;
import '../block/support/controllable_block_case.dart';
import '../inbox/inbox_case_test.dart' as activity;
import '../my_work/my_work_test_support.dart' as desk;
import 'read_cursor_server_frames.dart';
import 'request_change_hint_replay.dart';

const _beaconId = discussion.kRoomCubitFakeBeaconId;
const _authorId = kReplayAuthorId;
const _helperId = kReplayHelperId;
const _feedDestination = AttentionFeedDestinationId.activityStream;

class _ForwardSnapshots extends detail.FakeBeaconViewForwardRepository {
  int involvementReads = 0;
  int generation = 0;
  final involvementCalls = <({String beaconId, StackTrace stack})>[];

  @override
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) async => [];

  @override
  Future<Map<String, List<String>>> fetchReasonsByBeacon({
    required String beaconId,
  }) async => {};

  @override
  Future<BeaconInvolvementData> fetchInvolvementForBeacon(Beacon beacon) async {
    involvementReads++;
    involvementCalls.add((beaconId: beacon.id, stack: StackTrace.current));
    return (
      beacon: beacon,
      forwardedToIds: <String>{},
      helpOfferedIds: <String>{kReplayHelperId},
      withdrawnIds: <String>{},
      declinedOfferIds: <String>{},
      rejectedIds: <String>{},
      watchingIds: <String>{kReplayHelperId, 'watcher-$generation'},
      onwardForwarderIds: <String>{},
      myForwardedRecipientNotes: <String, String>{},
      myForwardedRecipientEdgeIds: <String, String>{},
      myForwardedRecipientReadAts: <String, DateTime?>{},
      myForwardedRecipientHasOnwardChild: <String, bool>{},
      myForwardedRecipientRejected: <String, bool>{},
    );
  }

  @override
  Stream<String> get forwardCommandCompleted => const Stream.empty();
}

class DiscussionSnapshots extends discussion.FakeBeaconThreadsRepository {
  DiscussionSnapshots(String userId) : super(userId: userId);

  int roomStateReads = 0;
  void Function(String threadId, DateTime at)? onSeen;

  @override
  Future<DateTime> markThreadSeen({
    required String beaconId,
    required String threadId,
    required DateTime readThroughAt,
  }) async {
    onSeen?.call(threadId, readThroughAt);
    return readThroughAt;
  }

  @override
  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async {
    roomStateReads++;
    return BeaconRoomState(
      beaconId: beaconId,
      updatedAt: DateTime.utc(2026),
      currentLine: 'Bring the tools',
    );
  }
}

class _AttentionSnapshots extends desk.StubAttentionRepository {
  List<AttentionReceipt> receipts = const [];
  int feedReads = 0;
  int summaryReads = 0;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async {
    feedReads++;
    return AttentionFeed(
      summary: AttentionSummary(unreadTotal: receipts.length),
      page: AttentionFeedPage(items: receipts),
    );
  }

  @override
  Future<AttentionSurfaceSummary> surfaceSummary() async {
    summaryReads++;
    return AttentionSurfaceSummary(forYouDot: receipts.isNotEmpty);
  }
}

/// Real cubits/cases and the real websocket invalidation buffer. Only the
/// repository I/O is replaced. The adapter below is the existing repository
/// seam: BeaconRepository emits RepositoryEventInvalidate, ForwardRepository
/// emits HelpOfferInvalidated, and rooms use fromRealtimeChange. It performs
/// no batching, read suppression or timing of its own.
class OpenRequestObserverHarness {
  OpenRequestObserverHarness(
    this.scenario,
    this.clock, {
    int initialGeneration = 0,
    bool echoReadMarks = false,
    bool readerHasSeenRow = true,
    this.withUnreadHints = false,
    DiscussionSnapshots? discussionRepository,
    InvalidationService? invalidationService,
    RoomReadWatermarkStore? watermarkStore,
    this.viewerOverride,
    String? threadItemId,
    activity.FakeInboxRepository? inboxRepository,
    Zone? homeInboxZone,
    Zone? watchingInboxZone,
  }) : watermark = watermarkStore ?? RoomReadWatermarkStore.testing(),
       inboxRepo = inboxRepository ?? activity.FakeInboxRepository(),
       ownsInvalidations = invalidationService == null {
    registerProfile();
    invalidations =
        invalidationService ?? InvalidationService.forTesting(socket.stream);
    realtime = RealtimeSyncCase(invalidations);
    roomRepo = discussionRepository ?? DiscussionSnapshots(viewerId);
    if (echoReadMarks) {
      // The server persists the cursor and fans out the frame its trigger
      // NOTIFY produces (pinned by the server tests, actor echo on or off):
      // the reader's first read of a scope is an INSERT, later ones UPDATEs.
      final persistedScopes = <String>{
        if (readerHasSeenRow) ...[RequestThread.generalId, ?threadItemId],
      };
      roomRepo.onSeen = (threadId, at) {
        final event = persistedScopes.add(threadId) ? 'insert' : 'update';
        socket.add(
          roomSeenReadCursorFrame(
            readerId: viewerId,
            beaconId: _beaconId,
            at: at,
            event: event,
            threadItemId: threadId == RequestThread.generalId ? null : threadId,
          ),
        );
      };
    }
    roomCase = BeaconThreadsCase(
      roomRepo,
      roomFacts,
      discussion.FakePollingRepository(),
      discussion.FakeBeaconRoomHintsRepository(),
      watermark,
      realtime,
      env: const Env(),
      logger: Logger('open request refresh'),
    );
    attention = AttentionCase(
      attentionRepo,
      accounts,
      realtime,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('open client attention'),
      qaLatencyMeasurementEnabled: false,
    )..attachFeedSession(_feedDestination);

    bridge = invalidations.entityChanges.listen((change) {
      delivered.add((
        at: clock.elapsed,
        kind: change.kind,
        aggregateId: change.aggregateId,
        operation: change.operation,
        actorUserId: change.actorUserId,
        childId: change.childId,
      ));
      if (change.kind == RealtimeEntityKind.beacon) {
        beaconRepo.emitInvalidation(change.aggregateId);
      }
      if (change.kind == RealtimeEntityKind.helpOffer) {
        final event = HelpOfferInvalidated(change.aggregateId);
        forward.emitHelpOfferChange(event);
        deskForward.emitHelpOffer(event);
      }
      final roomHint = BeaconRoomInvalidation.fromRealtimeChange(change);
      if (roomHint != null) {
        viewRoom.emitRoomInvalidation(roomHint);
        deskRoom.emitRoomInvalidation(roomHint);
        if (discussionRepository == null) {
          roomRepo.emitInvalidation(
            roomHint.entityType,
            operation: roomHint.operation,
            messageId: roomHint.messageId,
            paint: roomHint.paint,
          );
        }
      }
    });
    setSnapshot(initialGeneration);
    view = BeaconViewCubit(
      id: _beaconId,
      myProfile: Profile(id: viewerId),
      beaconViewCase: detail.buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        forward: forward,
        roomRepo: viewRoom,
        factCardsRepo: viewFacts,
        realtimeSyncCase: realtime,
      ),
      effects: FakeUiEffectPort(),
    );
    room = RoomCubit(
      beaconId: _beaconId,
      threadItemId: threadItemId,
      lobbyAccess: threadItemId == null
          ? null
          : const BeaconLobbyAccess(canRead: true, canPost: true),
      capabilities: threadItemId == null
          ? const RoomCapabilities.request()
          : const RoomCapabilities.questions(),
      beaconRoomCase: roomCase,
      coordinationItemRoomSync: CoordinationItemRoomSync(),
      presenceRepository: discussion.roomCubitFakePresenceRepository(),
      effects: FakeUiEffectPort(),
    );
    final inboxCase = activity.buildTestInboxCase(
      inboxRepo,
      roomCase,
      forwardRepository: forward,
      realtimeSyncCase: realtime,
    );
    // Home keeps its InboxCubit mounted when Watching creates another one.
    // Both are observers of the same projection and must share its read.
    homeInbox = (homeInboxZone ?? Zone.current).run(
      () => InboxCubit(
        userId: viewerId,
        inboxCase: inboxCase,
        effects: FakeUiEffectPort(),
      ),
    );
    watchingInbox = (watchingInboxZone ?? Zone.current).run(
      () => InboxCubit(
        userId: viewerId,
        inboxCase: inboxCase,
        effects: FakeUiEffectPort(),
      ),
    );
    myWork = MyWorkCubit(
      userId: viewerId,
      myWorkCase: desk.buildTestMyWorkCase(
        repo: myWorkRepo,
        roomHints: deskHints,
        watermarkStore: watermark,
        beaconRepo: beaconRepo,
        forwardRepo: deskForward,
        roomRepo: deskRoom,
        realtimeSyncCase: realtime,
        attentionCase: attention,
      ),
    );
    final beacons = FakeBeaconWritePort();
    children = BeaconHierarchyCubit(
      beaconId: _beaconId,
      hierarchyCase: buildBeaconHierarchyCaseForTest(
        hierarchyRepo,
        createCase: BeaconCreateCase(beacons, FakeBeaconImagePort()),
        beacons: beacons,
        commandStore: InMemoryBeaconChildCommandStore(),
        realtimeSyncCase: realtime,
      ),
    );
    unawaited(children.load());
    accounts.emit(viewerId);
  }

  final bool withUnreadHints;
  final RequestChangeReplay scenario;
  final FakeAsync clock;
  final String? viewerOverride;
  final bool ownsInvalidations;
  String get viewerId => viewerOverride ?? scenario.viewerId;
  String get helperId =>
      scenario == RequestChangeReplay.enoughHelp ? viewerId : _helperId;
  String actorFor(int generation) => scenario.actorFor(generation);
  void registerProfile() => discussion.registerRoomCubitProfileCubit(viewerId);

  final RoomReadWatermarkStore watermark;
  final socket = StreamController<Map<String, dynamic>>.broadcast();
  late final InvalidationService invalidations;
  late final RealtimeSyncCase realtime;
  late final StreamSubscription<RealtimeEntityChange> bridge;

  /// What InvalidationService hands to the app, and when.
  final delivered =
      <
        ({
          Duration at,
          RealtimeEntityKind kind,
          String aggregateId,
          RealtimeOperation operation,
          String? actorUserId,
          String? childId,
        })
      >[];
  final beaconRepo = detail.TrackingBeaconRepository();
  final forward = _ForwardSnapshots();
  final deskForward = desk.FakeForwardRepository();
  final viewRoom = detail.FakeBeaconViewRoomRepository();
  final deskRoom = desk.FakeBeaconThreadsRepository();
  late final DiscussionSnapshots roomRepo;
  final viewFacts = detail.FakeBeaconViewFactCardRepository();
  final roomFacts = detail.FakeBeaconViewFactCardRepository();
  final activity.FakeInboxRepository inboxRepo;
  final myWorkRepo = desk.FakeMyWorkRepository();
  final deskHints = desk.FakeRoomHints();
  final attentionRepo = _AttentionSnapshots();
  final accounts = AttentionCaseTestAccounts();
  late final AttentionCase attention;
  final hierarchyRepo = FakeBeaconHierarchyRepositoryPort();
  final childReads = <BeaconHierarchyChildGroup, int>{};
  late final BeaconViewCubit view;
  late final RoomCubit room;
  late final BeaconThreadsCase roomCase;
  late final InboxCubit homeInbox;
  late final InboxCubit watchingInbox;
  late final MyWorkCubit myWork;
  late final BeaconHierarchyCubit children;

  void setSnapshot(int generation, {BeaconStatus? statusOverride}) {
    final status =
        statusOverride ??
        (scenario == RequestChangeReplay.helperLeaves || generation == 0
            ? BeaconStatus.open
            : generation == 1
            ? BeaconStatus.enoughHelp
            : BeaconStatus.needsMoreHelp);
    final beacon = Beacon(
      id: _beaconId,
      title: 'Request snapshot $generation',
      author: const Profile(id: _authorId),
      status: status,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026, 1, 1, 0, 0, generation),
    );
    beaconRepo.fetchByIdHandler = (_) async => beacon;
    forward.generation = generation;
    viewRoom.roomState = BeaconRoomState(
      beaconId: _beaconId,
      updatedAt: DateTime.utc(2026),
      currentLine: 'Bring the tools',
    );
    final participants = [
      for (final userId in [
        _authorId,
        if (scenario == RequestChangeReplay.enoughHelp || generation == 0)
          helperId,
        if (scenario == RequestChangeReplay.helperLeaves && generation < 2)
          kReplayOtherHelperId,
      ])
        BeaconParticipant(
          id: 'participant-$userId',
          beaconId: _beaconId,
          userId: userId,
          role: 0,
          status: 0,
          roomAccess: 1,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
    ];
    viewRoom.participants = participants;
    roomRepo.participants = participants;
    roomRepo.messages = generation == 0
        ? []
        : [
            RoomMessage(
              id: 'notice-$generation',
              beaconId: _beaconId,
              authorId: actorFor(generation),
              body: scenario == RequestChangeReplay.enoughHelp
                  ? (status == BeaconStatus.open
                        ? 'Open'
                        : generation == 1
                        ? 'Enough help'
                        : 'Needs more help')
                  : 'Helper left the discussion',
              createdAt: DateTime.utc(2026, 1, 1, 0, 0, generation),
            ),
          ];
    final facts = [
      BeaconFactCard(
        id: 'fact',
        beaconId: _beaconId,
        factText: 'Tools are in the shed',
        visibility: 0,
        pinnedBy: _authorId,
        createdAt: DateTime.utc(2026),
        status: 0,
      ),
    ];
    viewFacts.cards = facts;
    roomFacts.cards = facts;
    final unreadHints = InboxRoomCardHints(
      isRoomMember: true,
      roomUnreadCount: generation == 0 ? 0 : 1,
      lastSeenAt: DateTime.utc(2026),
    );
    if (withUnreadHints) deskHints.hintsByBeaconId = {_beaconId: unreadHints};
    inboxRepo.fetchResult = [
      InboxItem(
        beaconId: _beaconId,
        latestForwardAt: DateTime.utc(2026),
        status: InboxItemStatus.watching,
        roomHints: withUnreadHints ? unreadHints : null,
        beacon: beacon,
      ),
    ];
    myWorkRepo.initResult = (
      authoredNonArchived: viewerId == _authorId ? [beacon] : const <Beacon>[],
      helpOfferedNonArchived: [
        if (viewerId == helperId)
          (
            beacon: beacon,
            helpOfferRowUpdatedAt: DateTime.utc(2026),
            offerHelpMessage: 'I can bring tools',
            helpType: null,
            authorResponseType: null,
            authorCoordinationUpdatedAt: null,
            coordinationAuthor: null,
            forwarderSenders: const <Profile>[],
            stakeState: CommitmentStakeState.none,
          ),
      ],
      obligationBeacons: const [],
      archivedCountHint: 0,
    );
    attentionRepo.receipts = generation == 0
        ? []
        : [
            attentionCaseTestReceipt(id: 'receipt-$generation').copyWith(
              beaconId: _beaconId,
              body: 'Change $generation',
            ),
          ];
    hierarchyRepo.fetchChildrenHandler = ({required group, after}) async {
      childReads.update(group, (n) => n + 1, ifAbsent: () => 1);
      // Keep a nonempty authoritative child slice: a refresh returning nothing
      // must fail convergence, even if its operation count happens to be low.
      return BeaconHierarchyPage(
        summaries: group == BeaconHierarchyChildGroup.active
            ? [
                BeaconHierarchySummary(
                  beaconId: 'child',
                  title: 'Visible child',
                  status: BeaconStatus.open,
                  publishedAt: DateTime.utc(2026),
                  isTombstone: false,
                  owner: const BeaconHierarchyOwnerSummary(
                    id: _authorId,
                    displayName: 'Author',
                  ),
                ),
              ]
            : [],
      );
    };
  }

  /// The read operations each surface may issue at most once per change.
  Map<String, int> readCounts() => {
    'detail.BeaconRoomStateGet': viewRoom.fetchBeaconRoomStateCalls,
    'discussion.BeaconRoomStateGet': roomRepo.roomStateReads,
    'discussion.RoomMessageList': roomRepo.fetchMessagesCallCount,
    'detail.BeaconFactCardList': viewFacts.listCalls,
    'discussion.BeaconFactCardList': roomFacts.listCalls,
    'home+watching.InboxFetch': inboxRepo.fetchCallCount,
    'desk.MyWorkInit': myWorkRepo.fetchInitCallCount,
    for (final group in BeaconHierarchyChildGroup.values)
      'children.BeaconChildren(${group.name})': childReads[group] ?? 0,
  };

  void expectSnapshot(
    int generation, {
    BeaconStatus? statusOverride,
    bool includeRoom = true,
  }) {
    expect(view.state.loadError, isNull);
    expect(room.state.loadError, isNull);
    expect(view.state.beacon.title, 'Request snapshot $generation');
    expect(
      view.state.beacon.status,
      statusOverride ??
          (generation == 0 || scenario == RequestChangeReplay.helperLeaves
              ? BeaconStatus.open
              : generation == 1
              ? BeaconStatus.enoughHelp
              : BeaconStatus.needsMoreHelp),
    );
    expect(view.state.beaconRoomCue?.currentLine, 'Bring the tools');
    if (includeRoom) {
      expect(room.state.roomState?.currentLine, 'Bring the tools');
    }
    expect(view.state.factCards.single.factText, 'Tools are in the shed');
    if (includeRoom) {
      expect(room.state.factCards.single.factText, 'Tools are in the shed');
    }
    final visibleMembers = [
      _authorId,
      if (scenario == RequestChangeReplay.enoughHelp || generation == 0)
        helperId,
      if (scenario == RequestChangeReplay.helperLeaves && generation < 2)
        kReplayOtherHelperId,
    ];
    expect(view.state.roomParticipants.map((p) => p.userId), visibleMembers);
    if (includeRoom) {
      expect(room.state.participants.map((p) => p.userId), visibleMembers);
    }
    for (final inbox in [homeInbox, watchingInbox]) {
      expect(inbox.state.projectionLoaded, isTrue);
      expect(inbox.state.projectionFailed, isFalse);
      expect(
        inbox.state.items.single.beacon?.title,
        'Request snapshot $generation',
      );
    }
    expect(myWork.state.attentionLoaded, isTrue);
    expect(
      myWork.state.nonArchivedCards.single.beacon.title,
      'Request snapshot $generation',
    );
    expect(
      children.state.active.items.single.title,
      'Visible child',
    );
    if (generation == 0 && includeRoom) {
      expect(room.state.messages, isEmpty);
    } else if (includeRoom) {
      expect(room.state.messages.single.id, 'notice-$generation');
      expect(
        room.state.messages.single.body,
        scenario == RequestChangeReplay.enoughHelp
            ? (statusOverride == BeaconStatus.open
                  ? 'Open'
                  : generation == 1
                  ? 'Enough help'
                  : 'Needs more help')
            : 'Helper left the discussion',
      );
      expect(
        attention
            .feedSession(_feedDestination)
            .pages[AttentionView.all]
            ?.items
            .single
            .body,
        'Change $generation',
      );
      expect(attention.surfaceSummarySnapshot.forYouDot, isTrue);
    }
  }

  Future<void> dispose() async {
    await children.close();
    await myWork.close();
    await watchingInbox.close();
    await homeInbox.close();
    await room.close();
    await view.close();
    await attention.dispose();
    await bridge.cancel();
    if (ownsInvalidations) await invalidations.dispose();
    await socket.close();
    await watermark.dispose();
    await accounts.dispose();
    await roomRepo.dispose();
    await viewRoom.dispose();
    await deskRoom.dispose();
    await forward.dispose();
    await deskForward.dispose();
    await beaconRepo.dispose();
    await inboxRepo.dispose();
  }
}

/// The per-consumer operation budget, including the Activity feed itself.
Map<String, int> readWaveCounts(OpenRequestObserverHarness client) => {
  ...client.readCounts(),
  'detail.BeaconFetchById': client.beaconRepo.fetchByIdCalls,
  'detail.BeaconParticipantList': client.viewRoom.fetchParticipantsCalls,
  'discussion.BeaconParticipantList':
      client.roomRepo.fetchParticipantsCallCount,
  'discussion.BeaconRoomReadWatermarks':
      client.roomRepo.fetchMainRoomReadWatermarksCallCount,
  'activity.AttentionFeed': client.attentionRepo.feedReads,
  'activity.AttentionSurfaceSummary': client.attentionRepo.summaryReads,
};

Map<String, int> _difference(Map<String, int> after, Map<String, int> before) =>
    {
      for (final entry in after.entries)
        entry.key: entry.value - before[entry.key]!,
    };

/// Replays change [generation] and waits until every refresh has settled.
Map<String, int> _replayChange(
  FakeAsync clock,
  OpenRequestObserverHarness client,
  int generation,
) {
  final before = client.readCounts();
  client.delivered.clear();
  client.setSnapshot(generation);
  client.scenario.deliver(
    clock: clock,
    socket: client.socket,
    beaconId: _beaconId,
    generation: generation,
  );
  clock.elapse(const Duration(seconds: 6));

  // The replay really is one change spread over ~2 s in separate flushes.
  final frames = client.scenario.viewerFrames(
    beaconId: _beaconId,
    generation: generation,
  );
  final flushes = client.delivered.map((d) => d.at).toSet();
  expect(
    [for (final d in client.delivered) (d.kind, d.aggregateId)],
    [
      for (final frame in frames)
        (
          RealtimeEntityKind.fromWire(
            (frame['payload'] as Map<String, dynamic>)['entity'],
          ),
          (frame['payload'] as Map<String, dynamic>)['id'],
        ),
    ],
  );
  expect(flushes, hasLength(frames.length));
  expect(
    client.delivered.last.at - client.delivered.first.at,
    greaterThanOrEqualTo(
      RequestChangeReplay.burstSpread - const Duration(milliseconds: 100),
    ),
  );

  client.expectSnapshot(generation);
  return _difference(client.readCounts(), before);
}

void main() {
  // Coverage: QA wave-2 RoomMessageList, RoomState, facts, participants,
  // read-watermarks, InboxFetch, MyWorkInit and child slices are measured
  // per consumer. BeaconChildren(active/finished/deleted) are separate groups.
  // Involvement has a separate trailing-forwards path: after fetch(),
  // BeaconViewCubit calls _refreshForwards when wasForwardsLoaded is true.
  // The mounted real-wire widget scenario lives in room_read_echo_refresh_test.
  // Sibling matrix: Request Discussion at bottom -> real-wire body test;
  // Activity and My Work -> local unread + one-wave tests (actor echo on/off
  // delivers the same frame: pinned by websocket_realtime_protocol_test);
  // Questions -> real PG scope + no-content-refetch/isolation tests here;
  // Questions entry -> no repeat access read; second tab -> unread convergence.
  // Native scroll-up/auto-follow, touch/keyboard and cross-tab browser delivery
  // need a web integration/Playwright network trace; widget tests cannot prove
  // those browser behaviours. Notification settlement echoes must be included
  // in that trace. The mounted replay pins the involvement pair: People load
  // owns read 1; one status-driven trailing forwards refresh owns read 2.
  // Fresh watching ids and an exact one-read delta prove this disposition.
  group(
    'Reading a newly received status line preserves one refresh per surface',
    () {
      for (final firstRead in [false, true]) {
        test('read marking does not reopen Request, Activity or My Work reads '
            'when the server publishes the ${firstRead ? 'first' : 'advanced'} '
            'read cursor', () {
          fakeAsync((clock) {
            final client = OpenRequestObserverHarness(
              RequestChangeReplay.enoughHelp,
              clock,
              echoReadMarks: true,
              readerHasSeenRow: !firstRead,
            );
            addTearDown(() {
              client.roomRepo.onSeen = null;
              return client.dispose();
            });
            clock.elapse(const Duration(seconds: 6));
            client.expectSnapshot(0);
            final before = readWaveCounts(client);
            client.setSnapshot(1);
            // A single committed transaction flushes its frames back to back.
            client.scenario
                .viewerFrames(beaconId: _beaconId, generation: 1)
                .forEach(client.socket.add);
            clock.elapse(const Duration(milliseconds: 2700));
            client.expectSnapshot(1);
            unawaited(client.room.markReadToBottom());
            clock.elapse(const Duration(milliseconds: 3300));
            expect(
              client.watermark.readThrough(_beaconId),
              client.room.state.messages.single.createdAt,
            );
            expect(client.room.state.unreadCount, 0);
            final delta = _difference(readWaveCounts(client), before);
            expect(
              delta['discussion.RoomMessageList'],
              1,
              reason: 'The displayed status line requires one message read',
            );
            expect(
              delta['home+watching.InboxFetch'],
              1,
              reason:
                  'Local read observation and confirmation are not new server content',
            );
            expect(delta['desk.MyWorkInit'], 1);
            expect(
              delta,
              everyReadAtMostOnce,
              reason:
                  'Read marking must not start another refresh wave: $delta',
            );
          });
        });
      }
    },
  );

  group('Local read watermarks recompute cards without remote reads', () {
    for (final surface in ['Activity', 'My Work']) {
      test(
        '$surface clears the discussion unread badge without fetching again',
        () {
          fakeAsync((clock) {
            final client = OpenRequestObserverHarness(
              RequestChangeReplay.enoughHelp,
              clock,
              initialGeneration: 1,
              withUnreadHints: true,
            );
            addTearDown(client.dispose);
            clock.elapse(const Duration(seconds: 6));
            int unread() => surface == 'Activity'
                ? client.homeInbox.state.items.single.roomHints!.roomUnreadCount
                : client.myWork.state.nonArchivedCards.single.roomUnreadCount;
            int reads() => surface == 'Activity'
                ? client.inboxRepo.fetchCallCount
                : client.myWorkRepo.fetchInitCallCount;
            expect(unread(), 1);
            final before = reads();
            unawaited(client.room.markReadToBottom());
            clock.elapse(const Duration(seconds: 6));
            expect(
              client.watermark.syncedAt(_beaconId),
              client.room.state.messages.single.createdAt,
            );
            expect(
              unread(),
              0,
              reason: 'The displayed card must recompute its unread badge',
            );
            expect(
              reads(),
              before,
              reason:
                  'Neither observing a local read nor confirming it requires a projection fetch',
            );
          });
        },
      );
    }
  });

  group('Read cursor hints preserve content projections', () {
    for (final scope in <String?>[null, 'CIquestions1']) {
      for (final event in ['insert', 'update']) {
        test(
          '${scope == null ? 'Discussion' : 'Questions'} read cursor $event '
          'does not reload Request, Questions access, Activity or My Work',
          () {
            fakeAsync((clock) {
              final client = OpenRequestObserverHarness(
                RequestChangeReplay.enoughHelp,
                clock,
                initialGeneration: 1,
                withUnreadHints: true,
              );
              addTearDown(client.dispose);
              final port = FakeLobbyPort(
                viewerId: client.viewerId,
                authorId: _authorId,
                offerers: {client.viewerId},
              )..messageCount = 7;
              final questions = BeaconLobbyEntryCubit(
                BeaconLobbyCase(port, client.realtime),
                beaconId: _beaconId,
              );
              addTearDown(questions.close);
              unawaited(questions.load());
              clock.elapse(const Duration(seconds: 6));
              client.expectSnapshot(1);
              expect(questions.state?.canRead, isTrue);
              final before = readWaveCounts(client);
              final accessBefore = port.calls
                  .where((call) => call == 'access')
                  .length;
              final at = client.room.state.messages.single.createdAt;
              client.socket.add(
                roomSeenReadCursorFrame(
                  readerId: client.viewerId,
                  beaconId: _beaconId,
                  at: at,
                  event: event,
                  threadItemId: scope,
                ),
              );
              clock.elapse(const Duration(seconds: 6));
              client.expectSnapshot(1);
              expect(questions.state?.messageCount, 7);
              final delta = _difference(readWaveCounts(client), before);
              expect(
                delta.values,
                everyElement(0),
                reason: 'A scoped read cursor is not a content change: $delta',
              );
              expect(
                port.calls.where((call) => call == 'access').length,
                accessBefore,
              );
              expect(
                client.homeInbox.state.items.single.roomHints!.roomUnreadCount,
                scope == null ? 0 : 1,
                reason: 'Questions cursors must never clear Discussion unread',
              );
              expect(
                client.myWork.state.nonArchivedCards.single.roomUnreadCount,
                scope == null ? 0 : 1,
              );
            });
          },
        );
      }
    }
  });

  group('A read in another tab clears unread without fetching projections', () {
    for (final firstRead in [true, false]) {
      test(
        'a second session converges Request, Activity and My Work unread from '
        'the server-side ${firstRead ? 'first' : 'advanced'} read cursor',
        () {
          fakeAsync((clock) {
            // Both tabs are the same signed-in reader with independent
            // session stores; only the server connects them.
            final first = OpenRequestObserverHarness(
              RequestChangeReplay.enoughHelp,
              clock,
              initialGeneration: 1,
              withUnreadHints: true,
            );
            final second = OpenRequestObserverHarness(
              RequestChangeReplay.enoughHelp,
              clock,
              initialGeneration: 1,
              withUnreadHints: true,
            );
            addTearDown(first.dispose);
            addTearDown(second.dispose);
            clock.elapse(const Duration(seconds: 6));
            expect(second.room.state.messages.single.id, 'notice-1');
            expect(second.room.state.unreadCount, 1);
            expect(
              second.homeInbox.state.items.single.roomHints!.roomUnreadCount,
              1,
            );
            expect(
              second.myWork.state.nonArchivedCards.single.roomUnreadCount,
              1,
            );
            final before = readWaveCounts(second);
            unawaited(first.room.markReadToBottom());
            clock.flushMicrotasks();
            final readAt = first.watermark.syncedAt(_beaconId)!;
            expect(
              second.watermark.readThrough(_beaconId),
              isNull,
              reason: 'Tabs must have independent session stores',
            );
            // The frame production fan-out delivers to every tab of the
            // reader (actor echo on or off) for the first tab's read.
            second.socket.add(
              roomSeenReadCursorFrame(
                readerId: second.viewerId,
                beaconId: _beaconId,
                at: readAt,
                event: firstRead ? 'insert' : 'update',
              ),
            );
            clock.elapse(const Duration(seconds: 6));
            expect(
              second.room.state.unreadCount,
              0,
              reason:
                  'The other tab read this message; its own read cursor must converge',
            );
            expect(second.watermark.syncedAt(_beaconId), readAt);
            expect(
              second.homeInbox.state.items.single.roomHints!.roomUnreadCount,
              0,
            );
            expect(
              second.myWork.state.nonArchivedCards.single.roomUnreadCount,
              0,
            );
            expect(
              _difference(readWaveCounts(second), before).values,
              everyElement(0),
              reason: 'A read cursor is not a content invalidation',
            );
          });
        },
      );
    }
  });

  // Disposition of QA's second BeaconInvolvementData: it is not caused by the
  // reader's room_seen echo. BeaconViewCubit.fetch() refreshes forwards
  // (and with them involvement) only when People/forwards were already
  // loaded, so an opened People list costs one involvement read per detail
  // refresh and an unopened one costs none.
  group(
    'A Request status change refreshes involvement only for an opened People list',
    () {
      for (final peopleOpen in [true, false]) {
        test(
          peopleOpen
              ? 'an opened People list gets one trailing involvement read and nothing from the read echo'
              : 'an unopened People list gets no involvement read',
          () {
            fakeAsync((clock) {
              final client = OpenRequestObserverHarness(
                RequestChangeReplay.enoughHelp,
                clock,
                echoReadMarks: true,
              );
              addTearDown(() {
                client.roomRepo.onSeen = null;
                return client.dispose();
              });
              clock.elapse(const Duration(seconds: 6));
              expect(client.view.state.beaconContextLoaded, isTrue);
              if (peopleOpen) {
                unawaited(client.view.loadForwards());
                clock.elapse(const Duration(seconds: 1));
                expect(client.view.state.forwardsLoaded, isTrue);
              }
              final opened = client.forward.involvementReads;
              expect(opened, peopleOpen ? 1 : 0);
              client.setSnapshot(1);
              client.scenario
                  .viewerFrames(beaconId: _beaconId, generation: 1)
                  .forEach(client.socket.add);
              clock.elapse(const Duration(milliseconds: 2700));
              final afterStatus = client.forward.involvementReads;
              expect(afterStatus - opened, peopleOpen ? 1 : 0);
              if (peopleOpen) {
                expect(
                  client.view.state.involvementWatchingIds,
                  contains('watcher-1'),
                  reason:
                      'The trailing read returns the new involvement snapshot',
                );
              }
              // The reader then reads the line and the server echoes room_seen.
              unawaited(client.room.markReadToBottom());
              clock.elapse(const Duration(seconds: 6));
              expect(client.room.state.unreadCount, 0);
              expect(
                client.forward.involvementReads,
                afterStatus,
                reason: 'A read cursor never reloads Request involvement',
              );
            });
          },
        );
      }
    },
  );

  group('An observer receives one refresh for a Request status change', () {
    for (final target in [BeaconStatus.enoughHelp, BeaconStatus.open]) {
      test(
        target == BeaconStatus.enoughHelp
            ? 'Enough help updates all mounted surfaces without repeated reads'
            : 'returning to Open updates all mounted surfaces without repeated reads',
        () {
          fakeAsync((clock) {
            final initialGeneration = target == BeaconStatus.open ? 1 : 0;
            final client = OpenRequestObserverHarness(
              RequestChangeReplay.enoughHelp,
              clock,
              initialGeneration: initialGeneration,
            );
            addTearDown(client.dispose);
            final questionsPort =
                FakeLobbyPort(
                    viewerId: _helperId,
                    authorId: _authorId,
                    offerers: {_helperId},
                  )
                  ..isHelper = true
                  ..messageCount = 7 + initialGeneration;
            final questions = BeaconLobbyEntryCubit(
              BeaconLobbyCase(questionsPort, client.realtime),
              beaconId: _beaconId,
            );
            addTearDown(questions.close);
            unawaited(questions.load());

            clock.elapse(const Duration(seconds: 8));
            client.expectSnapshot(initialGeneration);
            expect(questions.state?.canRead, isTrue);
            expect(questions.state?.isHelper, isTrue);
            expect(questions.state?.messageCount, 7 + initialGeneration);

            Map<String, int> reads() => {
              ...client.readCounts(),
              'detail.BeaconFetchById': client.beaconRepo.fetchByIdCalls,
              'questions.BeaconLobbyAccess': questionsPort.calls
                  .where((call) => call == 'access')
                  .length,
              'detail.BeaconParticipantList':
                  client.viewRoom.fetchParticipantsCalls,
              'discussion.BeaconParticipantList':
                  client.roomRepo.fetchParticipantsCallCount,
              'discussion.BeaconRoomReadWatermarks':
                  client.roomRepo.fetchMainRoomReadWatermarksCallCount,
            };

            final before = reads();
            final startedAt = clock.elapsed;
            client.delivered.clear();
            final generation = initialGeneration + 1;
            client.setSnapshot(generation, statusOverride: target);
            // A distinct server-returned projection proves that Questions
            // really re-read its access result. This count is a fixture
            // freshness marker, not a client rule about status or posting.
            questionsPort.messageCount = 7 + generation;

            // Use the server-derived observer envelopes and their existing
            // two-second delivery model. QA reports read waves around 0,
            // 2.4 and 6 seconds, NOT per-hint arrival times. Do not invent
            // late server hints from those read timestamps: whether the
            // server actually exceeds the 2.5-second window needs a capture.
            client.scenario.deliver(
              clock: clock,
              socket: client.socket,
              beaconId: _beaconId,
              generation: generation,
            );
            // Observe beyond the reported last wave and two further windows,
            // so a refresh that re-arms itself cannot escape measurement.
            clock.elapse(const Duration(seconds: 10));

            final frames = client.scenario.viewerFrames(
              beaconId: _beaconId,
              generation: generation,
            );
            expect(
              [
                for (final hint in client.delivered)
                  (
                    hint.kind,
                    hint.aggregateId,
                    hint.operation,
                    hint.actorUserId,
                    hint.childId,
                  ),
              ],
              [
                for (final frame in frames)
                  (
                    RealtimeEntityKind.fromWire(
                      (frame['payload'] as Map<String, dynamic>)['entity'],
                    ),
                    (frame['payload'] as Map<String, dynamic>)['id'],
                    RealtimeOperation.values.byName(
                      (frame['payload'] as Map<String, dynamic>)['event']
                          as String,
                    ),
                    (frame['payload'] as Map<String, dynamic>)['actor_user_id'],
                    (frame['payload'] as Map<String, dynamic>)['message_id'],
                  ),
              ],
              reason:
                  'Every observer envelope must retain its identity and order',
            );
            expect(
              client.delivered.map((hint) => hint.at).toSet(),
              hasLength(frames.length),
            );
            expect(
              client.delivered.last.at - client.delivered.first.at,
              greaterThanOrEqualTo(const Duration(milliseconds: 1900)),
            );
            expect(clock.elapsed - startedAt, const Duration(seconds: 12));

            // Fresh visible snapshots are required before considering the
            // read budget: suppressing all refreshes must fail this test.
            client.expectSnapshot(generation, statusOverride: target);
            expect(
              client.myWork.state.nonArchivedCards.single.beacon.status,
              target,
            );
            for (final inbox in [client.homeInbox, client.watchingInbox]) {
              expect(inbox.state.items.single.beacon?.status, target);
            }
            expect(questions.state?.canRead, isTrue);
            expect(
              questions.state?.messageCount,
              7 + generation,
              reason:
                  'Questions must show the refreshed server access snapshot',
            );
            final delta = _difference(reads(), before);
            expect(
              delta['questions.BeaconLobbyAccess'],
              1,
              reason: 'Questions must refresh its access exactly once',
            );
            // A surface owns a budget of operations, not one budget per
            // cubit or child group. Different consumers may each read once;
            // only another read by the same consumer is a duplicate wave.
            // Include every tracked detail/discussion slice so a repeated
            // partial refresh cannot hide behind a single BeaconFetchById.
            final surfaceReads = <String, Map<String, int>>{
              'Request detail': {
                for (final entry in delta.entries)
                  if (entry.key.startsWith('detail.') ||
                      entry.key.startsWith('discussion.'))
                    entry.key: entry.value,
              },
              'Questions access': {
                'questions.BeaconLobbyAccess':
                    delta['questions.BeaconLobbyAccess']!,
              },
              'child Requests': {
                for (final entry in delta.entries)
                  if (entry.key.startsWith('children.')) entry.key: entry.value,
              },
              'My Work': {'desk.MyWorkInit': delta['desk.MyWorkInit']!},
              'Inbox': {
                'home+watching.InboxFetch': delta['home+watching.InboxFetch']!,
              },
            };
            // Reading active/finished/deleted once each is ONE hierarchy
            // refresh, as is reading only the active slice. Unused operations
            // may stay at zero. The maximum multiplicity detects a repeated
            // full refresh or repeated partial refresh without adding
            // independent reads or demanding every child group be fetched.
            expect(
              {
                for (final surface in surfaceReads.entries)
                  surface.key: surface.value.values.fold<int>(
                    0,
                    (largest, count) => count > largest ? count : largest,
                  ),
              },
              {
                'Request detail': 1,
                'Questions access': 1,
                'child Requests': 1,
                'My Work': 1,
                'Inbox': 1,
              },
              reason:
                  'One author status change must converge every observer '
                  'surface without repeated reads. Surface budgets: '
                  '$surfaceReads; '
                  'delivered hints: ${client.delivered}',
            );
            expect(
              delta,
              everyReadAtMostOnce,
              reason: 'Each consumer may issue each read at most once: $delta',
            );
          });
        },
      );
    }
  });

  group('An open Request refreshes each surface once per server change', () {
    for (final scenario in RequestChangeReplay.values) {
      test(
        scenario == RequestChangeReplay.enoughHelp
            ? 'a helper sees Enough help with at most one read per surface, '
                  'and a later status change refreshes again'
            : 'an author sees a helper leave with at most one read per '
                  'surface, and a later withdrawal refreshes again',
        () {
          fakeAsync((clock) {
            final client = OpenRequestObserverHarness(scenario, clock);
            addTearDown(client.dispose);
            // Finish initial loads, before measuring invalidation-driven I/O.
            clock.elapse(const Duration(seconds: 6));
            expect(client.view.state.beaconContextLoaded, isTrue);
            expect(client.room.state.status, isA<StateIsSuccess>());
            client.expectSnapshot(0);

            // Server fan-out: the viewer gets only hints addressed to them
            // (not the leaver's own inbox row), with server-side ids.
            expect(
              [
                for (final frame in scenario.viewerFrames(
                  beaconId: _beaconId,
                  generation: 1,
                ))
                  (
                    (frame['payload'] as Map<String, dynamic>)['entity'],
                    (frame['payload'] as Map<String, dynamic>)['id'],
                  ),
              ],
              switch (scenario) {
                RequestChangeReplay.enoughHelp => [
                  ('beacon', _beaconId),
                  ('beacon_hierarchy', _beaconId),
                  ('activity_event', _beaconId),
                  ('room_message', _beaconId),
                  ('notification', _helperId),
                ],
                RequestChangeReplay.helperLeaves => [
                  ('help_offer', _beaconId),
                  ('room_message', _beaconId),
                  ('activity_event', _beaconId),
                  ('participant', _beaconId),
                  ('beacon_hierarchy', _beaconId),
                  ('notification', _authorId),
                ],
              },
            );

            final firstBurst = _replayChange(clock, client, 1);
            // The first window is over. Another independent change must
            // fetch again (convergence to snapshot 2 needs fresh reads);
            // permanent suppression is not coalescing.
            final laterBurst = _replayChange(clock, client, 2);

            expect(
              {'first change': firstBurst, 'later change': laterBurst},
              {
                'first change': everyReadAtMostOnce,
                'later change': everyReadAtMostOnce,
              },
              reason:
                  'Each surface issues each read operation at most once per '
                  'server change (each child group counts separately; the '
                  'two mounted inbox consumers share one InboxFetch). '
                  'Observed: first $firstBurst, later $laterBurst',
            );
          });
        },
      );
    }
  });
}

final everyReadAtMostOnce = predicate<Map<String, int>>(
  (reads) => reads.values.every((n) => n <= 1),
  'every read operation at most once',
);
