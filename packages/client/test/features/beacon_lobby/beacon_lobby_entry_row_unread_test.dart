import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/activity_beacon_attention.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_lobby/ui/widget/beacon_lobby_entry_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';

import '../beacon_threads/room_cubit_fakes.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'fake_lobby_port.dart';

/// Independent attention state; these notices never define Questions unread.
AttentionReceipt _questionsReceipt(
  String id, {
  String beaconId = 'B1',
  String? coordinationItemId = 'Llobby',
  String? settlementKind,
}) => AttentionReceipt(
  id: id,
  category: 'room',
  kind: 'roomActivityLowPriority',
  priority: 'normal',
  title: 'Ilya',
  body: 'New message in Questions',
  actionUrl: '/#/beacon/lobby/$beaconId',
  createdAt: DateTime.utc(2026, 10, 24),
  collapsedCount: 1,
  presentationKey: 'room_message_posted',
  presentationPayloadJson: coordinationItemId == null
      ? '{"eventType":"roomMessagePosted","beaconId":"$beaconId"}'
      : '{"eventType":"roomMessagePosted","beaconId":"$beaconId",'
            '"coordinationItemId":"$coordinationItemId"}',
  surface: AttentionSurface.myWork,
  beaconId: beaconId,
  targetEntityId: 'message-$id',
  destinationKind: 'beacon_room_message',
  coordinationItemId: coordinationItemId,
  requiresAction: true,
  settlementKind: settlementKind,
  settledAt: settlementKind == null ? null : DateTime.utc(2026, 10, 25),
);

/// Attention state is deliberately absent or disagrees with the Questions
/// messages and read cursor, so counting notices cannot satisfy these tests.
class _AttentionServer extends AttentionRepositoryFake {
  _AttentionServer(Iterable<AttentionReceipt> receipts)
    : _receipts = {for (final r in receipts) r.id: r};

  final Map<String, AttentionReceipt> _receipts;

  List<AttentionReceipt> get _all => _receipts.values.toList();

  @override
  Future<int> settle({required String receiptId, required String kind}) async {
    final receipt = _receipts[receiptId];
    if (receipt == null) return 0;
    _receipts[receiptId] = receipt.copyWith(
      settlementKind: kind,
      settledAt: DateTime.utc(2026, 10, 25),
    );
    return 1;
  }

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => AttentionFeed(
    summary: const AttentionSummary(),
    page: AttentionFeedPage(items: _all),
  );

  @override
  Future<AttentionFeedPage> requestHistory({
    required String beaconId,
    String? cursor,
    int limit = 20,
  }) async => AttentionFeedPage(
    items: [
      for (final r in _all)
        if (r.beaconId == beaconId) r,
    ],
  );

  @override
  Future<List<MyWorkBeaconAttention>> myWorkAttention(
    Set<String> beaconIds,
  ) async => [
    for (final id in beaconIds)
      MyWorkBeaconAttention(
        beaconId: id,
        unseenCount: 0,
        liveObligations: [
          for (final r in _all)
            if (r.beaconId == id && r.isLiveObligation) r,
        ],
      ),
  ];

  @override
  Future<ActivityBeaconAttention> activityAttention({
    required String beaconId,
    String? cursor,
    int limit = 20,
  }) async => ActivityBeaconAttention(
    beaconId: beaconId,
    eventTotal: 0,
    unseenCount: 0,
    latestAt: DateTime.utc(1970),
    events: [
      for (final r in _all)
        if (r.beaconId == beaconId) r,
    ],
  );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => {
    for (final r in _all)
      if (r.isLiveObligation && r.beaconId != null) r.beaconId!,
  };

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;
}

class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  /// The case refreshes attention only for a signed-in account.
  void signIn(String id) => _changes.add(id);

  Future<void> close() => _changes.close();
}

Widget _app(Locale locale, Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: locale,
  home: child,
);

/// The existing room API supplies Questions messages, independently of the
/// attention API. Restrict reads to the requested Request and Questions scope.
class _QuestionsMessages extends FakeBeaconThreadsRepository {
  _QuestionsMessages() : super(userId: 'Uauthor');

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) async => [
    for (final message in messages)
      if (message.beaconId == beaconId && message.threadItemId == threadItemId)
        message,
  ];
}

/// Models the server probe's counts from its messages and persisted cursor.
/// The row consumes this probe, rather than downloading room history itself.
class _QuestionsLobbyPort extends FakeLobbyPort {
  _QuestionsLobbyPort(this.room, this.watermarks) : super(viewerId: 'Uauthor');

  final _QuestionsMessages room;
  final RoomReadWatermarkStore watermarks;

  @override
  Future<BeaconLobbyAccess> access(String beaconId) async {
    final access = await super.access(beaconId);
    final seen = watermarks.readThrough(beaconId, threadId: 'Llobby');
    return access.copyWith(
      unreadCount: room.messages
          .where(
            (message) =>
                message.beaconId == beaconId &&
                message.threadItemId == 'Llobby' &&
                message.authorId != viewerId &&
                (seen == null || message.createdAt.isAfter(seen)),
          )
          .length,
    );
  }
}

void main() {
  group('author Questions counts follow the Questions read cursor', () {
    late AttentionCase attention;
    late RoomReadWatermarkStore watermarks;
    late _QuestionsMessages room;

    tearDown(() async {
      await GetIt.I.reset();
    });

    /// Five actual Questions messages, with the first three already read.
    /// Acknowledging attention is deliberately a separate state transition.
    Future<void> pumpRow(
      WidgetTester tester, {
      List<AttentionReceipt> notices = const [],
      bool allQuestionsRead = false,
      Locale locale = const Locale('en'),
    }) async {
      await GetIt.I.reset();
      final at = DateTime.utc(2026, 10, 24, 12);
      room = _QuestionsMessages()
        ..messages = [
          for (var i = 1; i <= 5; i++)
            RoomMessage(
              id: 'M$i',
              beaconId: 'B1',
              threadItemId: 'Llobby',
              body: 'Question $i',
              authorId: i.isOdd ? 'Ubob' : 'Ucarol',
              author: Profile(
                id: i.isOdd ? 'Ubob' : 'Ucarol',
                displayName: i.isOdd ? 'Bob' : 'Carol',
              ),
              createdAt: at.add(Duration(minutes: i)),
            ),
        ];
      watermarks = RoomReadWatermarkStore.testing()
        ..confirmSynced(
          'B1',
          room.messages[allQuestionsRead ? 4 : 2].createdAt,
          threadId: 'Llobby',
        );
      addTearDown(watermarks.dispose);
      final lobbySync = FakeRealtimeSyncPort();
      addTearDown(lobbySync.dispose);
      final port = _QuestionsLobbyPort(room, watermarks)..messageCount = 5;
      final sync = buildTestRealtimeSync();
      addTearDown(sync.port.dispose);
      GetIt.I
        ..registerSingleton<BeaconLobbyCase>(lobbyCaseFor(port, lobbySync))
        ..registerSingleton<RoomReadWatermarkStore>(watermarks)
        ..registerSingleton<BeaconThreadsCase>(
          roomCubitMakeCase(
            room,
            watermarkStore: watermarks,
            realtimeSyncCase: sync.case_,
          ),
        );
      registerRoomCubitProfileCubit('Uauthor');
      final accounts = _Accounts();
      addTearDown(accounts.close);
      attention = AttentionCase(
        _AttentionServer(notices),
        accounts,
        sync.case_,
        noopBlockCase(),
        FeedSessionRegistry(),
        Logger('questions-read-cursor-widget-test'),
      );
      addTearDown(attention.dispose);
      GetIt.I.registerSingleton<AttentionCase>(attention);
      ensureNoopAttentionActorProfilesRegistered();
      accounts.signIn('Uauthor');
      await tester.pumpWidget(
        _app(
          locale,
          const Scaffold(
            body: BeaconLobbyEntryRow(beaconId: 'B1', isAuthor: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('two unread Questions replace the total with "2 new"', (
      tester,
    ) async {
      await pumpRow(tester);
      expect(find.text('Questions'), findsOneWidget);
      expect(find.text('2 new'), findsOneWidget);
      expect(find.text('5 messages'), findsNothing);
    });

    testWidgets('read Questions show the total despite pending notices', (
      tester,
    ) async {
      await pumpRow(
        tester,
        allQuestionsRead: true,
        notices: [
          _questionsReceipt('r1'),
          _questionsReceipt('r2'),
        ],
      );
      expect(find.text('5 messages'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\bnew\b')), findsNothing);
    });

    testWidgets('settling notices leaves unread Questions unchanged', (
      tester,
    ) async {
      await pumpRow(
        tester,
        notices: [
          _questionsReceipt('r1'),
          _questionsReceipt('r2'),
        ],
      );
      expect(find.text('2 new'), findsOneWidget);
      final lastRead = watermarks.readThrough('B1', threadId: 'Llobby');
      await attention.settleReceipt('r1');
      await tester.pumpAndSettle();
      expect(
        find.text('2 new'),
        findsOneWidget,
        reason: 'Settling a notice does not read its Questions message.',
      );
      await attention.settleReceipt('r2');
      await tester.pumpAndSettle();
      expect(watermarks.readThrough('B1', threadId: 'Llobby'), lastRead);
      expect(find.text('2 new'), findsOneWidget);
      expect(find.text('5 messages'), findsNothing);
    });

    testWidgets('two unread Questions are localized for a Russian reader', (
      tester,
    ) async {
      await pumpRow(tester, locale: const Locale('ru'));
      final l10n = lookupL10n(const Locale('ru'));
      expect(find.text(l10n.beaconLobbyEntryUnread(2)), findsOneWidget);
      expect(find.text(l10n.beaconLobbyEntryCount(5)), findsNothing);
      expect(find.text('2 new'), findsNothing);
    });
  });
}
