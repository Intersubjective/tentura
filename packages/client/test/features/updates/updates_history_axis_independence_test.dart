import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/attention_dismissible_membership.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../features/block/support/controllable_block_case.dart';
import '../../support/attention_repository_fake_base.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import 'support/noop_invite_setup_port.dart';

/// U17b §3 — History's two axes, disagreeing **on purpose**.
///
/// The Unread tab and its badge are the **clear** axis: the server filters
/// them with `$2 = 'unread' AND stream.is_active_attention`
/// (`attention_repository.dart`), and the client mirror is `isInUnreadView`.
/// The row *chrome* — bold headline, the mark-read control — is the **read**
/// axis, `!receipt.isSeen`.
///
/// So a receipt that has been cleared but never read is simultaneously absent
/// from Unread and bold on All. That looks like a contradiction and is not one:
/// it is §3's "these never substitute for one another". This file exists
/// because the name `unreadTotal` has already produced two false findings in
/// this plan by implying the other axis.
void main() {
  testWidgets(
    'a cleared, unseen receipt is absent from Unread but still bold on All',
    (tester) async {
      final accounts = _Accounts();
      final cleared = _receipt(
        id: 'r-cleared',
        clearedAt: DateTime.utc(2026, 9, 19),
      );
      // The Unread list and its badge are derived from the shared membership
      // rule rather than hardcoded, so this fixture *is* the axis: loosening
      // `isActiveOptional` puts the row back on Unread and fails the test
      // below, instead of the fake quietly holding the old answer.
      final unread = [cleared].where(isInUnreadView).toList(growable: false);
      final repository = _ViewRepository(
        itemsByView: {
          AttentionView.all: [cleared],
          AttentionView.unread: unread,
        },
        summary: AttentionSummary(unreadTotal: unread.length),
      );
      final sync = buildTestRealtimeSync();
      final attention = AttentionCase(
        repository,
        accounts,
        sync.case_,
        noopBlockCase(),
        FeedSessionRegistry(),
        Logger('history-axis-independence'),
      );
      accounts.emit('viewer');
      await _drain();

      final cubit = UpdatesFeedCubit(
        destinationId: AttentionFeedDestinationId.activityStream,
        attention: attention,
        setup: NoopInviteAcceptedSetupPort(),
        realtime: sync.case_,
        logger: Logger('history-axis-independence-cubit'),
        actorProfiles: buildNoopAttentionActorProfiles(),
      );
      await _drain();

      await tester.pumpWidget(
        _wrap(
          BlocProvider.value(
            value: cubit,
            child: const UpdatesFeedPane(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The clear axis: not on the Unread list, not in its badge.
      await tester.tap(find.byKey(const ValueKey<String>('updates-unread')));
      await _drain();
      await tester.pumpAndSettle();
      expect(cubit.state.view, AttentionView.unread);
      expect(
        find.bySemanticsIdentifier(TestIds.updatesReceipt('r-cleared')),
        findsNothing,
        reason: 'clearing took it off the Unread view without touching seenAt',
      );
      expect(cubit.state.summary.unreadTotal, 0);

      // The read axis: on All, and still rendered unread.
      await tester.tap(find.byKey(const ValueKey<String>('updates-all')));
      await _drain();
      await tester.pumpAndSettle();
      expect(cubit.state.view, AttentionView.all);
      final row = find.bySemanticsIdentifier(
        TestIds.updatesReceipt('r-cleared'),
      );
      expect(row, findsOneWidget, reason: 'clearing is not deletion (§9)');
      expect(
        cubit.state.items.single.isSeen,
        isFalse,
        reason: 'the clear never wrote seen_at',
      );
      expect(
        _headlineWeightIn(tester, row),
        FontWeight.w600,
        reason: 'the row chrome is the read axis, and it still reads unread',
      );

      unawaited(cubit.close());
      unawaited(attention.dispose());
      unawaited(sync.port.dispose());
      unawaited(accounts.close());
    },
  );
}

/// The headline's weight — `w600` when the tile considers the row unread.
FontWeight? _headlineWeightIn(WidgetTester tester, Finder row) {
  final text = tester.widget<Text>(
    find
        .descendant(of: row, matching: find.byType(Text))
        .first,
  );
  return text.textSpan?.style?.fontWeight;
}

AttentionReceipt _receipt({required String id, DateTime? clearedAt}) =>
    AttentionReceipt(
      id: id,
      category: 'asksOfMe',
      kind: 'needsMe',
      priority: 'normal',
      title: 'Cleared but never read',
      body: 'Body',
      actionUrl: '/#/',
      createdAt: DateTime.utc(2026, 9, 18),
      collapsedCount: 1,
      presentationPayloadJson: '{}',
      beaconId: 'B-$id',
      surface: AttentionSurface.activity,
      clearedAt: clearedAt,
    );

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _ViewRepository extends AttentionRepositoryFake {
  _ViewRepository({required this.itemsByView, required this.summary});

  final Map<AttentionView, List<AttentionReceipt>> itemsByView;
  final AttentionSummary summary;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => AttentionFeed(
    summary: summary,
    page: AttentionFeedPage(items: itemsByView[view] ?? const []),
  );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

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

Future<void> _drain([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

Widget _wrap(Widget child) => MediaQuery(
  data: const MediaQueryData(size: Size(800, 800)),
  child: TenturaResponsiveScope(
    child: MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      home: Scaffold(body: child),
    ),
  ),
);
