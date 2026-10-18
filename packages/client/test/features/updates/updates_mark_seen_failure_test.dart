import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../block/support/controllable_block_case.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import 'support/mark_seen_server_fake.dart';
import 'support/noop_invite_setup_port.dart';

/// #336 — "No feedback (snackbar/error) is shown either." A Mark seen that
/// the server refuses must say so instead of silently doing nothing.
///
/// Needs the new l10n key `updatesMarkSeenFailed` (en + ru).
void main() {
  testWidgets(
    'a failed "Mark seen" shows an error snackbar and keeps the row (#336)',
    (tester) async {
      // `showSnackBar(isError: true)` logs through GetIt's Logger.
      if (!GetIt.I.isRegistered<Logger>()) {
        GetIt.I.registerSingleton<Logger>(Logger('updates-mark-seen-336'));
        addTearDown(() => GetIt.I.unregister<Logger>());
      }
      final server = MarkSeenServerFake([
        markSeenTestReceipt('r1', minute: 2),
      ])..failWrites = true;
      final accounts = _Accounts();
      final sync = buildTestRealtimeSync();
      final attention = AttentionCase(
        server,
        accounts,
        sync.case_,
        noopBlockCase(),
        FeedSessionRegistry(),
        Logger('updates-mark-seen-failure-336'),
      );
      final cubit = UpdatesFeedCubit(
        destinationId: AttentionFeedDestinationId.history,
        attention: attention,
        setup: NoopInviteAcceptedSetupPort(),
        realtime: sync.case_,
        logger: Logger('updates-mark-seen-failure-336-cubit'),
        actorProfiles: buildNoopAttentionActorProfiles(),
      );
      accounts.emit('viewer');
      await _drain();

      await tester.pumpWidget(
        _wrap(
          BlocProvider.value(value: cubit, child: const UpdatesFeedPane()),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('updates-unread')));
      await _drain();
      await tester.pumpAndSettle();

      final row = find.bySemanticsIdentifier(TestIds.updatesReceipt('r1'));
      expect(row, findsOneWidget);
      final l10n = L10n.of(tester.element(find.byType(UpdatesFeedPane)))!;

      await tester.tap(
        find.descendant(of: row, matching: find.byType(PopupMenuButton<void>)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.updatesMarkSeen).last);
      await _drain();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(
            l10n.updatesMarkSeenFailed,
            findRichText: true,
          ),
        ),
        findsOneWidget,
        reason: 'the failure must be visible, not a silent no-op',
      );
      expect(
        find.bySemanticsIdentifier(TestIds.updatesReceipt('r1')),
        findsOneWidget,
        reason: 'a refused Mark seen rolls back: the row stays on Unread',
      );
      expect(cubit.state.summary.unreadTotal, 1);
      expect(
        server.clearedIds,
        isEmpty,
        reason: 'nothing half-applied on the server behind the error',
      );
      expect(server.row('r1').clearedAt, isNull);
      expect(server.row('r1').seenAt, isNull);

      await tester.pumpAndSettle(const Duration(seconds: 5));
      unawaited(cubit.close());
      unawaited(attention.dispose());
      unawaited(sync.port.dispose());
      unawaited(accounts.close());
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
