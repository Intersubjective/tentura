import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../block/support/controllable_block_case.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import 'support/mark_seen_server_fake.dart';
import 'support/noop_invite_setup_port.dart';

/// #601 (from #336) — "Mark seen" says when it fails, but "Mark unread",
/// "Read all" and "Mark done" only set `actionError`, which nothing shows:
/// a refused action looked like a silent no-op.
void main() {
  testWidgets('a failed "Mark unread" shows an error snackbar', (
    tester,
  ) async {
    final h = await _Harness.start(tester, [
      markSeenTestReceipt(
        'r1',
        minute: 2,
      ).copyWith(seenAt: DateTime.utc(2026, 10, 14, 9, 3)),
    ]);
    final row = find.bySemanticsIdentifier(TestIds.updatesReceipt('r1'));
    expect(row, findsOneWidget);

    await tester.tap(
      find.descendant(of: row, matching: find.byType(PopupMenuButton<void>)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(h.l10n.updatesMarkUnseen).last);
    await h.settle();

    expect(_snackBar(h.l10n.updatesMarkUnseenFailed), findsOneWidget);
    expect(h.cubit.state.hasActionError, isTrue);
    expect(h.server.row('r1').seenAt, isNotNull);
    await h.dispose();
  });

  testWidgets('a failed "Read all" shows an error snackbar', (tester) async {
    final h = await _Harness.start(tester, [
      markSeenTestReceipt('r1', minute: 2),
    ]);
    expect(h.cubit.state.summary.unreadTotal, 1);

    await tester.tap(find.text(h.l10n.updatesMarkAllSeen));
    await h.settle();

    expect(_snackBar(h.l10n.updatesMarkAllSeenFailed), findsOneWidget);
    expect(h.server.row('r1').seenAt, isNull);
    await h.dispose();
  });

  testWidgets('a failed "Mark done" shows an error snackbar', (tester) async {
    final h = await _Harness.start(tester, [
      markSeenTestReceipt('r1', minute: 2).copyWith(requiresAction: true),
    ]);
    final row = find.bySemanticsIdentifier(TestIds.updatesReceipt('r1'));
    expect(row, findsOneWidget);

    await tester.tap(
      find.descendant(of: row, matching: find.text(h.l10n.updatesMarkDone)),
    );
    await h.settle();

    expect(_snackBar(h.l10n.updatesMarkDoneFailed), findsOneWidget);
    expect(h.server.row('r1').settlementKind, isNull);
    await h.dispose();
  });

  test('guard: the cubit reports success and failure to its caller', () async {
    for (final fail in [false, true]) {
      final server = MarkSeenServerFake([
        markSeenTestReceipt(
          'r1',
          minute: 2,
        ).copyWith(seenAt: DateTime.utc(2026, 10, 14, 9, 3)),
      ])..failWrites = fail;
      final accounts = _Accounts();
      final sync = buildTestRealtimeSync();
      final attention = _attention(server, accounts, sync);
      final cubit = _cubit(attention, sync);
      accounts.emit('viewer');
      await _drain();

      expect(await cubit.markUnseen('r1'), !fail);
      expect(await cubit.markAllSeen(), !fail);
      expect(cubit.state.hasActionError, fail);

      await cubit.close();
      unawaited(attention.dispose());
      unawaited(sync.port.dispose());
      unawaited(accounts.close());
    }
  });
}

typedef _Sync = ({RealtimeSyncCase case_, TestRealtimeSyncPort port});

Finder _snackBar(String text) => find.descendant(
  of: find.byType(SnackBar),
  matching: find.text(text, findRichText: true),
);

AttentionCase _attention(
  MarkSeenServerFake server,
  _Accounts accounts,
  _Sync sync,
) => AttentionCase(
  server,
  accounts,
  sync.case_,
  noopBlockCase(),
  FeedSessionRegistry(),
  Logger('updates-action-failure-601'),
);

UpdatesFeedCubit _cubit(AttentionCase attention, _Sync sync) =>
    UpdatesFeedCubit(
      destinationId: AttentionFeedDestinationId.history,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('updates-action-failure-601-cubit'),
      actorProfiles: buildNoopAttentionActorProfiles(),
    );

final class _Harness {
  _Harness._(
    this.tester,
    this.server,
    this.accounts,
    this.sync,
    this.attention,
    this.cubit,
  );

  final WidgetTester tester;
  final MarkSeenServerFake server;
  final _Accounts accounts;
  final _Sync sync;
  final AttentionCase attention;
  final UpdatesFeedCubit cubit;

  L10n get l10n => L10n.of(tester.element(find.byType(UpdatesFeedPane)))!;

  static Future<_Harness> start(
    WidgetTester tester,
    List<AttentionReceipt> receipts,
  ) async {
    // `showSnackBar(isError: true)` logs through GetIt's Logger.
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('updates-action-failure-601'));
      addTearDown(() => GetIt.I.unregister<Logger>());
    }
    final server = MarkSeenServerFake(receipts);
    final accounts = _Accounts();
    final sync = buildTestRealtimeSync();
    final attention = _attention(server, accounts, sync);
    final cubit = _cubit(attention, sync);
    accounts.emit('viewer');
    await _drain();

    await tester.pumpWidget(
      _wrap(BlocProvider.value(value: cubit, child: const UpdatesFeedPane())),
    );
    await tester.pump();
    await tester.pump();
    await _drain();
    await tester.pumpAndSettle();
    // Loaded while the link was up; every write from here on fails.
    server.failWrites = true;
    return _Harness._(tester, server, accounts, sync, attention, cubit);
  }

  Future<void> settle() async {
    await _drain();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> dispose() async {
    await tester.pumpAndSettle(const Duration(seconds: 5));
    unawaited(cubit.close());
    unawaited(attention.dispose());
    unawaited(sync.port.dispose());
    unawaited(accounts.close());
  }
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
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
