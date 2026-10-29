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
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

import '../../domain/attention/attention_case_test_support.dart';
import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';
import '../beacon_threads/room_cubit_fakes.dart' as discussion;
import '../beacon_view/beacon_view_case_test_support.dart' as detail;
import '../block/support/controllable_block_case.dart';
import '../inbox/inbox_case_test.dart' as activity;
import '../my_work/my_work_test_support.dart' as desk;
import 'request_change_hint_replay.dart';

const _beaconId = discussion.kRoomCubitFakeBeaconId;
const _authorId = kReplayAuthorId;
const _helperId = kReplayHelperId;
const _feedDestination = AttentionFeedDestinationId.activityStream;

class _ForwardSnapshots extends detail.FakeBeaconViewForwardRepository {
  @override
  Stream<String> get forwardCommandCompleted => const Stream.empty();
}

class _DiscussionSnapshots extends discussion.FakeBeaconThreadsRepository {
  _DiscussionSnapshots(String userId) : super(userId: userId);

  int roomStateReads = 0;

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

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async {
    return AttentionFeed(
      summary: AttentionSummary(unreadTotal: receipts.length),
      page: AttentionFeedPage(items: receipts),
    );
  }

  @override
  Future<AttentionSurfaceSummary> surfaceSummary() async {
    return AttentionSurfaceSummary(forYouDot: receipts.isNotEmpty);
  }
}

/// Real cubits/cases and the real websocket invalidation buffer. Only the
/// repository I/O is replaced. The adapter below is the existing repository
/// seam: BeaconRepository emits RepositoryEventInvalidate, ForwardRepository
/// emits HelpOfferInvalidated, and rooms use fromRealtimeChange. It performs
/// no batching, read suppression or timing of its own.
class _OpenClient {
  _OpenClient(this.scenario, this.clock) {
    registerProfile();
    invalidations = InvalidationService.forTesting(socket.stream);
    realtime = RealtimeSyncCase(invalidations);
    roomRepo = _DiscussionSnapshots(viewerId);
    final watermark = RoomReadWatermarkStore.testing();
    final roomCase = BeaconThreadsCase(
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
        roomRepo.emitInvalidation(
          roomHint.entityType,
          operation: roomHint.operation,
          messageId: roomHint.messageId,
          paint: roomHint.paint,
        );
      }
    });
    setSnapshot(0);
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
    homeInbox = InboxCubit(
      userId: viewerId,
      inboxCase: inboxCase,
      effects: FakeUiEffectPort(),
    );
    watchingInbox = InboxCubit(
      userId: viewerId,
      inboxCase: inboxCase,
      effects: FakeUiEffectPort(),
    );
    myWork = MyWorkCubit(
      userId: viewerId,
      myWorkCase: desk.buildTestMyWorkCase(
        repo: myWorkRepo,
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

  final RequestChangeReplay scenario;
  final FakeAsync clock;
  String get viewerId => scenario.viewerId;
  String actorFor(int generation) => scenario.actorFor(generation);
  void registerProfile() => discussion.registerRoomCubitProfileCubit(viewerId);

  final socket = StreamController<Map<String, dynamic>>.broadcast();
  late final InvalidationService invalidations;
  late final RealtimeSyncCase realtime;
  late final StreamSubscription<RealtimeEntityChange> bridge;

  /// What InvalidationService hands to the app, and when.
  final delivered =
      <({Duration at, RealtimeEntityKind kind, String aggregateId})>[];
  final beaconRepo = detail.TrackingBeaconRepository();
  final forward = _ForwardSnapshots();
  final deskForward = desk.FakeForwardRepository();
  final viewRoom = detail.FakeBeaconViewRoomRepository();
  final deskRoom = desk.FakeBeaconThreadsRepository();
  late final _DiscussionSnapshots roomRepo;
  final viewFacts = detail.FakeBeaconViewFactCardRepository();
  final roomFacts = detail.FakeBeaconViewFactCardRepository();
  final inboxRepo = activity.FakeInboxRepository();
  final myWorkRepo = desk.FakeMyWorkRepository();
  final attentionRepo = _AttentionSnapshots();
  final accounts = AttentionCaseTestAccounts();
  late final AttentionCase attention;
  final hierarchyRepo = FakeBeaconHierarchyRepositoryPort();
  final childReads = <BeaconHierarchyChildGroup, int>{};
  late final BeaconViewCubit view;
  late final RoomCubit room;
  late final InboxCubit homeInbox;
  late final InboxCubit watchingInbox;
  late final MyWorkCubit myWork;
  late final BeaconHierarchyCubit children;

  void setSnapshot(int generation) {
    final status =
        scenario == RequestChangeReplay.helperLeaves || generation == 0
        ? BeaconStatus.open
        : generation == 1
        ? BeaconStatus.enoughHelp
        : BeaconStatus.needsMoreHelp;
    final beacon = Beacon(
      id: _beaconId,
      title: 'Request snapshot $generation',
      author: const Profile(id: _authorId),
      status: status,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026, 1, 1, 0, 0, generation),
    );
    beaconRepo.fetchByIdHandler = (_) async => beacon;
    viewRoom.roomState = BeaconRoomState(
      beaconId: _beaconId,
      updatedAt: DateTime.utc(2026),
      currentLine: 'Bring the tools',
    );
    final participants = [
      for (final userId in [
        _authorId,
        if (scenario == RequestChangeReplay.enoughHelp || generation == 0)
          _helperId,
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
                  ? (generation == 1 ? 'Enough help' : 'Needs more help')
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
    inboxRepo.fetchResult = [
      InboxItem(
        beaconId: _beaconId,
        latestForwardAt: DateTime.utc(2026),
        status: InboxItemStatus.watching,
        beacon: beacon,
      ),
    ];
    myWorkRepo.initResult = (
      authoredNonArchived: viewerId == _authorId ? [beacon] : const <Beacon>[],
      helpOfferedNonArchived: [
        if (viewerId == _helperId)
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

  void expectSnapshot(int generation) {
    expect(view.state.loadError, isNull);
    expect(room.state.loadError, isNull);
    expect(view.state.beacon.title, 'Request snapshot $generation');
    expect(
      view.state.beacon.status,
      generation == 0 || scenario == RequestChangeReplay.helperLeaves
          ? BeaconStatus.open
          : generation == 1
          ? BeaconStatus.enoughHelp
          : BeaconStatus.needsMoreHelp,
    );
    expect(view.state.beaconRoomCue?.currentLine, 'Bring the tools');
    expect(room.state.roomState?.currentLine, 'Bring the tools');
    expect(view.state.factCards.single.factText, 'Tools are in the shed');
    expect(room.state.factCards.single.factText, 'Tools are in the shed');
    final visibleMembers = [
      _authorId,
      if (scenario == RequestChangeReplay.enoughHelp || generation == 0)
        _helperId,
      if (scenario == RequestChangeReplay.helperLeaves && generation < 2)
        kReplayOtherHelperId,
    ];
    expect(view.state.roomParticipants.map((p) => p.userId), visibleMembers);
    expect(room.state.participants.map((p) => p.userId), visibleMembers);
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
    if (generation == 0) {
      expect(room.state.messages, isEmpty);
    } else {
      expect(room.state.messages.single.id, 'notice-$generation');
      expect(
        room.state.messages.single.body,
        scenario == RequestChangeReplay.enoughHelp
            ? (generation == 1 ? 'Enough help' : 'Needs more help')
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
    await invalidations.dispose();
    await socket.close();
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

Map<String, int> _difference(Map<String, int> after, Map<String, int> before) =>
    {
      for (final entry in after.entries)
        entry.key: entry.value - before[entry.key]!,
    };

/// Replays change [generation] and waits until every refresh has settled.
Map<String, int> _replayChange(
  FakeAsync clock,
  _OpenClient client,
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
            final client = _OpenClient(scenario, clock);
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
