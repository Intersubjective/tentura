import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';

import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'activity_offers_test_support.dart';
import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;

/// The Activity mirror of `attention_page_merge_test.dart`: the pinned zone
/// merges pages too, so the same moving-group property has to hold here.
void main() {
  late FakeInboxRepository repo;
  late _ForwardRepo forwardRepo;
  late _AttentionRepo attentionRepo;
  late ActivityOffersCubit cubit;

  InboxItem offer(String beaconId, DateTime at) => InboxItem(
    beaconId: beaconId,
    latestForwardAt: at,
    status: InboxItemStatus.needsMe,
  );

  setUp(() {
    repo = FakeInboxRepository();
    forwardRepo = _ForwardRepo();
    attentionRepo = _AttentionRepo();
  });

  tearDown(() async {
    await cubit.close();
    await forwardRepo.dispose();
    await repo.dispose();
  });

  test('a Request repeated by a moved page key appears once, losing nothing',
      () async {
    final at = DateTime.utc(2026, 3, 1, 12);
    final all = [offer('B1', at), offer('B2', at), offer('B3', at)];
    wireActivityOffersV2(
      inbox: repo,
      attention: attentionRepo,
      items: all,
      nextCursor: 'page-two',
      totalCount: 3,
    );
    attentionRepo.offerRows = [
      activityOfferSortRow(all[0]),
      activityOfferSortRow(all[1]),
    ];
    // B1's key moved past the cursor, so the tail repeats it alongside B3.
    attentionRepo.secondOfferRows = [
      activityOfferSortRow(all[0]),
      activityOfferSortRow(all[2]),
    ];
    attentionRepo.secondOffersNextCursor = null;

    final sync = buildTestRealtimeSync();
    cubit = ActivityOffersCubit(
      userId: 'u1',
      inboxCase: buildTestInboxCase(
        repo,
        buildTestBeaconThreadsCase(),
        forwardRepository: forwardRepo,
        realtimeSyncCase: sync.case_,
      ),
      attentionCase: AttentionCase(
        attentionRepo,
        _Accounts(),
        sync.case_,
        noopBlockCase(),
        FeedSessionRegistry(),
        Logger('activity-offers-page-merge-test'),
        qaLatencyMeasurementEnabled: false,
      ),
      pageSize: 2,
      actorProfiles: buildNoopAttentionActorProfiles(),
    );

    await cubit.loadFirst();
    await cubit.loadMore();

    final ids = cubit.state.items
        .map((item) => item.beaconId)
        .toList(growable: false);
    expect(
      ids.toSet().length,
      ids.length,
      reason: 'the repeated Request is not shown twice',
    );
    expect(
      ids.toSet(),
      {'B1', 'B2', 'B3'},
      reason: 'and the row only the tail carried is still there',
    );
  });
}

final class _Accounts implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => const Stream.empty();
}

class _AttentionRepo extends ConfigurableActivityOffersAttentionRepo {
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
