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
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'activity_offers_test_support.dart';
import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;
import '../../support/noop_attention_actor_profiles.dart';

Future<void> _settle([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
  await Future<void>.delayed(const Duration(milliseconds: 60));
}

InboxItem _offer(String beaconId, DateTime at) => InboxItem(
  beaconId: beaconId,
  latestForwardAt: at,
  status: InboxItemStatus.needsMe,
);

final class _Accounts implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => const Stream.empty();
}

class _AttentionRepo extends ConfigurableActivityOffersAttentionRepo {
  Set<String> unread = const {};

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => AttentionFeed(
    summary: const AttentionSummary(),
    page: const AttentionFeedPage(),
  );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async =>
      unread.intersection(beaconIds);

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

  void emitDeskChange(String beaconId) => _forwardChanges.add(beaconId);

  void emitHelpOffer(HelpOfferEvent event) => _helpOfferChanges.add(event);

  @override
  Future<void> dispose() async {
    await _helpOfferChanges.close();
    await _forwardChanges.close();
    await _forwardCommandCompleted.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeInboxRepository repo;
  late _ForwardRepo forwardRepo;
  late InboxCase inboxCase;
  late _AttentionRepo attentionRepo;
  late ActivityOffersCubit cubit;

  ActivityOffersCubit buildCubit({
    FakeInboxRepository? inboxRepo,
    _AttentionRepo? attention,
    int pageSize = 20,
  }) {
    final sync = buildTestRealtimeSync();
    final attentionCase = AttentionCase(
      attention ?? attentionRepo,
      _Accounts(),
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('activity-offers-test'),
    );
    inboxCase = buildTestInboxCase(
      inboxRepo ?? repo,
      buildTestBeaconThreadsCase(),
      forwardRepository: forwardRepo,
      realtimeSyncCase: sync.case_,
    );
    return ActivityOffersCubit(
      userId: 'u1',
      inboxCase: inboxCase,
      attentionCase: attentionCase,
      pageSize: pageSize,
      actorProfiles: buildNoopAttentionActorProfiles(),
    );
  }

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

  group('paging', () {
    test('loadMore uses V2 nextCursor not item latestForwardAt', () async {
      const opaqueCursor = 'v2-cursor-not-latest-forward-at';
      final at = DateTime.utc(2026, 3, 1, 12);
      final first = [
        _offer('B3', at),
        _offer('B2', at),
      ];
      final second = [
        _offer('B1', at),
        _offer('B0', at.subtract(const Duration(hours: 1))),
      ];
      wireActivityOffersV2(
        inbox: repo,
        attention: attentionRepo,
        items: [...first, ...second],
        nextCursor: opaqueCursor,
        totalCount: 4,
      );
      attentionRepo.offerRows = [
        for (final item in first) activityOfferSortRow(item),
      ];
      attentionRepo.secondOfferRows = [
        for (final item in second) activityOfferSortRow(item),
      ];
      attentionRepo.secondOffersNextCursor = null;
      cubit = buildCubit(pageSize: 2);

      await cubit.loadFirst();
      expect(cubit.state.offersNextCursor, opaqueCursor);
      final reordered = [
        cubit.state.items.last,
        ...cubit.state.items.sublist(0, cubit.state.items.length - 1),
      ];
      cubit.emit(cubit.state.copyWith(items: reordered));

      await cubit.loadMore();
      expect(attentionRepo.lastActivityOffersCursor, opaqueCursor);
      expect(
        attentionRepo.lastActivityOffersCursor,
        isNot(cubit.state.items.last.latestForwardAt.toIso8601String()),
      );
      expect(
        cubit.state.items.map((e) => e.beaconId).toSet(),
        {'B3', 'B2', 'B1', 'B0'},
      );
      expect(cubit.state.hasMore, isFalse);
    });
  });

  group('live arrival', () {
    test('inserts at top when not scrolled away', () async {
      final first = [_offer('B1', DateTime.utc(2026, 1, 1))];
      wireActivityOffersV2(inbox: repo, attention: attentionRepo, items: first);
      repo.openForwardsCount = 1;
      cubit = buildCubit();

      await cubit.loadFirst();
      final arrival = _offer('B-new', DateTime.utc(2026, 6, 1));
      repo.openForwardByBeacon['B-new'] = arrival;

      forwardRepo.emitDeskChange('B-new');
      await _settle(20);

      expect(cubit.state.items.first.beaconId, 'B-new');
      expect(cubit.state.heldBackIds, isEmpty);
    });

    test('held back while scrolled away until revealHeldBack', () async {
      final first = [_offer('B1', DateTime.utc(2026, 1, 1))];
      wireActivityOffersV2(inbox: repo, attention: attentionRepo, items: first);
      repo.openForwardsCount = 1;
      cubit = buildCubit();

      await cubit.loadFirst();
      cubit.setScrolledAway(true);
      final arrival = _offer('B-new', DateTime.utc(2026, 6, 1));
      repo.openForwardByBeacon['B-new'] = arrival;

      forwardRepo.emitDeskChange('B-new');
      await _settle(20);

      expect(cubit.state.items.map((e) => e.beaconId), ['B1']);
      expect(cubit.state.heldBackIds, {'B-new'});

      cubit.revealHeldBack();
      expect(cubit.state.items.first.beaconId, 'B-new');
      expect(cubit.state.heldBackIds, isEmpty);
    });
  });

  group('demotion', () {
    test('watch removes row and emits demotedBeaconIds', () async {
      wireActivityOffersV2(
        inbox: repo,
        attention: attentionRepo,
        items: [_offer('B1', DateTime.utc(2026))],
      );
      repo.openForwardsCount = 1;
      cubit = buildCubit();

      await cubit.loadFirst();
      final demoted = <String>[];
      final sub = cubit.demotedBeaconIds.listen(demoted.add);

      repo.openForwardByBeacon['B1'] = null;
      forwardRepo.emitDeskChange('B1');
      await _settle(20);

      expect(cubit.state.items, isEmpty);
      expect(demoted, ['B1']);
      await sub.cancel();
    });

    test('reject demotes via help-offer stream', () async {
      wireActivityOffersV2(
        inbox: repo,
        attention: attentionRepo,
        items: [_offer('B2', DateTime.utc(2026))],
      );
      repo.openForwardsCount = 1;
      cubit = buildCubit();

      await cubit.loadFirst();
      final demoted = <String>[];
      final sub = cubit.demotedBeaconIds.listen(demoted.add);

      repo.openForwardByBeacon['B2'] = null;
      forwardRepo.emitHelpOffer(const HelpOfferCreated('B2'));
      await _settle(20);

      expect(cubit.state.items, isEmpty);
      expect(demoted, ['B2']);
      await sub.cancel();
    });

    test('restored rejected re-upserts through open-forward refetch', () async {
      wireActivityOffersV2(
        inbox: repo,
        attention: attentionRepo,
        items: [_offer('B3', DateTime.utc(2026))],
      );
      repo.openForwardsCount = 1;
      cubit = buildCubit();

      await cubit.loadFirst();
      repo.openForwardByBeacon['B3'] = null;
      forwardRepo.emitDeskChange('B3');
      await _settle(20);
      expect(cubit.state.items, isEmpty);

      final restored = _offer('B3', DateTime.utc(2026, 7, 1));
      repo.openForwardByBeacon['B3'] = restored;
      forwardRepo.emitDeskChange('B3');
      await _settle(20);

      expect(cubit.state.items.single.beaconId, 'B3');
      expect(
        cubit.state.items.single.latestForwardAt,
        restored.latestForwardAt,
      );
    });
  });

  group('totalCount', () {
    test('reflects aggregate before all pages are loaded', () async {
      final at = DateTime.utc(2026, 3, 1);
      final first = [_offer('B2', at), _offer('B1', at)];
      final second = [_offer('B0', at.subtract(const Duration(hours: 1)))];
      wireActivityOffersV2(
        inbox: repo,
        attention: attentionRepo,
        items: first,
        nextCursor: 'more',
        totalCount: 3,
      );
      attentionRepo.secondOfferRows = [
        for (final item in second) activityOfferSortRow(item),
      ];
      cubit = buildCubit(pageSize: 2);

      await cubit.loadFirst();
      expect(cubit.state.items.length, 2);
      expect(cubit.state.totalCount, 3);
    });

    test('failed offers fetch leaves count from prior success', () async {
      wireActivityOffersV2(
        inbox: repo,
        attention: attentionRepo,
        items: [_offer('B1', DateTime.utc(2026))],
        nextCursor: 'more',
      );
      cubit = buildCubit();

      await cubit.loadFirst();
      expect(cubit.state.totalCount, 1);

      attentionRepo.failActivityOffers = true;
      await cubit.loadMore();
      expect(cubit.state.pageLoadFailed, isTrue);
      expect(cubit.state.totalCount, 1);
    });
  });
}
