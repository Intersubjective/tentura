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
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/features/inbox/ui/widget/activity_event_subcard_block.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../block/support/controllable_block_case.dart';
import '../../domain/attention/attention_case_test_support.dart';
import '../../support/attention_repository_fake_base.dart';
import '../../support/test_realtime_sync.dart';

AttentionReceipt _event(int index) => AttentionReceipt(
  id: 'e$index',
  category: 'requestProgress',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: 'Event $index',
  body: 'Body $index',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 1, 2),
  collapsedCount: 1,
  presentationKey: 'help_offer_submitted',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
);

/// Serves [total] children strictly by cursor, [pageSize] at a time.
///
/// The cursor is the index of the first row of the next page, so a fake that
/// ignored it would repeat the head forever and the dedupe assertions below
/// would fail rather than pass quietly.
final class _PagingRepository extends AttentionRepositoryFake {
  _PagingRepository({required this.total});

  final int total;
  static const pageSize = 20;
  final List<({String? cursor, int limit})> calls = [];

  @override
  Future<ActivityBeaconAttention> activityAttention({
    required String beaconId,
    String? cursor,
    int limit = 20,
  }) async {
    calls.add((cursor: cursor, limit: limit));
    final offset = cursor == null ? 0 : int.parse(cursor);
    final take = limit < pageSize ? limit : pageSize;
    final end = (offset + take) > total ? total : offset + take;
    return ActivityBeaconAttention(
      beaconId: beaconId,
      eventTotal: total,
      unseenCount: total,
      latestAt: DateTime.utc(2026, 1, 2),
      events: [for (var i = offset; i < end; i++) _event(i)],
      nextCursor: end >= total ? null : '$end',
    );
  }

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => const AttentionFeed(
    summary: AttentionSummary(unreadTotal: 0),
    page: AttentionFeedPage(),
  );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => const {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markSeen(List<String> ids) async =>
      throw StateError('the active-event block must never mark seen');

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

Future<void> _pump(
  WidgetTester tester, {
  required int eventTotal,
  required List<AttentionReceipt> preview,
}) async {
  const size = Size(800, 2000);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: ActivityEventSubcardBlock(
                eventTotal: eventTotal,
                eventsPreview: preview,
                beaconId: 'b1',
                overflowPolicy: AttentionBlockOverflowPolicy.paginate,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

List<String> _renderedIds(WidgetTester tester) => tester
    .widgetList<AttentionMiniCard>(find.byType(AttentionMiniCard))
    .map((c) => c.receipt.id)
    .toList(growable: false);

void main() {
  late AttentionCaseTestAccounts accounts;

  setUp(() {
    accounts = AttentionCaseTestAccounts();
  });

  tearDown(() async {
    await GetIt.I.reset();
    await accounts.dispose();
  });

  void registerCase(_PagingRepository repository) {
    GetIt.I.registerSingleton<AttentionCase>(
      AttentionCase(
        repository,
        accounts,
        buildTestRealtimeSync().case_,
        noopBlockCase(),
        FeedSessionRegistry(),
        Logger('ActivityEventSubcardBlockPaginationTest'),
        qaLatencyMeasurementEnabled: false,
      ),
    );
  }

  testWidgets('paginates past the old one-shot 100 cap', (tester) async {
    final repository = _PagingRepository(total: 120);
    registerCase(repository);
    await _pump(
      tester,
      eventTotal: 120,
      preview: [for (var i = 0; i < 3; i++) _event(i)],
    );

    var guard = 0;
    final loadMore = find.byKey(ActivityEventSubcardBlock.loadMoreKey);
    while (loadMore.evaluate().isNotEmpty) {
      await tester.ensureVisible(loadMore);
      await tester.pump();
      await tester.tap(loadMore);
      await tester.pumpAndSettle();
      if (++guard > 20) fail('pagination did not terminate');
    }

    final ids = _renderedIds(tester);
    // The 101st child is the one the old single capped request could not
    // reach; it must be present, exactly once, like every other child.
    expect(ids, contains('e100'));
    expect(ids, contains('e119'));
    expect(ids.toSet(), hasLength(ids.length), reason: 'no duplicate child');
    expect(ids, hasLength(120), reason: 'no child lost across pages');
    expect(repository.calls.length, greaterThan(1));
    expect(
      repository.calls.map((c) => c.cursor).toList(),
      containsAllInOrder(<String?>[null, '20']),
    );
  });

  testWidgets('the count is the server total, not the loaded rows', (
    tester,
  ) async {
    final repository = _PagingRepository(total: 42);
    registerCase(repository);
    await _pump(
      tester,
      // Two rows in hand, the server says 42 exist.
      eventTotal: 42,
      preview: [for (var i = 0; i < 2; i++) _event(i)],
    );

    expect(_renderedIds(tester), hasLength(2));
    expect(find.text('40 more updates'), findsOneWidget);
  });
}
