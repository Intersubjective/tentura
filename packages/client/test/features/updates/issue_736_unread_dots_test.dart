import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../block/support/controllable_block_case.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import 'support/mark_unread_server_fake.dart';
import 'support/noop_invite_setup_port.dart';

/// #736b (Vadim: option A) — "Unread 7" while only 2 rows had a dot. The
/// Unread view and its count are the clear axis (every row not cleared); the
/// dot was the read axis, so a row that had been opened but not cleared sat
/// on Unread with no dot. On the Unread view every row now carries the dot,
/// so the dots add up to the count. All keeps the read-axis dot.
void main() {
  testWidgets('on Unread every row has a dot and the dots equal the count', (
    tester,
  ) async {
    final server = MarkUnreadServerFake([
      markUnreadTestReceipt('r1', minute: 4),
      markUnreadTestReceipt('r2', minute: 3, seen: false),
      markUnreadTestReceipt('r3', minute: 2),
      markUnreadTestReceipt('r4', minute: 1, cleared: true),
    ]);
    final accounts = _Accounts();
    final sync = buildTestRealtimeSync();
    final attention = AttentionCase(
      server,
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('updates-unread-dots-736'),
    );
    final cubit = UpdatesFeedCubit(
      destinationId: AttentionFeedDestinationId.activityStream,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('updates-unread-dots-736-cubit'),
      actorProfiles: buildNoopAttentionActorProfiles(),
    );
    accounts.emit('viewer');
    await _drain();

    await tester.pumpWidget(
      _wrap(BlocProvider.value(value: cubit, child: const UpdatesFeedPane())),
    );
    await tester.pump();
    await tester.pump();
    await _drain();
    await tester.pumpAndSettle();

    // Guard: All keeps the read axis — only the row never opened has a dot.
    expect(cubit.state.view, AttentionView.all);
    expect(
      find.bySemanticsIdentifier(TestIds.updatesReceipt('r4')),
      findsOneWidget,
    );
    expect(find.byKey(UpdatesFeedTile.unreadDotKey), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('updates-unread')));
    await _drain();
    await tester.pumpAndSettle();
    await _drain();
    await tester.pumpAndSettle();

    expect(cubit.state.view, AttentionView.unread);
    expect(cubit.state.summary.unreadTotal, 3);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('updates-unread')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    for (final id in ['r1', 'r2', 'r3']) {
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(TestIds.updatesReceipt(id)),
          matching: find.byKey(UpdatesFeedTile.unreadDotKey),
        ),
        findsOneWidget,
        reason: '$id is on Unread, so it carries the dot',
      );
    }
    expect(
      find.byKey(UpdatesFeedTile.unreadDotKey),
      findsNWidgets(cubit.state.summary.unreadTotal),
    );

    unawaited(cubit.close());
    unawaited(attention.dispose());
    unawaited(sync.port.dispose());
    unawaited(accounts.close());
  });

  testWidgets('a read, uncleared row has a dot only on the Unread view', (
    tester,
  ) async {
    final receipt = markUnreadTestReceipt('r1', minute: 1);
    await tester.pumpWidget(
      _wrap(
        UpdatesFeedTile(
          receipt: receipt,
          onTap: () {},
          onMarkSeen: () {},
          onMarkUnseen: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(UpdatesFeedTile.unreadDotKey), findsNothing);

    await tester.pumpWidget(
      _wrap(
        UpdatesFeedTile(
          receipt: receipt,
          onTap: () {},
          onMarkSeen: () {},
          onMarkUnseen: () {},
          unreadView: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(UpdatesFeedTile.unreadDotKey), findsOneWidget);
  });

  testWidgets('an unread row has the bold title', (tester) async {
    await tester.pumpWidget(
      _wrap(
        UpdatesFeedTile(
          receipt: markUnreadTestReceipt('r1', minute: 1, seen: false),
          onTap: () {},
          onMarkSeen: () {},
          onMarkUnseen: () {},
          unreadView: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_boldTitle, findsOneWidget);
  });

  testWidgets(
    'on Unread a read, uncleared row keeps its read look and menu',
    (tester) async {
      final receipt = markUnreadTestReceipt('r1', minute: 1);
      await tester.pumpWidget(
        _wrap(
          UpdatesFeedTile(
            receipt: receipt,
            onTap: () {},
            onMarkSeen: () {},
            onMarkUnseen: () {},
            unreadView: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = L10n.of(
        tester.element(find.byType(UpdatesFeedTile)),
      )!;

      expect(find.byKey(UpdatesFeedTile.unreadDotKey), findsOneWidget);
      // The title stays at the read weight (an unread title is w600).
      expect(_boldTitle, findsNothing);

      await tester.tap(find.byTooltip(l10n.updatesRowMenuTooltip));
      await tester.pumpAndSettle();
      expect(find.text(l10n.updatesMarkUnseen), findsOneWidget);
      expect(find.text(l10n.attentionEventDismiss), findsOneWidget);
      expect(find.text(l10n.updatesMarkSeen), findsNothing);
    },
  );
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

/// The row title written with [Text.rich] at the unread weight.
final _boldTitle = find.byWidgetPredicate(
  (w) => w is Text && w.textSpan?.style?.fontWeight == FontWeight.w600,
);

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
