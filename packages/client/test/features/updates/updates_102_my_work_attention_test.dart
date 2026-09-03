import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _Repository implements AttentionRepositoryPort {
  AttentionFeed feed = const AttentionFeed(
    summary: AttentionSummary(),
    page: AttentionFeedPage(),
  );
  Set<String> unread = const {};

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
  }) async => feed;

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async =>
      unread.intersection(beaconIds);

  @override
  Future<int> markAllSeen() async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

AttentionReceipt _commitmentAcceptedReceipt({
  required String id,
  required String beaconId,
}) => AttentionReceipt(
  id: id,
  category: 'requestProgress',
  kind: 'commitmentAccepted',
  priority: 'normal',
  title: 'Alex accepted your ask',
  body: 'Accept proof',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 8, 5, 10),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  beaconId: beaconId,
);

Future<void> _settle([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Accounts accounts;
  late _Repository repository;
  late TestRealtimeSyncPort realtime;
  late AttentionCase attention;
  late HomeAttentionCubit home;

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
      Logger('updates-102-attention-test'),
    );
    home = HomeAttentionCubit(
      attention,
      accounts,
      Logger('updates-102-attention-test'),
    );
  });

  tearDown(() async {
    await home.close();
    await attention.dispose();
    await realtime.dispose();
    await accounts.close();
  });

  test(
    'commitmentAccepted receipt drives Updates unread and My Work dot without navigation',
    () async {
      const beaconId = 'B102';
      const receiptId = 'receipt-102';
      repository
        ..feed = AttentionFeed(
          summary: const AttentionSummary(unreadTotal: 1),
          page: AttentionFeedPage(
            items: [
              _commitmentAcceptedReceipt(id: receiptId, beaconId: beaconId),
            ],
          ),
        )
        ..unread = {beaconId};

      accounts.emit('author');
      await attention.refresh();
      await _settle();

      expect(attention.snapshot.summary.unreadTotal, 1);
      expect(
        attention.snapshot.pages[AttentionView.all]!.items.single.id,
        receiptId,
      );

      home.reportInboxSnapshot(
        accountId: 'author',
        beaconIds: const {},
        loaded: true,
      );
      home.reportMyWorkSnapshot(
        accountId: 'author',
        beaconIds: {beaconId},
        loaded: true,
      );
      home.setActiveHomeTab(HomeTab.work);
      await _settle();

      expect(home.state.hasMyWorkDot, isFalse);
      expect(home.state.isMyWorkBeaconMarked(beaconId), isTrue);

      home.setActiveHomeTab(HomeTab.updates);
      await _settle();

      expect(home.state.hasMyWorkDot, isTrue);
      expect(home.state.isMyWorkBeaconMarked(beaconId), isTrue);
      expect(home.state.myWorkMarkerIds, {beaconId});
    },
  );
}
