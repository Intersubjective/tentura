import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fake_async/fake_async.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_read_watermark.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/util/burst_coalescer.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:logging/logging.dart';
import 'package:tentura/features/beacon_lobby/ui/bloc/beacon_lobby_entry_cubit.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import '../beacon_lobby/fake_lobby_port.dart';
import '../realtime/open_request_change_refresh_test.dart' as observer;
import '../inbox/inbox_case_test.dart' show FakeInboxRepository;
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../support/phone_surface.dart';
import '../realtime/read_cursor_server_frames.dart';
import '../realtime/request_change_hint_replay.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';
import 'support/room_hint_wire_harness.dart';

typedef _Delivery = ({int id, String observer, String trigger});

class _TracedInboxRepository extends FakeInboxRepository {
  final trace = <String>[];
  final starts = <({_Delivery? delivery, bool overlapsRead})>[];
  final deliveries = <_Delivery>[];
  _Delivery? activeDelivery;
  _Delivery? activeRefresh;
  int _deliveryId = 0;
  int _pendingReads = 0;
  void Function()? onNextFetch;

  R deliver<R>(String observer, Object? event, R Function() callback) {
    final trigger = switch (event) {
      RealtimeEntityChange change => 'realtime:${change.kind.name}',
      BeaconRoomInvalidation hint => 'room:${hint.entityType.name}',
      RealtimeCatchUp catchUp => 'catch-up:${catchUp.reason.name}',
      RoomReadWatermarkKey _ => 'watermark',
      _ => null,
    };
    if (trigger == null) return callback();
    final delivery = (id: ++_deliveryId, observer: observer, trigger: trigger);
    deliveries.add(delivery);
    trace.add('deliver:$delivery');
    final previous = activeDelivery;
    activeDelivery = delivery;
    try {
      return callback();
    } finally {
      activeDelivery = previous;
    }
  }

  @override
  Future<List<InboxItem>> fetch({required String userId}) {
    final origin = activeRefresh ?? activeDelivery;
    starts.add((
      delivery: origin,
      overlapsRead: _pendingReads > 0,
    ));
    trace.add('InboxFetch:${starts.last}');
    _pendingReads++;
    final started = onNextFetch;
    onNextFetch = null;
    started?.call();
    return super.fetch(userId: userId).whenComplete(() {
      _pendingReads--;
      trace.add('response:${origin?.observer ?? "initial load"}');
    });
  }
}

/// Message HTTP -> Ferry -> real repository -> case -> cubit -> body.
/// Only unrelated room slices and the mark-seen server write are faked.
/// Unlike the old refresh replay, successful mark-seen writes send their
/// private room_seen frame back through the real invalidation service.
class _ReadEchoRoom extends observer.DiscussionSnapshots {
  _ReadEchoRoom(
    this.wire, {
    required bool readerHasSeenRow,
    String? scope,
  }) : _persistedScopes = {
         if (readerHasSeenRow) scope ?? RequestThread.generalId,
       },
       super(roomHintWireViewerId);

  @override
  Stream<BeaconRoomInvalidation> get beaconRoomInvalidations =>
      wire.repository.beaconRoomInvalidations;

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) {
    fetchMessagesCallCount++;
    return wire.repository.fetchMessages(
      beaconId: beaconId,
      beforeIso: beforeIso,
      threadItemId: threadItemId,
    );
  }

  @override
  Future<List<RoomReadWatermark>> fetchMainRoomReadWatermarks(String beaconId) {
    fetchMainRoomReadWatermarksCallCount++;
    return wire.repository.fetchMainRoomReadWatermarks(beaconId);
  }

  final RoomHintWire wire;
  final Set<String> _persistedScopes;
  final readMarks = <DateTime>[];
  int threadReads = 0;

  @override
  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async {
    roomStateReads++;
    return BeaconRoomState(
      beaconId: beaconId,
      updatedAt: DateTime.utc(2026),
      currentLine: 'Bring the tools',
    );
  }

  @override
  Future<List<RequestThread>> fetchThreads(String beaconId) async {
    threadReads++;
    return [
      RequestThread(
        threadId: RequestThread.generalId,
        kind: RequestThreadKind.general,
        messageCount: wireServerMessageCount,
        unreadCount: 1,
      ),
    ];
  }

  int wireServerMessageCount = 0;

  @override
  Future<DateTime> markThreadSeen({
    required String beaconId,
    required String threadId,
    required DateTime readThroughAt,
  }) async {
    readMarks.add(readThroughAt);
    // The server persists the cursor and sends this tab the frame its trigger
    // NOTIFY produces through production fan-out (pinned by the server tests,
    // actor echo on or off; first read of a scope = INSERT) over the real wire.
    wire.socket.frames.add(
      jsonEncode(
        roomSeenReadCursorFrame(
          readerId: roomHintWireViewerId,
          beaconId: beaconId,
          at: readThroughAt,
          event: _persistedScopes.add(threadId) ? 'insert' : 'update',
          threadItemId: threadId == RequestThread.generalId ? null : threadId,
        ),
      ),
    );
    return readThroughAt;
  }
}

Future<void> _wait(WidgetTester tester, Duration duration) async {
  await tester.runAsync(() => Future<void>.delayed(duration));
  await tester.pump();
  // Let BasicChatBody's initial/auto-follow post-frame callback reach the
  // actual markReadToBottom path, without calling it from the test.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

typedef _Observer = ({
  observer.OpenRequestObserverHarness client,
  _ReadEchoRoom repo,
  RoomHintWire wire,
  RoomHintWireServer server,
  RoomReadWatermarkStore watermark,
  ThreadsCubit threads,
  BeaconLobbyEntryCubit questions,
  FakeLobbyPort questionsPort,
  List<Map<String, dynamic>> previousRows,
});

/// Mounts the real BeaconRoomBody of an observer of [kReplayAuthorId]'s
/// Request with every surface QA counted, on the real message wire.
Future<_Observer> _mountObserver(
  WidgetTester tester, {
  required String? scope,
  required bool firstRead,
  int previousCount = 1,
  FakeInboxRepository? inboxRepository,
  Zone? homeInboxZone,
  Zone? watchingInboxZone,
}) async {
  await usePhoneSurface(tester);
  await GetIt.I.reset();
  addTearDown(GetIt.I.reset);
  registerRoomCubitProfileCubit(roomHintWireViewerId);
  GetIt.I
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());
  final lastPreviousAt = DateTime.utc(2026, 10, 31, 11);
  final previousRows = [
    for (var i = previousCount - 1; i >= 0; i--)
      roomHintWireMessageRow(
        id: 'Mprevious${(i + 1).toString().padLeft(3, '0')}',
        authorId: kReplayAuthorId,
        authorTitle: 'Автор',
        createdAt: lastPreviousAt
            .subtract(Duration(minutes: i))
            .toIso8601String(),
        body: i == 0 ? 'Обсуждаем встречу' : 'Сообщение номер $i',
      ),
  ];
  if (scope != null) {
    for (final row in previousRows) {
      row['threadItemId'] = scope;
    }
  }
  final server = RoomHintWireServer()..messageRows = [...previousRows];
  final wire = (await tester.runAsync(() => RoomHintWire.start(server)))!;
  addTearDown(() => tester.runAsync(wire.close));
  final repo = _ReadEchoRoom(
    wire,
    readerHasSeenRow: !firstRead,
    scope: scope,
  );
  final watermark = RoomReadWatermarkStore.testing();
  if (!firstRead) {
    watermark.confirmSynced(
      kRoomCubitFakeBeaconId,
      lastPreviousAt,
      threadId: scope ?? RequestThread.generalId,
    );
  }
  repo.wireServerMessageCount = previousCount;
  late observer.OpenRequestObserverHarness client;
  late ThreadsCubit threads;
  late BeaconLobbyEntryCubit questions;
  final questionsPort = FakeLobbyPort(
    viewerId: roomHintWireViewerId,
    authorId: kReplayAuthorId,
    offerers: {roomHintWireViewerId},
  )..messageCount = 7;
  await tester.runAsync(() async {
    client = observer.OpenRequestObserverHarness(
      RequestChangeReplay.enoughHelp,
      FakeAsync(),
      discussionRepository: repo,
      invalidationService: wire.realtime,
      watermarkStore: watermark,
      viewerOverride: roomHintWireViewerId,
      threadItemId: scope,
      withUnreadHints: true,
      inboxRepository: inboxRepository,
      homeInboxZone: homeInboxZone,
      watchingInboxZone: watchingInboxZone,
    );
    await awaitRoomCubitLoad(client.room);
    client.room.syncBeaconStatus(BeaconStatus.open);
    threads = ThreadsCubit(
      beaconId: kRoomCubitFakeBeaconId,
      beaconThreadsCase: client.roomCase,
    );
    await threads.fetch();
    expect(threads.state.loadError, isNull);
    questions = BeaconLobbyEntryCubit(
      BeaconLobbyCase(questionsPort, client.realtime),
      beaconId: kRoomCubitFakeBeaconId,
    );
    await questions.load();
    // Opening People owns the first involvement read. A later status
    // refresh owns the second via the existing trailing forwards refresh.
    if (!client.view.state.beaconContextLoaded) {
      await client.view.stream
          .firstWhere((s) => s.beaconContextLoaded)
          .timeout(const Duration(seconds: 3));
    }
    await client.view.loadForwards();
    expect(client.view.state.forwardsLoaded, isTrue);
    expect(client.forward.involvementReads, 1);
    expect(client.view.state.involvementWatchingIds, contains('watcher-0'));
  });
  final homeAttention = (await tester.runAsync(
    () async => HomeAttentionCubit(
      client.attention,
      client.accounts,
      Logger('observer attention'),
    ),
  ))!;
  addTearDown(() => tester.runAsync(homeAttention.close));
  addTearDown(() => tester.runAsync(client.dispose));
  addTearDown(() => tester.runAsync(threads.close));
  addTearDown(() => tester.runAsync(questions.close));
  final presence = RoomBodyHarnessPresenceCubit();
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<RoomCubit>.value(value: client.room),
        BlocProvider<HomeAttentionCubit>.value(value: homeAttention),
        BlocProvider<BeaconViewCubit>.value(value: client.view),
        BlocProvider<InboxCubit>.value(value: client.homeInbox),
        BlocProvider<MyWorkCubit>.value(value: client.myWork),
        BlocProvider<BeaconHierarchyCubit>.value(value: client.children),
        BlocProvider<ProfileCubit>.value(value: GetIt.I<ProfileCubit>()),
        BlocProvider<PresenceCubit>.value(value: presence),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: BeaconRoomBody(
              enableComposer: false,
              capabilities: scope == null
                  ? const RoomCapabilities.request()
                  : const RoomCapabilities.questions(),
            ),
          ),
        ),
      ),
    ),
  );
  await _wait(tester, const Duration(milliseconds: 100));
  expect(client.room.state.messages.last.body, 'Обсуждаем встречу');
  expect(
    find.textContaining('Обсуждаем встречу', findRichText: true),
    findsOneWidget,
  );
  expect(
    repo.readMarks,
    firstRead ? [lastPreviousAt] : isEmpty,
    reason: firstRead
        ? "Opening the room at the bottom creates the reader's first cursor"
        : 'Everything shown was already read',
  );
  client.expectSnapshot(0, includeRoom: false);
  return (
    client: client,
    repo: repo,
    wire: wire,
    server: server,
    watermark: watermark,
    threads: threads,
    questions: questions,
    questionsPort: questionsPort,
    previousRows: previousRows,
  );
}

Map<String, int> _reads(_Observer o) => {
  ...observer.readWaveCounts(o.client),
  'discussion.BeaconThreadsList': o.repo.threadReads,
  'detail.BeaconInvolvementData': o.client.forward.involvementReads,
  'questions.BeaconLobbyAccess': o.questionsPort.calls
      .where((c) => c == 'access')
      .length,
};

/// The author's status change: the server now lists the system line and the
/// author's committed transaction reaches this tab back to back.
Future<DateTime> _deliverStatusChange(
  WidgetTester tester,
  _Observer o, {
  required String? scope,
}) async {
  o.client.setSnapshot(1);
  o.questionsPort.messageCount = 8;
  final at = DateTime.utc(2026, 10, 31, 12);
  final row =
      roomHintWireMessageRow(
        id: 'notice-1',
        authorId: kReplayAuthorId,
        authorTitle: 'Автор',
        createdAt: at.toIso8601String(),
      )..addAll({
        'systemMessageKind': BeaconRoomSystemMessageKind.statusChanged,
        'systemPayloadJson': jsonEncode(_statusPayload),
      });
  if (scope != null) row['threadItemId'] = scope;
  o.server.messageRows = [...o.previousRows, row];
  o.repo.wireServerMessageCount = o.previousRows.length + 1;
  await tester.runAsync(() async {
    for (final frame in RequestChangeReplay.enoughHelp.viewerFrames(
      beaconId: kRoomCubitFakeBeaconId,
      generation: 1,
    )) {
      // The replay's observer is this signed-in account on the wire.
      final payload = frame['payload'] as Map<String, dynamic>;
      if (payload['entity'] == 'notification') {
        payload['id'] = roomHintWireViewerId;
      }
      o.wire.socket.frames.add(jsonEncode(frame));
    }
  });
  return at;
}

final _statusPayload = {
  'version': 1,
  'fromStatus': BeaconStatus.open.smallintValue,
  'toStatus': BeaconStatus.enoughHelp.smallintValue,
  'reason': 'author_status_change',
};

Map<String, int> _oneWave(String? scope) => {
  'detail.BeaconRoomStateGet': 1,
  'discussion.BeaconRoomStateGet': scope == null ? 1 : 0,
  'discussion.RoomMessageList': 1,
  'detail.BeaconFactCardList': 1,
  'discussion.BeaconFactCardList': scope == null ? 1 : 0,
  'home+watching.InboxFetch': 1,
  'desk.MyWorkInit': 1,
  'children.BeaconChildren(active)': 1,
  'children.BeaconChildren(finished)': 1,
  'children.BeaconChildren(deleted)': 1,
  'detail.BeaconFetchById': 1,
  'detail.BeaconParticipantList': 1,
  'discussion.BeaconParticipantList': scope == null ? 1 : 0,
  'discussion.BeaconRoomReadWatermarks': scope == null ? 1 : 0,
  'activity.AttentionFeed': 1,
  'activity.AttentionSurfaceSummary': 1,
  'discussion.BeaconThreadsList': 1,
  'detail.BeaconInvolvementData': 1,
  'questions.BeaconLobbyAccess': 1,
};

Map<String, int> _delta(Map<String, int> after, Map<String, int> before) => {
  for (final key in before.keys) key: after[key]! - before[key]!,
};

ScrollPosition _chatScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(BasicChatBody),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final holdResponse in [true, false]) {
    testWidgets(
      'Home and Watching refresh once per status change across event-loop '
      'turns with ${holdResponse ? "an unfinished" : "an already completed"} '
      'response',
      (tester) async {
        final inbox = _TracedInboxRepository();
        final gates = (await tester.runAsync(
          () async => (
            watchingDue: Completer<void>(),
            homeTurn: Completer<void>(),
            started: Completer<void>(),
            echo: Completer<void>(),
            response: Completer<List<InboxItem>>(),
          ),
        ))!;
        var watchingTimerScheduled = false;
        void Function()? dispatchWatching;
        Object? lastHomeTurn;
        final zones = (await tester.runAsync(() async {
          Zone observerZone(String surface) => Zone.current.fork(
            specification: ZoneSpecification(
              // Scope attribution to the actual typed subscriber invocation.
              // Synchronous map/where/merge delivery retains this token; an
              // unrelated later event cannot replace a timer's cause.
              registerUnaryCallback: <R, T>(self, parent, zone, callback) =>
                  parent.registerUnaryCallback(
                    zone,
                    (T event) =>
                        inbox.deliver(surface, event, () => callback(event)),
                  ),
              createTimer: (self, parent, zone, duration, callback) {
                if (surface == 'home' &&
                    duration == Duration.zero &&
                    inbox.activeRefresh != null) {
                  final turn = Object();
                  lastHomeTurn = turn;
                  return parent.createTimer(zone, duration, () {
                    callback();
                    if (identical(lastHomeTurn, turn) &&
                        !gates.homeTurn.isCompleted) {
                      inbox.trace.add('home event-loop turn completed');
                      gates.homeTurn.complete();
                    }
                  });
                }
                if (duration != BurstCoalescer.window) {
                  return parent.createTimer(zone, duration, callback);
                }
                final delivery = inbox.activeDelivery;
                void refresh() {
                  final previous = inbox.activeRefresh;
                  inbox.activeRefresh = delivery;
                  inbox.trace.add('refresh:$surface <- $delivery');
                  try {
                    callback();
                  } finally {
                    inbox.activeRefresh = previous;
                  }
                  if (surface == 'home' &&
                      lastHomeTurn == null &&
                      !gates.homeTurn.isCompleted) {
                    gates.homeTurn.complete();
                  }
                }

                if (surface != 'watching') {
                  return parent.createTimer(zone, duration, refresh);
                }
                watchingTimerScheduled = true;
                return parent.createTimer(zone, duration, () {
                  // The real timer has become due. Suspend this one pending
                  // callback while Home's real next-turn timers run. The test
                  // creates no zero-duration timers and adds no timing slack.
                  dispatchWatching = refresh;
                  if (!gates.watchingDue.isCompleted) {
                    gates.watchingDue.complete();
                  }
                });
              },
            ),
          );
          return (
            home: observerZone('home'),
            watching: observerZone('watching'),
          );
        }))!;
        final o = await _mountObserver(
          tester,
          scope: null,
          firstRead: true,
          inboxRepository: inbox,
          homeInboxZone: zones.home,
          watchingInboxZone: zones.watching,
        );
        final before = inbox.fetchCallCount;
        inbox.trace.clear();
        inbox.starts.clear();
        inbox.deliveries.clear();
        final homeUpdates = <InboxState>[];
        final watchingUpdates = <InboxState>[];
        final subscriptions = (await tester.runAsync(
          () async => (
            home: o.client.homeInbox.stream.listen(homeUpdates.add),
            watching: o.client.watchingInbox.stream.listen(watchingUpdates.add),
            hints: o.wire.realtime.entityChanges.listen((change) {
              inbox.trace.add('wire:${change.kind.name}');
              if (change.kind == RealtimeEntityKind.roomSeen &&
                  change.readCursor?.lastSeenAt ==
                      DateTime.utc(2026, 10, 31, 12) &&
                  !gates.echo.isCompleted) {
                gates.echo.complete();
              }
            }),
          ),
        ))!;
        addTearDown(subscriptions.home.cancel);
        addTearDown(subscriptions.watching.cancel);
        addTearDown(subscriptions.hints.cancel);
        inbox.onNextFetch = gates.started.complete;
        if (holdResponse) inbox.pendingFetches.add(gates.response);
        addTearDown(() {
          if (!gates.response.isCompleted)
            gates.response.complete(inbox.fetchResult);
        });
        final at = await _deliverStatusChange(tester, o, scope: null);
        final expectedProjection = [
          (
            beaconId: kRoomCubitFakeBeaconId,
            title: 'Request snapshot 1',
            context: '',
            status: BeaconStatus.enoughHelp,
            unread: 0,
          ),
        ];
        Object projection(InboxState state) => [
          for (final item in state.items)
            (
              beaconId: item.beaconId,
              title: item.beacon?.title,
              context: item.context,
              status: item.beacon?.status,
              unread: item.roomHints?.roomUnreadCount,
            ),
        ];
        Future<void> updated(InboxCubit cubit) async {
          if (cubit.state.items.single.beacon?.title != 'Request snapshot 1') {
            await cubit.stream
                .firstWhere(
                  (s) => s.items.single.beacon?.title == 'Request snapshot 1',
                )
                .timeout(const Duration(seconds: 3));
          }
        }

        await tester.runAsync(() async {
          await gates.started.future.timeout(const Duration(seconds: 5));
          if (watchingTimerScheduled) {
            await gates.watchingDue.future.timeout(const Duration(seconds: 3));
            await gates.homeTurn.future.timeout(const Duration(seconds: 3));
            if (!holdResponse) {
              await updated(o.client.homeInbox);
              expect(projection(o.client.homeInbox.state), expectedProjection);
              // A duplicate read returns distinguishable data. No new hint
              // was published: Watching still owes this wave's first result.
              inbox.fetchResult = [
                for (final item in inbox.fetchResult)
                  item.copyWith(context: 'A later server response'),
              ];
              inbox.trace.add(
                'home applied first response before Watching callback',
              );
            }
            dispatchWatching!();
          }
          if (holdResponse) gates.response.complete(inbox.fetchResult);
          await updated(o.client.homeInbox);
          await updated(o.client.watchingInbox);
        });
        // Capture each applied result before the chat publishes its cursor.
        final applied = {
          'home': projection(o.client.homeInbox.state),
          'watching': projection(o.client.watchingInbox.state),
        };
        int statusUpdates(List<InboxState> states) => states
            .where(
              (s) =>
                  s.projectionLoaded &&
                  s.items.single.beacon?.title == 'Request snapshot 1',
            )
            .length;
        final updates = {
          'home': statusUpdates(homeUpdates),
          'watching': statusUpdates(watchingUpdates),
        };
        // The room has its own request. An Inbox refresh completing does not
        // mean the status message is ready to render and auto-read yet.
        await tester.runAsync(() async {
          if (!o.client.room.state.messages.any((m) => m.id == 'notice-1')) {
            await o.client.room.stream
                .firstWhere((s) => s.messages.any((m) => m.id == 'notice-1'))
                .timeout(const Duration(seconds: 3));
          }
        });
        await _wait(tester, Duration.zero);
        await tester.runAsync(
          () => gates.echo.future.timeout(const Duration(seconds: 3)),
        );
        await tester.pump();
        expect(o.repo.readMarks, contains(at));
        expect(o.watermark.syncedAt(kRoomCubitFakeBeaconId), at);
        expect(o.client.room.state.unreadCount, 0);
        expect(find.textContaining('Помощи хватает'), findsWidgets);
        for (final cubit in [o.client.homeInbox, o.client.watchingInbox]) {
          expect(cubit.state.projectionLoaded, isTrue);
          expect(cubit.state.projectionFailed, isFalse);
          expect(cubit.state.items.single.beacon?.title, 'Request snapshot 1');
          expect(cubit.state.items.single.roomHints?.roomUnreadCount, 0);
        }
        expect(tester.takeException(), isNull);
        expect(inbox.starts, isNotEmpty);
        for (final read in inbox.starts) {
          expect(
            read.delivery,
            isNotNull,
            reason: 'A fetch must have an actual delivered cause',
          );
          expect(inbox.deliveries, contains(read.delivery));
          expect(
            read.delivery!.trigger,
            anyOf(
              'realtime:roomMessage',
              'room:roomMessage',
              'realtime:beacon',
              'realtime:activityEvent',
              'room:activityEvent',
            ),
            reason:
                'A read must come from this status wave, never its '
                'watermark, room_seen echo, or an unrelated catch-up',
          );
        }
        expect(inbox.starts.first.overlapsRead, isFalse);
        expect(
          inbox.starts.skip(1).map((read) => read.overlapsRead),
          everyElement(holdResponse),
        );
        expect(
          inbox.deliveries.where((d) => d.trigger.startsWith('catch-up:')),
          isEmpty,
        );
        final echoIndex = inbox.trace.indexOf('wire:roomSeen');
        final watermarkIndex = inbox.trace.indexWhere(
          (s) => s.contains('trigger: watermark'),
        );
        expect(echoIndex, greaterThanOrEqualTo(0));
        expect(watermarkIndex, greaterThanOrEqualTo(0));
        final readIndices = [
          for (var i = 0; i < inbox.trace.length; i++)
            if (inbox.trace[i].startsWith('InboxFetch:')) i,
        ];
        expect(readIndices, everyElement(lessThan(echoIndex)));
        expect(readIndices, everyElement(lessThan(watermarkIndex)));
        // Check the read budget and both applied results together. In the fast
        // response case a second read yields a different context, so checking
        // eventual titles alone would miss the inconsistent projection.
        expect(
          {
            'InboxFetch': inbox.fetchCallCount - before,
            'applied result': applied,
            'successful updates': updates,
          },
          {
            'InboxFetch': 1,
            'applied result': {
              'home': expectedProjection,
              'watching': expectedProjection,
            },
            'successful updates': {'home': 1, 'watching': 1},
          },
          reason:
              'One status wave must apply the same result exactly once '
              'to both observers. Trigger/read order: ${inbox.trace}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  group('A reader at the bottom reads a status line in one refresh wave', () {
    for (final scope in <String?>[null, 'CIquestions1']) {
      for (final firstRead in [false, true]) {
        testWidgets(
          '${scope == null ? "Discussion" : "Questions"} auto-read keeps every '
          'mounted observer projection to one refresh when the server '
          'publishes the ${firstRead ? "first" : "advanced"} read cursor',
          (tester) async {
            final o = await _mountObserver(
              tester,
              scope: scope,
              firstRead: firstRead,
            );
            final before = _reads(o);
            final at = await _deliverStatusChange(tester, o, scope: scope);
            // First fixed window fetches the system line. Building the real
            // body at the bottom now marks it read and the server publishes
            // the reader's cursor, which used to open wave 2.
            await _wait(tester, const Duration(milliseconds: 2800));
            expect(
              o.client.room.state.messages.last.systemPayloadJson,
              jsonEncode(_statusPayload),
            );
            expect(
              o.repo.readMarks,
              contains(at),
              reason:
                  'The mounted body, not the test, must read the received line',
            );
            expect(
              o.watermark.syncedAt(
                kRoomCubitFakeBeaconId,
                threadId: scope ?? RequestThread.generalId,
              ),
              at,
            );
            await _wait(tester, const Duration(milliseconds: 3200));
            expect(o.client.room.state.unreadCount, 0);
            if (scope == null) {
              expect(find.textContaining('Помощи хватает'), findsWidgets);
            }
            expect(tester.takeException(), isNull);
            o.client.expectSnapshot(1, includeRoom: false);
            expect(o.questions.state?.messageCount, 8);
            // Concrete disposition of the involvement pair: one initial
            // People read plus one status-driven trailing refresh. The read
            // cursor must not add another. Fresh watching ids prove the
            // trailing read returned.
            expect(o.client.forward.involvementReads, 2);
            expect(
              o.client.view.state.involvementWatchingIds,
              contains('watcher-1'),
            );
            final delta = _delta(_reads(o), before);
            expect(
              delta,
              _oneWave(scope),
              reason:
                  'Every mounted observer must converge in one wave; child '
                  'reads are per group. Actual: $delta',
            );
            // Dispose the mounted body before its dependencies and sockets.
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  });

  group('A scrolled-up reader keeps its place while another tab reads', () {
    for (final scope in <String?>[null, 'CIquestions1']) {
      testWidgets(
        '${scope == null ? "Discussion" : "Questions"} reader scrolled up '
        "keeps its scroll position, converges unread from the other tab's "
        'read cursor and refreshes once',
        (tester) async {
          final o = await _mountObserver(
            tester,
            scope: scope,
            firstRead: false,
            previousCount: 40,
          );
          final scroll = _chatScroll(tester);
          expect(scroll.maxScrollExtent, greaterThan(1200));
          await tester.drag(
            find
                .descendant(
                  of: find.byType(BasicChatBody),
                  matching: find.byType(Scrollable),
                )
                .first,
            const Offset(0, 900),
          );
          await tester.pump(const Duration(milliseconds: 300));
          final readingAt = scroll.pixels;
          expect(
            scroll.maxScrollExtent - readingAt,
            greaterThan(56),
            reason: 'The reader is reading older messages, not the bottom',
          );
          final before = _reads(o);
          final at = await _deliverStatusChange(tester, o, scope: scope);
          await _wait(tester, const Duration(milliseconds: 2800));
          expect(
            o.client.room.state.messages.last.systemPayloadJson,
            jsonEncode(_statusPayload),
          );
          expect(
            o.repo.readMarks,
            isEmpty,
            reason: 'A scrolled-up reader is not auto-followed to the line',
          );
          expect(o.client.room.state.unreadCount, 1);
          expect(scroll.pixels, moreOrLessEquals(readingAt, epsilon: 1));
          // The same reader reads the line in another tab: the server
          // persists the cursor and fans it out to this tab as well.
          o.wire.socket.frames.add(
            jsonEncode(
              roomSeenReadCursorFrame(
                readerId: roomHintWireViewerId,
                beaconId: kRoomCubitFakeBeaconId,
                at: at,
                event: 'update',
                threadItemId: scope,
              ),
            ),
          );
          await _wait(tester, const Duration(milliseconds: 3200));
          expect(tester.takeException(), isNull);
          expect(
            o.watermark.syncedAt(
              kRoomCubitFakeBeaconId,
              threadId: scope ?? RequestThread.generalId,
            ),
            at,
            reason: "The other tab's cursor converges this tab",
          );
          expect(o.client.room.state.unreadCount, 0);
          expect(
            scroll.pixels,
            moreOrLessEquals(readingAt, epsilon: 1),
            reason: "A read cursor must not move the reader's place",
          );
          expect(
            o.repo.readMarks,
            isEmpty,
            reason: 'Convergence is not a new read by this tab',
          );
          o.client.expectSnapshot(1, includeRoom: false);
          final delta = _delta(_reads(o), before);
          expect(
            delta,
            _oneWave(scope),
            reason:
                'A read cursor from another tab is not a content change. '
                'Actual: $delta',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  });
}
