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

/// #736 round 3 — Alice opened the Request, which clears its optional rows
/// (the clear axis) without reading them (the read axis). "Bob accepted your
/// invite" and "Carol can't make it" left Unread (Unread 2) but kept their
/// dots on All: 4 dots against Unread 2. A row with a dot must be on Unread
/// and counted, so a cleared row carries no dot.
void main() {
  testWidgets('a cleared, unread row has no dot on All', (tester) async {
    await tester.pumpWidget(
      _wrap(
        UpdatesFeedTile(
          receipt: markUnreadTestReceipt(
            'r1',
            minute: 1,
            seen: false,
            cleared: true,
          ),
          onTap: () {},
          onMarkSeen: () {},
          onMarkUnseen: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(UpdatesFeedTile.unreadDotKey), findsNothing);
  });

  testWidgets('on All the dots equal the Unread count after a Request open', (
    tester,
  ) async {
    final server = MarkUnreadServerFake([
      // The two "Created an account" rows: unread and not cleared.
      markUnreadTestReceipt('account-1', minute: 4, seen: false),
      markUnreadTestReceipt('account-2', minute: 3, seen: false),
      // The invite answers, cleared by opening the Request but never read.
      markUnreadTestReceipt(
        'invite-ok',
        minute: 2,
        seen: false,
        cleared: true,
      ),
      markUnreadTestReceipt(
        'invite-no',
        minute: 1,
        seen: false,
        cleared: true,
      ),
    ]);
    final accounts = _Accounts();
    final sync = buildTestRealtimeSync();
    final attention = AttentionCase(
      server,
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('updates-cleared-dot-736'),
    );
    final cubit = UpdatesFeedCubit(
      destinationId: AttentionFeedDestinationId.activityStream,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('updates-cleared-dot-736-cubit'),
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

    expect(cubit.state.view, AttentionView.all);
    expect(cubit.state.summary.unreadTotal, 2);
    for (final id in ['invite-ok', 'invite-no']) {
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(TestIds.updatesReceipt(id)),
          matching: find.byKey(UpdatesFeedTile.unreadDotKey),
        ),
        findsNothing,
        reason: '$id is not on Unread, so it has no dot',
      );
    }
    expect(find.byKey(UpdatesFeedTile.unreadDotKey), findsNWidgets(2));

    unawaited(cubit.close());
    unawaited(attention.dispose());
    unawaited(sync.port.dispose());
    unawaited(accounts.close());
  });
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
