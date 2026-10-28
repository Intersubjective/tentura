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

import '../../support/attention_repository_fake_base.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'fake_lobby_port.dart';

/// A Questions notice for [beaconId] that the author has not settled.
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

/// The server's attention store, answering every read path with the same
/// receipts, so the row may take its numbers from whichever one it likes.
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

void main() {
  group('the Questions row tells the author how many questions are new', () {
    late AttentionCase attention;

    tearDown(() async {
      await GetIt.I.reset();
    });

    /// The author's Request B1 holds [messages] Questions messages; the
    /// server holds [receipts] for the author.
    Future<void> pumpRow(
      WidgetTester tester,
      List<AttentionReceipt> receipts, {
      Locale locale = const Locale('en'),
      int messages = 5,
    }) async {
      await GetIt.I.reset();
      final port = FakeLobbyPort(viewerId: 'Uauthor');
      for (var i = 0; i < messages; i++) {
        port.messagesList.add(
          BeaconLobbyMessage(
            id: 'M$i',
            authorId: 'Unina',
            authorName: 'Nina',
            body: 'Question $i',
          ),
        );
      }
      GetIt.I.registerSingleton<BeaconLobbyCase>(
        lobbyCaseFor(port, FakeRealtimeSyncPort()),
      );

      final accounts = _Accounts();
      addTearDown(accounts.close);
      final sync = buildTestRealtimeSync();
      addTearDown(sync.port.dispose);
      attention = AttentionCase(
        _AttentionServer(receipts),
        accounts,
        sync.case_,
        noopBlockCase(),
        FeedSessionRegistry(),
        Logger('beacon-lobby-entry-row-unread-test'),
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

    testWidgets('two unsettled Questions notices read "2 new"', (
      tester,
    ) async {
      await pumpRow(tester, [
        _questionsReceipt('r1'),
        _questionsReceipt('r2'),
        // Not this Request's Questions: another Request, a General message,
        // and a question the author has already dealt with.
        _questionsReceipt('other', beaconId: 'B2'),
        _questionsReceipt('general', coordinationItemId: null),
        _questionsReceipt('done', settlementKind: 'resolved'),
      ]);
      expect(find.text('Questions'), findsOneWidget);
      // The total stays next to it.
      expect(find.text('5 messages'), findsOneWidget);
      expect(find.text('2 new'), findsOneWidget);
    });

    testWidgets('no unsettled Questions notice, no badge', (tester) async {
      await pumpRow(tester, [
        _questionsReceipt('other', beaconId: 'B2'),
        _questionsReceipt('general', coordinationItemId: null),
        _questionsReceipt('done', settlementKind: 'resolved'),
      ]);
      expect(find.text('5 messages'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\bnew\b')), findsNothing);
    });

    testWidgets('settling the notices clears the badge', (tester) async {
      await pumpRow(tester, [_questionsReceipt('r1'), _questionsReceipt('r2')]);
      expect(find.text('2 new'), findsOneWidget);

      await attention.settleReceipt('r1');
      await tester.pumpAndSettle();
      expect(find.text('1 new'), findsOneWidget);

      await attention.settleReceipt('r2');
      await tester.pumpAndSettle();
      expect(find.textContaining(RegExp(r'\bnew\b')), findsNothing);
      expect(find.text('5 messages'), findsOneWidget);
    });

    testWidgets('the badge is written in Russian for a Russian reader', (
      tester,
    ) async {
      await pumpRow(tester, [
        _questionsReceipt('r1'),
        _questionsReceipt('r2'),
      ], locale: const Locale('ru'));
      expect(find.text('2 new'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data ?? '').contains('2') &&
              (w.data ?? '').toLowerCase().contains('нов'),
        ),
        findsOneWidget,
      );
    });
  });
}
