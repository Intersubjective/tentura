import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
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

/// #336 — "Mark seen" on one Updates item must do what the person sees it
/// promise: the item leaves the Unread tab, the Unread count drops, and both
/// survive a reload (a fresh client over the same server state).
///
/// The Unread tab and its badge are the server's active-attention axis
/// (`isInUnreadView`, see `updates_history_axis_independence_test.dart`); a
/// bare `attentionMarkSeen` moves only `seen_at`, so on its own it changes
/// nothing the person can see on that tab. These tests pin the user-visible
/// outcome, not which mutation achieves it.
void main() {
  group('UpdatesFeedCubit.markSeen (#336)', () {
    test(
      'takes the item off Unread, drops the Unread count, and persists '
      'after reload',
      () async {
        final server = MarkSeenServerFake([
          markSeenTestReceipt('r1', minute: 2),
          markSeenTestReceipt('r2', minute: 1),
        ]);
        final first = await _Client.open(server, view: AttentionView.unread);

        expect(first.cubit.state.view, AttentionView.unread);
        expect(_ids(first.cubit), ['r1', 'r2']);
        expect(first.cubit.state.summary.unreadTotal, 2);

        await first.cubit.markSeen('r1');
        await _settle();

        expect(
          server.markSeenIds,
          contains('r1'),
          reason: 'Mark seen must still record the read (seen_at)',
        );
        expect(
          first.cubit.state.actionError,
          isNull,
          reason: 'a successful Mark seen leaves no error behind',
        );
        expect(
          _ids(first.cubit),
          ['r2'],
          reason: 'the item marked seen must leave the Unread tab',
        );
        expect(
          first.cubit.state.summary.unreadTotal,
          1,
          reason: 'the Unread counter must drop by one',
        );

        await first.close();

        // Reload: a brand-new client over the same server state.
        final reloaded = await _Client.open(
          server,
          view: AttentionView.unread,
        );
        expect(
          _ids(reloaded.cubit),
          ['r2'],
          reason: 'after a reload the item is still off Unread',
        );
        expect(reloaded.cubit.state.summary.unreadTotal, 1);
        expect(
          server.row('r1').seenAt,
          isNotNull,
          reason: 'the server row of the item marked seen is read',
        );
        expect(
          server.row('r1').clearedAt,
          isNotNull,
          reason: 'and off the server-side Unread rule (cleared)',
        );
        expect(
          server.row('r2').seenAt,
          isNull,
          reason: 'only the item acted on was touched',
        );
        expect(server.row('r2').clearedAt, isNull);

        await reloaded.cubit.setView(AttentionView.all);
        await _settle();
        final r1 = reloaded.cubit.state.items.singleWhere((r) => r.id == 'r1');
        expect(
          r1.isSeen,
          isTrue,
          reason: 'and on All it renders as read (no bold, no dot)',
        );
        expect(
          reloaded.cubit.state.items.map((r) => r.id),
          containsAll(<String>['r1', 'r2']),
          reason: 'marking seen is not deleting: All still lists it',
        );

        await reloaded.close();
      },
    );
  });

  testWidgets(
    'row overflow ⋮ → "Mark seen" on the Unread tab removes the row and '
    'drops the badge (#336)',
    (tester) async {
      final server = MarkSeenServerFake([
        markSeenTestReceipt('r1', minute: 2),
        markSeenTestReceipt('r2', minute: 1),
      ]);
      final client = _Client.build(server);
      client.accounts.emit('viewer');
      await _drain();

      await tester.pumpWidget(
        _wrap(
          BlocProvider.value(
            value: client.cubit,
            child: const UpdatesFeedPane(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('updates-unread')));
      await _drain();
      await tester.pumpAndSettle();
      expect(client.cubit.state.view, AttentionView.unread);
      final row = find.bySemanticsIdentifier(TestIds.updatesReceipt('r1'));
      expect(row, findsOneWidget);
      expect(client.cubit.state.summary.unreadTotal, 2);
      expect(_unreadTabCount('2'), findsOneWidget);

      final l10n = L10n.of(tester.element(find.byType(UpdatesFeedPane)))!;
      final overflow = find.descendant(
        of: row,
        matching: find.byType(PopupMenuButton<void>),
      );
      expect(overflow, findsOneWidget);
      await tester.tap(overflow);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.updatesMarkSeen).last);
      await _drain();
      await tester.pumpAndSettle();
      await _drain();
      await tester.pumpAndSettle();

      expect(server.markSeenIds, contains('r1'));
      expect(
        find.bySemanticsIdentifier(TestIds.updatesReceipt('r1')),
        findsNothing,
        reason: 'the row marked seen must leave the Unread tab',
      );
      expect(
        find.bySemanticsIdentifier(TestIds.updatesReceipt('r2')),
        findsOneWidget,
        reason: 'only the row acted on leaves',
      );
      expect(client.cubit.state.summary.unreadTotal, 1);
      expect(
        _unreadTabCount('1'),
        findsOneWidget,
        reason: 'the rendered Unread tab counter drops 2 → 1',
      );

      unawaited(client.cubit.close());
      unawaited(client.attention.dispose());
      unawaited(client.sync.port.dispose());
      unawaited(client.accounts.close());
    },
  );

  testWidgets(
    'tapping a row on Unread opens it read-only: marked seen, NOT cleared, '
    'stays on Unread (#336 guard)',
    (tester) async {
      final router = _StubRootRouter();
      GetIt.I.registerSingleton<RootRouter>(router);
      addTearDown(() => GetIt.I.unregister<RootRouter>());
      final server = MarkSeenServerFake([
        markSeenTestReceipt('r1', minute: 2),
        markSeenTestReceipt('r2', minute: 1),
      ]);
      final client = _Client.build(server);
      client.accounts.emit('viewer');
      await _drain();

      await tester.pumpWidget(
        _wrap(
          BlocProvider.value(
            value: client.cubit,
            child: const UpdatesFeedPane(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('updates-unread')));
      await _drain();
      await tester.pumpAndSettle();
      final row = find.bySemanticsIdentifier(TestIds.updatesReceipt('r1'));
      expect(row, findsOneWidget);

      // The row body (primary tap), not the ⋮ overflow.
      await tester.tap(
        find.descendant(of: row, matching: find.byType(InkWell)).first,
      );
      await _drain();
      await tester.pumpAndSettle();
      await _drain();
      await tester.pumpAndSettle();

      expect(router.opened, ['r1'], reason: 'the tap opened the update');
      expect(
        server.markSeenIds,
        contains('r1'),
        reason: 'opening is reading',
      );
      expect(
        server.clearRequestedIds,
        isEmpty,
        reason: 'opening must not clear (R2): only the explicit Mark seen does',
      );
      expect(server.row('r1').clearedAt, isNull);
      expect(
        find.bySemanticsIdentifier(TestIds.updatesReceipt('r1')),
        findsOneWidget,
        reason: 'an opened row stays on Unread',
      );
      expect(client.cubit.state.summary.unreadTotal, 2);
      expect(_unreadTabCount('2'), findsOneWidget);

      unawaited(client.cubit.close());
      unawaited(client.attention.dispose());
      unawaited(client.sync.port.dispose());
      unawaited(client.accounts.close());
    },
  );
}

/// The rendered count on the Unread tab (plain-text style, pane.dart).
Finder _unreadTabCount(String count) => find.descendant(
  of: find.byKey(const ValueKey<String>('updates-unread')),
  matching: find.text(count),
);

/// Records which update was opened; everything else is unused here.
class _StubRootRouter extends Mock implements RootRouter {
  final opened = <String>[];

  @override
  Future<void> openFromUpdate(AttentionReceipt receipt) async {
    opened.add(receipt.id);
  }
}

List<String> _ids(UpdatesFeedCubit cubit) =>
    cubit.state.items.map((r) => r.id).toList(growable: false);

final class _Client {
  _Client._(this.accounts, this.sync, this.attention, this.cubit);

  /// Builds without emitting an account (widget tests drive their own pump).
  factory _Client.build(MarkSeenServerFake server) {
    final accounts = _Accounts();
    final sync = buildTestRealtimeSync();
    final attention = AttentionCase(
      server,
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('updates-mark-seen-336'),
    );
    final cubit = UpdatesFeedCubit(
      destinationId: AttentionFeedDestinationId.history,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('updates-mark-seen-336-cubit'),
      actorProfiles: buildNoopAttentionActorProfiles(),
    );
    return _Client._(accounts, sync, attention, cubit);
  }

  static Future<_Client> open(
    MarkSeenServerFake server, {
    required AttentionView view,
  }) async {
    final client = _Client.build(server);
    client.accounts.emit('viewer');
    await _settle();
    await client.cubit.setView(view);
    await _settle();
    return client;
  }

  final _Accounts accounts;
  final ({RealtimeSyncCase case_, TestRealtimeSyncPort port}) sync;
  final AttentionCase attention;
  final UpdatesFeedCubit cubit;

  Future<void> close() async {
    await cubit.close();
    await attention.dispose();
    await sync.port.dispose();
    await accounts.close();
  }
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

Future<void> _settle([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
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
