import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
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
import 'support/mark_unread_server_fake.dart';
import 'support/noop_invite_setup_port.dart';

/// #601 (option B, Vadim 2026-10-22) — "Mark unread" on a cleared (Done)
/// Updates item must put it back under Unread, through the server's new
/// un-clear command `attentionMarkUnread` (port `markUnread`), and survive a
/// reload. Today it only calls `attentionMarkUnseen`, which moves the read
/// dot and leaves `cleared_at` set, so the item never returns to Unread.
///
/// Guards: an item that was only read (not cleared) ends unread and stays on
/// Unread via either command; a failed un-clear rolls back. Obligations
/// (requires_action) can never be cleared (clear_optional_only_chk), so no
/// test for un-clearing them exists or can be set up.
void main() {
  group('UpdatesFeedCubit.markUnseen on a cleared item (#601)', () {
    test(
      'un-clears it on the server, it shows under Unread, and it persists '
      'after reload',
      () async {
        final server = MarkUnreadServerFake([
          markUnreadTestReceipt('r1', minute: 2, cleared: true),
          markUnreadTestReceipt('r2', minute: 1, seen: false),
        ]);
        final first = await _Client.open(server, view: AttentionView.all);
        expect(_ids(first.cubit), ['r1', 'r2']);
        expect(
          first.cubit.state.summary.unreadTotal,
          1,
          reason: 'precondition: the cleared item is not counted as unread',
        );

        final ok = await first.cubit.markUnseen('r1');
        await _settle();

        expect(ok, isTrue);
        expect(first.cubit.state.actionError, isNull);
        expect(
          server.markUnreadIds,
          ['r1'],
          reason: 'Mark unread on a cleared item must send the un-clear '
              'command (attentionMarkUnread), not only the read dot',
        );
        expect(server.row('r1').clearedAt, isNull);
        expect(server.row('r1').seenAt, isNull);

        final r1 = first.cubit.state.items.singleWhere((r) => r.id == 'r1');
        expect(r1.isSeen, isFalse, reason: 'it renders unread on All');
        expect(r1.isCleared, isFalse);

        await first.cubit.setView(AttentionView.unread);
        await _settle();
        expect(
          _ids(first.cubit),
          ['r1', 'r2'],
          reason: 'the item marked unread is back on the Unread tab',
        );
        expect(first.cubit.state.summary.unreadTotal, 2);

        await first.close();

        final reloaded = await _Client.open(
          server,
          view: AttentionView.unread,
        );
        expect(
          _ids(reloaded.cubit),
          ['r1', 'r2'],
          reason: 'after a reload the item is still under Unread',
        );
        expect(reloaded.cubit.state.summary.unreadTotal, 2);
        await reloaded.close();
      },
    );

    test(
      'guard: an item that was only read becomes unread and stays on Unread',
      () async {
        final server = MarkUnreadServerFake([
          markUnreadTestReceipt('r3', minute: 3),
        ]);
        final client = await _Client.open(server, view: AttentionView.unread);
        expect(_ids(client.cubit), ['r3']);

        expect(await client.cubit.markUnseen('r3'), isTrue);
        await _settle();

        // Either command is a valid route for a read, uncleared item: the
        // read-axis attentionMarkUnseen, or always attentionMarkUnread
        // (which on an uncleared row only nulls seen_at).
        expect(
          [...server.markUnseenIds, ...server.markUnreadIds],
          contains('r3'),
        );
        expect(server.row('r3').seenAt, isNull);
        expect(server.row('r3').clearedAt, isNull);
        expect(_ids(client.cubit), ['r3']);
        expect(
          client.cubit.state.items.singleWhere((r) => r.id == 'r3').isSeen,
          isFalse,
        );
        await client.close();
      },
    );

    test(
      'guard: a failed un-clear reports the error and leaves the item '
      'cleared, off Unread',
      () async {
        final server = MarkUnreadServerFake([
          markUnreadTestReceipt('r1', minute: 2, cleared: true),
          markUnreadTestReceipt('r2', minute: 1, seen: false),
        ]);
        final client = await _Client.open(server, view: AttentionView.all);
        server.failWrites = true;

        expect(await client.cubit.markUnseen('r1'), isFalse);
        await _settle();

        expect(client.cubit.state.actionError, isNotNull);
        expect(server.row('r1').clearedAt, isNotNull);
        final r1 = client.cubit.state.items.singleWhere((r) => r.id == 'r1');
        expect(
          r1.isCleared,
          isTrue,
          reason: 'an optimistic un-clear must be rolled back on failure',
        );
        expect(client.cubit.state.summary.unreadTotal, 1);

        await client.cubit.setView(AttentionView.unread);
        await _settle();
        expect(_ids(client.cubit), ['r2']);
        await client.close();
      },
    );

    test(
      'guard: a server that un-clears nothing reports the error and leaves '
      'the item cleared, off Unread',
      () async {
        final server = MarkUnreadServerFake([
          markUnreadTestReceipt('r1', minute: 2, cleared: true),
          markUnreadTestReceipt('r2', minute: 1, seen: false),
        ]);
        final client = await _Client.open(server, view: AttentionView.all);
        server.unreadChangesNothing = true;

        expect(
          await client.cubit.markUnseen('r1'),
          isFalse,
          reason: 'an un-clear the server ignored (0 rows) is a failure',
        );
        await _settle();

        expect(server.markUnreadIds, ['r1']);
        expect(client.cubit.state.actionError, isNotNull);
        expect(server.row('r1').clearedAt, isNotNull);
        final r1 = client.cubit.state.items.singleWhere((r) => r.id == 'r1');
        expect(r1.isCleared, isTrue);
        expect(client.cubit.state.summary.unreadTotal, 1);

        await client.cubit.setView(AttentionView.unread);
        await _settle();
        expect(_ids(client.cubit), ['r2']);
        await client.close();
      },
    );
  });

  testWidgets(
    'row overflow → "Mark unread" on a cleared item brings it back to the '
    'Unread tab and raises the badge (#601)',
    (tester) async {
      final server = MarkUnreadServerFake([
        markUnreadTestReceipt('r1', minute: 2, cleared: true),
        markUnreadTestReceipt('r2', minute: 1, seen: false),
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
      await _drain();
      await tester.pumpAndSettle();

      expect(client.cubit.state.view, AttentionView.all);
      final row = find.bySemanticsIdentifier(TestIds.updatesReceipt('r1'));
      expect(row, findsOneWidget);
      expect(_unreadTabCount('1'), findsOneWidget);

      final l10n = L10n.of(tester.element(find.byType(UpdatesFeedPane)))!;
      final overflow = find.descendant(
        of: row,
        matching: find.byType(PopupMenuButton<void>),
      );
      expect(overflow, findsOneWidget);
      await tester.tap(overflow);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.updatesMarkUnseen).last);
      await _drain();
      await tester.pumpAndSettle();
      await _drain();
      await tester.pumpAndSettle();

      expect(server.markUnreadIds, ['r1']);

      await tester.tap(find.byKey(const ValueKey<String>('updates-unread')));
      await _drain();
      await tester.pumpAndSettle();
      await _drain();
      await tester.pumpAndSettle();

      expect(client.cubit.state.view, AttentionView.unread);
      expect(
        find.bySemanticsIdentifier(TestIds.updatesReceipt('r1')),
        findsOneWidget,
        reason: 'the item marked unread is listed under Unread',
      );
      expect(
        _unreadTabCount('2'),
        findsOneWidget,
        reason: 'the Unread tab counter goes 1 → 2',
      );

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

List<String> _ids(UpdatesFeedCubit cubit) =>
    cubit.state.items.map((r) => r.id).toList(growable: false);

final class _Client {
  _Client._(this.accounts, this.sync, this.attention, this.cubit);

  factory _Client.build(MarkUnreadServerFake server) {
    final accounts = _Accounts();
    final sync = buildTestRealtimeSync();
    final attention = AttentionCase(
      server,
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('updates-mark-unread-601'),
    );
    final cubit = UpdatesFeedCubit(
      destinationId: AttentionFeedDestinationId.history,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('updates-mark-unread-601-cubit'),
      actorProfiles: buildNoopAttentionActorProfiles(),
    );
    return _Client._(accounts, sync, attention, cubit);
  }

  static Future<_Client> open(
    MarkUnreadServerFake server, {
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
