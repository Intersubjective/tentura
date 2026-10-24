import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../block/support/controllable_block_case.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import 'support/mark_seen_server_fake.dart';
import 'support/noop_invite_setup_port.dart';

/// #601 / #258 (plan row V2) — "Read all" reads **and** clears the active
/// optional rows, like the per-item "Mark seen"; obligations stay put. The
/// clear is one bounded server sweep (`AttentionCase.dismissAll`). A single
/// clear the server answers `stale` or `denied` is said in a muted line, not
/// an error and not silence; inside Read all it is not said at all.
void main() {
  group('UpdatesFeedCubit.markAllSeen clears optional rows (#601)', () {
    test(
      'two optional + one obligation: Read all leaves Unread with only the '
      'obligation',
      () async {
        final server = MarkSeenServerFake([
          markSeenTestReceipt('r1', minute: 3),
          markSeenTestReceipt('r2', minute: 2),
          markSeenTestReceipt('o1', minute: 1).copyWith(requiresAction: true),
        ]);
        final c = await _Client.open(server, view: AttentionView.unread);
        expect(_ids(c.cubit), ['r1', 'r2', 'o1']);
        expect(c.cubit.state.summary.unreadTotal, 3);

        expect(await c.cubit.markAllSeen(), isTrue);
        await _settle();

        expect(c.cubit.state.actionError, isNull);
        expect(
          _ids(c.cubit),
          ['o1'],
          reason: 'Read all must take the optional rows off Unread',
        );
        expect(c.cubit.state.summary.unreadTotal, 1);
        expect(server.row('r1').seenAt, isNotNull, reason: 'still a read');
        expect(server.row('r1').clearedAt, isNotNull);
        expect(server.row('r2').clearedAt, isNotNull);
        expect(
          server.row('o1').clearedAt,
          isNull,
          reason: 'an obligation is never cleared by Read all',
        );
        expect(server.row('o1').settlementKind, isNull);
        // Review of #707: one bounded server sweep, not one clear per row.
        expect(server.dismissAllOperationIds, hasLength(1));
        expect(server.clearRequestedIds, isEmpty);

        await c.close();

        final reloaded = await _Client.open(
          server,
          view: AttentionView.unread,
        );
        expect(_ids(reloaded.cubit), ['o1'], reason: 'and after a reload');
        await reloaded.close();
      },
    );

    test('Read all also clears optional rows not loaded on screen', () async {
      final server = MarkSeenServerFake([
        markSeenTestReceipt('r1', minute: 3),
        markSeenTestReceipt('o1', minute: 1).copyWith(requiresAction: true),
      ]);
      // Needs you lists only the obligation, so r1 is not in the cubit's rows.
      final c = await _Client.open(server, view: AttentionView.needsYou);
      expect(_ids(c.cubit), ['o1']);

      expect(await c.cubit.markAllSeen(), isTrue);
      await _settle();

      expect(server.row('r1').clearedAt, isNotNull);
      expect(server.row('o1').clearedAt, isNull);
      expect(server.row('o1').seenAt, isNotNull, reason: 'still a read');
      expect(server.dismissAllOperationIds, hasLength(1));
      await c.close();
    });

    test('guard: a complete clear says nothing extra', () async {
      final server = MarkSeenServerFake([markSeenTestReceipt('r1', minute: 2)]);
      final c = await _Client.open(server, view: AttentionView.unread);
      final notices = <UpdatesClearNotice>[];
      final sub = c.cubit.clearNotices.listen(notices.add);

      expect(await c.cubit.markSeen('r1'), isTrue);
      expect(await c.cubit.markAllSeen(), isTrue);
      await _settle();

      expect(notices, isEmpty);
      expect(c.cubit.state.actionError, isNull);
      await sub.cancel();
      await c.close();
    });
  });

  group('Read all clears already-read rows the sweep does not take (#711)', () {
    AttentionReceipt deskRow(
      String id, {
      required int minute,
      String? beacon,
    }) => markSeenTestReceipt(id, minute: minute).copyWith(
      surface: AttentionSurface.myWork,
      beaconId: beacon,
      presentationKey: 'plan_updated',
      seenAt: DateTime.utc(2026, 10, 14, 8),
    );

    test(
      'read optional My Desk rows leave Unread and stay gone after a reload',
      () async {
        final server = MarkSeenServerFake([
          deskRow('p1', minute: 6, beacon: 'B1'),
          deskRow('p2', minute: 5, beacon: 'B1'),
          deskRow('w1', minute: 4, beacon: 'B2'),
          deskRow('n1', minute: 3),
          markSeenTestReceipt('r1', minute: 2),
          markSeenTestReceipt(
            'o1',
            minute: 1,
          ).copyWith(
            surface: AttentionSurface.myWork,
            beaconId: 'B1',
            requiresAction: true,
          ),
        ]);
        final c = await _Client.open(server, view: AttentionView.unread);
        expect(_ids(c.cubit), ['p1', 'p2', 'w1', 'n1', 'r1', 'o1']);

        expect(await c.cubit.markAllSeen(), isTrue);
        await _settle();

        expect(c.cubit.state.actionError, isNull);
        for (final id in ['p1', 'p2', 'w1', 'n1', 'r1']) {
          expect(server.row(id).clearedAt, isNotNull, reason: id);
        }
        expect(
          server.row('o1').clearedAt,
          isNull,
          reason: 'an obligation is never cleared by Read all',
        );
        expect(server.dismissAllOperationIds, hasLength(1));
        await c.close();

        final reloaded = await _Client.open(
          server,
          view: AttentionView.unread,
        );
        expect(_ids(reloaded.cubit), ['o1']);
        expect(reloaded.cubit.state.summary.unreadTotal, 1);

        // A second Read all has nothing left to clear and still succeeds.
        expect(await reloaded.cubit.markAllSeen(), isTrue);
        await _settle();
        expect(_ids(reloaded.cubit), ['o1']);
        await reloaded.close();
      },
    );

    test('Read all clears them even when they are not on screen', () async {
      final server = MarkSeenServerFake([
        deskRow('p1', minute: 3, beacon: 'B1'),
        markSeenTestReceipt('o1', minute: 1).copyWith(requiresAction: true),
      ]);
      final c = await _Client.open(server, view: AttentionView.needsYou);
      expect(_ids(c.cubit), ['o1']);

      expect(await c.cubit.markAllSeen(), isTrue);
      await _settle();

      expect(server.row('p1').clearedAt, isNotNull);
      expect(server.row('o1').clearedAt, isNull);
      await c.close();
    });

    test('guard: Mark seen on a read My Desk row clears it', () async {
      final server = MarkSeenServerFake([
        deskRow('p1', minute: 2, beacon: 'B1'),
      ]);
      final c = await _Client.open(server, view: AttentionView.unread);

      expect(await c.cubit.markSeen('p1'), isTrue);
      await _settle();

      expect(server.row('p1').clearedAt, isNotNull);
      expect(_ids(c.cubit), isEmpty);
      await c.close();
    });
  });

  group('stale / denied clears are surfaced, muted (#601)', () {
    for (final (status, notice) in [
      (AttentionOperationStatus.stale, UpdatesClearNotice.stale),
      (AttentionOperationStatus.denied, UpdatesClearNotice.denied),
    ]) {
      test('Mark seen answered ${status.wireName} emits $notice', () async {
        final server = MarkSeenServerFake([
          markSeenTestReceipt('r1', minute: 2),
        ])..clearStatus = status;
        final c = await _Client.open(server, view: AttentionView.unread);
        final notices = <UpdatesClearNotice>[];
        final sub = c.cubit.clearNotices.listen(notices.add);

        expect(await c.cubit.markSeen('r1'), isTrue);
        await _settle();

        expect(notices, [notice]);
        expect(
          c.cubit.state.actionError,
          isNull,
          reason: 'a stale/denied clear is not a failure',
        );
        await sub.cancel();
        await c.close();
      });

      // Review of #707: one stale member inside a bulk sweep is not news, so
      // the bulk path says nothing (single Mark seen still does).
      test('Read all answered ${status.wireName} says nothing', () async {
        final server = MarkSeenServerFake([
          markSeenTestReceipt('r1', minute: 3),
          markSeenTestReceipt('r2', minute: 2),
        ])..clearStatus = status;
        final c = await _Client.open(server, view: AttentionView.unread);
        final notices = <UpdatesClearNotice>[];
        final sub = c.cubit.clearNotices.listen(notices.add);

        expect(await c.cubit.markAllSeen(), isTrue);
        await _settle();

        expect(notices, isEmpty);
        expect(c.cubit.state.actionError, isNull);
        await sub.cancel();
        await c.close();
      });
    }
  });

  testWidgets('a stale clear on Read all shows no line and no error', (
    tester,
  ) async {
    final server = MarkSeenServerFake([markSeenTestReceipt('r1', minute: 2)])
      ..clearStatus = AttentionOperationStatus.stale;
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
    final l10n = L10n.of(tester.element(find.byType(UpdatesFeedPane)))!;

    await tester.tap(find.text(l10n.updatesMarkAllSeen));
    await _drain();
    await tester.pump();
    await _drain();
    await tester.pump();

    expect(_snackBar(l10n.updatesClearStale), findsNothing);
    expect(_snackBar(l10n.updatesMarkAllSeenFailed), findsNothing);
    expect(client.cubit.state.actionError, isNull);

    unawaited(client.cubit.close());
    unawaited(client.attention.dispose());
    unawaited(client.sync.port.dispose());
    unawaited(client.accounts.close());
  });
}

Finder _snackBar(String text) => find.descendant(
  of: find.byType(SnackBar),
  matching: find.text(text, findRichText: true),
);

List<String> _ids(UpdatesFeedCubit cubit) =>
    cubit.state.items.map((r) => r.id).toList(growable: false);

final class _Client {
  _Client._(this.accounts, this.sync, this.attention, this.cubit);

  factory _Client.build(MarkSeenServerFake server) {
    final accounts = _Accounts();
    final sync = buildTestRealtimeSync();
    final attention = AttentionCase(
      server,
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('updates-read-all-601'),
    );
    final cubit = UpdatesFeedCubit(
      destinationId: AttentionFeedDestinationId.history,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('updates-read-all-601-cubit'),
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
