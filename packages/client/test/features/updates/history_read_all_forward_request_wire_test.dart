@Tags(['pg', 'repo-files'])
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../domain/attention/attention_case_test_support.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/production_receipt_transport.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'support/noop_invite_setup_port.dart';

// «Read all» in History with a Request forwarded to the viewer. Real path:
// production GraphQL server on Postgres -> Ferry -> repository -> case ->
// cubit -> tiles. A reload is a new case and cubit over the same server
// state. Browser page-reload behaviour needs the web integration runner.
const _viewer = 'Ua00000000005';
const _forwardId = 'Nfwdrelay00001';
const _plainId = 'Nfwdplain00001';

Future<void> _until(bool Function() ready, {Object? Function()? why}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out: ${why?.call()}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// A History cubit over its own [AttentionCase], like a freshly opened app.
final class _Session {
  _Session._(this.remote, this.accounts, this.sync, this.attention, this.cubit);

  final RemoteApiService remote;
  final AttentionCaseTestAccounts accounts;
  final ({RealtimeSyncCase case_, TestRealtimeSyncPort port}) sync;
  final AttentionCase attention;
  final UpdatesFeedCubit cubit;

  static Future<_Session> open() async {
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
    );
    await remote.setSessionAuth();
    final accounts = AttentionCaseTestAccounts();
    final sync = buildTestRealtimeSync();
    final attention = AttentionCase(
      AttentionRepository(remote),
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('history-read-all-forward'),
    );
    accounts.emit(_viewer);
    await Future<void>.delayed(Duration.zero);
    final cubit = UpdatesFeedCubit(
      destinationId: AttentionFeedDestinationId.history,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('history-read-all-forward-cubit'),
      actorProfiles: buildNoopAttentionActorProfiles(),
    );
    await _until(() => cubit.state.firstLoadDone, why: () => 'History load');
    return _Session._(remote, accounts, sync, attention, cubit);
  }

  Future<void> close() async {
    await cubit.close();
    await attention.dispose();
    await sync.port.dispose();
    await accounts.dispose();
    await remote.close();
  }
}

Future<void> _withServer(
  WidgetTester tester,
  Future<void> Function() body,
) =>
    tester.runAsync(() async {
          final transport = await ProductionReceiptTransport.start(
            forwardRequestFixture: true,
          );
          try {
            await http.runWithClient(
              body,
              () => MockClient((request) async {
                if (request.url.path.endsWith('/session/access-token')) {
                  return http.Response(
                    jsonEncode({
                      'subject': _viewer,
                      'access_token': 'test-token',
                      'expires_in': 3600,
                    }),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }
                return transport.graphql(
                  _viewer,
                  jsonDecode(request.body) as Map<String, dynamic>,
                );
              }),
            );
          } finally {
            await transport.close();
          }
        })
        as Future<void>;

Future<void> _expectHistoryRead(
  UpdatesFeedCubit cubit, {
  required String reason,
}) async {
  // The Read all gate also follows the surface summary, which loads async.
  await _until(() => !cubit.state.canReadAll, why: () => cubit.state);
  final forward = cubit.state.items.where((r) => r.id == _forwardId);
  expect(forward, hasLength(1), reason: '$reason: forward item is listed');
  expect(forward.single.isSeen, isTrue, reason: '$reason: forward item read');
  expect(
    cubit.state.items.where((r) => !r.isSeen).map((r) => r.id),
    isEmpty,
    reason: '$reason: no History item is unread',
  );
  expect(cubit.state.summary.unreadTotal, 0, reason: '$reason: unread count');
  expect(cubit.state.canReadAll, isFalse, reason: '$reason: Read all gate');
}

Future<void> _pump(WidgetTester tester, UpdatesFeedCubit cubit) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: const UpdatesFeedPane(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Read all marks the forwarded-Request item read and the unread count 0',
    (tester) async {
      await _withServer(tester, () async {
        final session = await _Session.open();
        try {
          final cubit = session.cubit;
          expect(
            cubit.state.items.map((r) => r.id),
            containsAll([_forwardId, _plainId]),
          );
          expect(cubit.state.summary.unreadTotal, 2, reason: 'precondition');
          expect(cubit.state.canReadAll, isTrue, reason: 'precondition');

          expect(await cubit.markAllSeen(), isTrue);
          await _until(
            () => cubit.state.summary.unreadTotal == 0,
            why: () => cubit.state,
          );

          await _expectHistoryRead(cubit, reason: 'after Read all');
        } finally {
          await session.close();
        }
      });
    },
  );

  testWidgets(
    'after Read all a freshly opened History still shows the forwarded '
    'Request read with an unread count of 0',
    (tester) async {
      await _withServer(tester, () async {
        final first = await _Session.open();
        try {
          expect(await first.cubit.markAllSeen(), isTrue);
        } finally {
          await first.close();
        }

        final reloaded = await _Session.open();
        try {
          await _expectHistoryRead(reloaded.cubit, reason: 'after reload');
        } finally {
          await reloaded.close();
        }
      });
    },
  );

  testWidgets(
    'tapping Read all leaves the forwarded-Request row without an unread '
    'dot and the History badge without a count',
    (tester) async {
      await _withServer(tester, () async {
        final session = await _Session.open();
        try {
          await _pump(tester, session.cubit);
          final forwardDot = find.descendant(
            of: find.bySemanticsIdentifier(TestIds.updatesReceipt(_forwardId)),
            matching: find.byKey(UpdatesFeedTile.unreadDotKey),
          );
          final badge = find.descendant(
            of: find.byKey(const ValueKey<String>('updates-unread')),
            matching: find.textContaining(RegExp(r'\d')),
          );
          expect(forwardDot, findsOneWidget, reason: 'precondition: dotted');
          expect(badge, findsOneWidget, reason: 'precondition: count shown');

          await tester.tap(find.text('Read all'));
          await _until(
            () => session.cubit.state.summary.unreadTotal == 0,
            why: () => session.cubit.state,
          );
          await _pump(tester, session.cubit);

          expect(forwardDot, findsNothing);
          expect(find.byKey(UpdatesFeedTile.unreadDotKey), findsNothing);
          expect(badge, findsNothing);
        } finally {
          await session.close();
        }
      });
    },
  );
}
