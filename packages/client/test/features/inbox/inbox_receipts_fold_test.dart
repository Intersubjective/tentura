import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import '../../support/attention_repository_fake_base.dart';
import 'package:tentura/features/inbox/ui/widget/inbox_receipts_tab_label.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _Repository extends AttentionRepositoryFake {
  AttentionFeed feed = const AttentionFeed(
    summary: AttentionSummary(),
    page: AttentionFeedPage(),
  );

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => feed;

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => const {};

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

AttentionReceipt _receipt({
  required String id,
  required bool seen,
}) => AttentionReceipt(
  id: id,
  category: 'requestProgress',
  kind: 'commitmentAccepted',
  priority: 'normal',
  title: 'Test receipt',
  body: 'Body',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9, 9),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  seenAt: seen ? DateTime.utc(2026, 9, 9, 1) : null,
);

void main() {
  late _Accounts accounts;
  late _Repository repository;
  late TestRealtimeSyncPort realtime;
  late AttentionCase attention;

  setUp(() {
    accounts = _Accounts();
    repository = _Repository();
    final sync = buildTestRealtimeSync();
    realtime = sync.port;
    attention = AttentionCase(
      repository,
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('inbox-receipts-read-state-test'),
    );
    attention.attachFeedSession(AttentionFeedDestinationId.activityStream);
    if (GetIt.I.isRegistered<AttentionCase>()) {
      GetIt.I.unregister<AttentionCase>();
    }
    GetIt.I.registerSingleton<AttentionCase>(attention);
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('inbox-receipts-read-state-test'));
    }
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<AttentionCase>()) {
      GetIt.I.unregister<AttentionCase>();
    }
    await attention.dispose();
    await realtime.dispose();
    await accounts.close();
  });

  test('read-state survives fold: seen receipt stays seen after refresh', () async {
    const receiptId = 'receipt-fold-1';
    repository.feed = AttentionFeed(
      summary: const AttentionSummary(unreadTotal: 1),
      page: AttentionFeedPage(
        items: [_receipt(id: receiptId, seen: false)],
      ),
    );
    accounts.emit('user');
    await attention.refresh();
    await Future<void>.delayed(Duration.zero);

    expect(attention.snapshot.summary.unreadTotal, 1);
    await attention.markSeen([receiptId]);
    // CHANGES IN U15R-c: was `0`. `unreadTotal` counts active attention, and
    // a read receipt is still uncleared (R2/D02). What this test is actually
    // about — the read state surviving a refresh — is asserted below.
    expect(attention.snapshot.summary.unreadTotal, 1);

    repository.feed = AttentionFeed(
      summary: const AttentionSummary(unreadTotal: 1),
      page: AttentionFeedPage(
        items: [_receipt(id: receiptId, seen: false)],
      ),
    );
    await attention.refresh();
    await Future<void>.delayed(Duration.zero);

    // CHANGES IN U17b: was `0`, and only ever was because a pending read-axis
    // ack was folded into this total — which is what let History's "mark
    // unread" raise the badge for an already-cleared row (§3). It now reports
    // what the server reported, which is the same `1` the comment fifteen
    // lines above already states for a read-but-uncleared receipt.
    expect(attention.snapshot.summary.unreadTotal, 1);
    expect(
      attention
          .feedSession(AttentionFeedDestinationId.activityStream)
          .pages[AttentionView.all]!
          .items
          .single
          .isSeen,
      isTrue,
    );
  });

  test('receipts tab label uses AttentionCase unread total like Updates nav', () {
    expect(formatInboxReceiptsTabLabel('Receipts', 3), 'Receipts (3)');
    expect(formatInboxReceiptsTabLabel('Receipts', 0), 'Receipts');
    expect(
      attention.snapshot.summary.unreadTotal,
      repository.feed.summary.unreadTotal,
    );
  });
}
