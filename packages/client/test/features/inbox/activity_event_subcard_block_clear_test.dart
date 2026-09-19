import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
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

/// Records the clear axis and makes the read axis fatal: U10b moved event
/// acknowledgement off `seen_at`, and a block that quietly marked seen again
/// would look identical on screen.
final class _AxisRepository extends AttentionRepositoryFake {
  final List<String?> clearSnapshots = [];
  final List<String> clears = [];

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
      throw StateError('the active-event block must never mark seen: $ids');

  @override
  Future<int> markUnseen(List<String> ids) async =>
      throw StateError('the active-event block must never mark unseen');

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async =>
      throw StateError('the active-event block must never mark all seen');

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;

  @override
  Future<AttentionClearSnapshot> clearSnapshot({
    required AttentionClearCaptureKind kind,
    String? beaconId,
    String? receiptId,
  }) async {
    clearSnapshots.add(receiptId);
    return AttentionClearSnapshot(
      snapshotToken: 'token-$receiptId',
      receiptIds: [if (receiptId != null) receiptId],
    );
  }

  @override
  Future<AttentionClearResult> clear({
    required String snapshotToken,
    required String operationId,
  }) async {
    clears.add(snapshotToken);
    return AttentionClearResult(
      operationId: operationId,
      status: AttentionOperationStatus.complete,
      appliedReceiptIds: [snapshotToken.replaceFirst('token-', '')],
    );
  }
}

void main() {
  late AttentionCaseTestAccounts accounts;
  late _AxisRepository repository;

  setUp(() {
    accounts = AttentionCaseTestAccounts();
    repository = _AxisRepository();
    GetIt.I.registerSingleton<AttentionCase>(
      AttentionCase(
        repository,
        accounts,
        buildTestRealtimeSync().case_,
        noopBlockCase(),
        FeedSessionRegistry(),
        Logger('ActivityEventSubcardBlockClearTest'),
        qaLatencyMeasurementEnabled: false,
      ),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
    await accounts.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    required int eventTotal,
    required List<AttentionReceipt> preview,
    AttentionBlockOverflowPolicy policy =
        AttentionBlockOverflowPolicy.timeline,
    VoidCallback? onOpenTimeline,
  }) async {
    const size = Size(800, 1200);
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
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  key: const Key('block-host'),
                  width: 360,
                  child: ActivityEventSubcardBlock(
                    eventTotal: eventTotal,
                    eventsPreview: preview,
                    beaconId: 'b1',
                    overflowPolicy: policy,
                    onOpenTimeline: onOpenTimeline,
                    onClearEvent: (id) => GetIt.I<AttentionCase>().clearReceipt(
                      receiptId: id,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('dismissing a row clears it and never marks it seen', (
    tester,
  ) async {
    await pump(tester, eventTotal: 2, preview: [_event(0), _event(1)]);

    expect(find.byType(AttentionMiniCard), findsNWidgets(2));

    await tester.tap(find.byKey(AttentionMiniCard.dismissKey).first);
    await tester.pumpAndSettle();

    // The clear axis carried it — and `markSeen` would have thrown.
    expect(repository.clearSnapshots, ['e0']);
    expect(repository.clears, ['token-e0']);
    // The cleared row leaves the block.
    expect(
      tester
          .widgetList<AttentionMiniCard>(find.byType(AttentionMiniCard))
          .map((c) => c.receipt.id),
      ['e1'],
    );
  });

  testWidgets('«ещё N» opens the Timeline and the block does not grow', (
    tester,
  ) async {
    var opened = 0;
    await pump(
      tester,
      eventTotal: 12,
      preview: [for (var i = 0; i < 3; i++) _event(i)],
      onOpenTimeline: () => opened++,
    );

    final host = find.byKey(const Key('block-host'));
    final before = tester.getSize(host).height;
    expect(find.byType(AttentionMiniCard), findsNWidgets(3));
    expect(find.text('9 more updates'), findsOneWidget);

    await tester.tap(find.byKey(ActivityEventSubcardBlock.moreKey));
    await tester.pumpAndSettle();

    expect(opened, 1);
    // The height guarantee: a card whose «ещё N» expanded in place would grow
    // here, and no navigation assertion alone would notice.
    expect(tester.getSize(host).height, before);
    expect(find.byType(AttentionMiniCard), findsNWidgets(3));
    expect(repository.clearSnapshots, isEmpty);
  });
}
