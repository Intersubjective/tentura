@Tags(['pg', 'repo-files'])
library;

import 'dart:async';
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
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
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
import '../../support/phone_surface.dart';
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
  Future<void> Function() body, {
  Future<void> Function(ProductionReceiptTransport)? prepare,
  void Function(http.Response)? Function(Map<String, dynamic>)? observeRequest,
}) =>
    tester.runAsync(() async {
          final transport = await ProductionReceiptTransport.start(
            forwardRequestFixture: true,
          );
          try {
            await prepare?.call(transport);
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
                final graphql =
                    jsonDecode(request.body) as Map<String, dynamic>;
                final observeResponse = observeRequest?.call(graphql);
                final response = await transport.graphql(_viewer, graphql);
                observeResponse?.call(response);
                return response;
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

Future<void> _pump(
  WidgetTester tester,
  UpdatesFeedCubit cubit, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: locale,
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

  testWidgets(
    'Mark unread restores the closed Request card, count, and unread styling',
    (tester) async {
      await usePhoneSurface(tester);
      const closeId = 'inbox:Bfwdreq000001';
      late Completer<({Object? ids, int updated})> mutation;
      late Completer<({int unreadTotal, List<Map<String, dynamic>> items})>
      reread;
      late Completer<List<Map<String, dynamic>>> reopenedFeed;
      var reopening = false;
      final serverUnreadCard = allOf(
        containsPair('id', closeId),
        containsPair('seenAt', isNull),
      );
      final card = find.bySemanticsIdentifier(TestIds.updatesReceipt(closeId));
      final dot = find.descendant(
        of: card,
        matching: find.byKey(UpdatesFeedTile.unreadDotKey),
      );
      final unread = find.byKey(const ValueKey<String>('updates-unread'));
      final count = find.descendant(
        of: unread,
        matching: find.textContaining(RegExp(r'^\d+$')),
      );
      final title = find
          .descendant(
            of: card,
            matching: find.byWidgetPredicate(
              (widget) => widget is Text && widget.textSpan != null,
            ),
          )
          .first;

      FontWeight? titleWeight() =>
          tester.widget<Text>(title).textSpan!.style!.fontWeight;
      String? shownCount() =>
          count.evaluate().isEmpty ? null : tester.widget<Text>(count).data;

      await _withServer(
        tester,
        () async {
          final session = await _Session.open();
          late final Map<String, Object?> afterMarking;
          late final Map<String, Object?> underUnread;
          try {
            await _pump(tester, session.cubit, locale: const Locale('ru'));
            final receipt = session.cubit.state.items.singleWhere(
              (item) => item.id == closeId,
            );
            expect(
              receipt.forwardOutcome,
              AttentionForwardOutcome.closedBeforeResponse,
            );
            // The close card is uncleared, so its menu uses attentionMarkUnseen.
            expect(receipt.isCleared, isFalse);
            expect(card, findsOneWidget);
            expect(dot, findsNothing);
            expect(titleWeight(), FontWeight.w500);
            expect(shownCount(), isNull);

            await tester.tap(
              find.descendant(
                of: card,
                matching: find.byType(PopupMenuButton<void>),
              ),
            );
            await tester.pumpAndSettle();
            final markUnread = find.text('Снять отметку о прочтении');
            expect(markUnread, findsOneWidget);
            await tester.tap(markUnread);
            await tester.pumpAndSettle();

            final result = await mutation.future.timeout(
              const Duration(seconds: 15),
            );
            expect(result.ids, [closeId]);
            final serverFeed = await reread.future.timeout(
              const Duration(seconds: 15),
            );
            await _until(
              () =>
                  session.cubit.state.summary.unreadTotal ==
                  serverFeed.unreadTotal,
              why: () => session.cubit.state,
            );
            await tester.pumpAndSettle();

            expect(card, findsOneWidget);
            afterMarking = {
              'mutation result': result.updated,
              'post-mutation History All response': serverFeed.items,
              'unread dot in All': dot.evaluate().isNotEmpty,
              'title weight in All': titleWeight(),
              'unread count': shownCount(),
            };

            await tester.tap(unread);
            await tester.pumpAndSettle();
            expect(session.cubit.state.view, AttentionView.unread);
            await _until(
              () => session.attention
                  .feedSession(AttentionFeedDestinationId.history)
                  .pages
                  .containsKey(AttentionView.unread),
              why: () => session.cubit.state,
            );
            await tester.pumpAndSettle();
            underUnread = {
              'card in Unread': card.evaluate().isNotEmpty,
              'count in Unread': shownCount(),
            };

            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            await session.close();
          }

          reopening = true;
          final fresh = await _Session.open();
          try {
            final serverItems = await reopenedFeed.future.timeout(
              const Duration(seconds: 15),
            );
            await _pump(tester, fresh.cubit, locale: const Locale('ru'));
            expect(card, findsOneWidget);
            expect(tester.takeException(), isNull);
            expect(
              {
                ...afterMarking,
                ...underUnread,
                'fresh History All response': serverItems,
                'fresh cubit read state': fresh.cubit.state.items
                    .singleWhere((item) => item.id == closeId)
                    .isSeen,
                'unread dot after opening a new History': dot
                    .evaluate()
                    .isNotEmpty,
                'title weight after opening a new History': titleWeight(),
              },
              {
                'mutation result': greaterThan(0),
                'post-mutation History All response': contains(
                  serverUnreadCard,
                ),
                'unread dot in All': true,
                'title weight in All': FontWeight.w600,
                'unread count': '1',
                'card in Unread': true,
                'count in Unread': '1',
                'fresh History All response': contains(serverUnreadCard),
                'fresh cubit read state': false,
                'unread dot after opening a new History': true,
                'title weight after opening a new History': FontWeight.w600,
              },
            );
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await fresh.close();
          }
        },
        prepare: (transport) async {
          // HTTP completions are delivered outside the widget test's fake clock.
          mutation = Completer<({Object? ids, int updated})>();
          reread = Completer();
          reopenedFeed = Completer();
          Future<Object?> run(String viewer, String field, String query) async {
            final response = await transport.graphql(viewer, {'query': query});
            final body = jsonDecode(response.body) as Map<String, dynamic>;
            expect(body['errors'], isNull);
            return (body['data'] as Map)[field];
          }

          expect(
            await run(
              _viewer,
              'attentionMarkAllSeen',
              'mutation { attentionMarkAllSeen }',
            ),
            greaterThan(0),
          );
          expect(
            await run(
              'Ua00000000001',
              'beaconClose',
              'mutation { beaconClose(beaconId: "Bfwdreq000001") }',
            ),
            isTrue,
          );
          expect(
            await run(
              _viewer,
              'attentionMarkSeen',
              'mutation { attentionMarkSeen(ids: ["$closeId"]) }',
            ),
            greaterThan(0),
          );
        },
        observeRequest: (request) {
          final variables = request['variables'] as Map?;
          if (request['operationName'] == 'AttentionMarkUnseen') {
            return (response) {
              final body = jsonDecode(response.body) as Map<String, dynamic>;
              expect(body['errors'], isNull);
              mutation.complete((
                ids: variables!['ids'],
                updated: (body['data'] as Map)['attentionMarkUnseen'] as int,
              ));
            };
          }
          if (request['operationName'] != 'AttentionFeed' ||
              variables?['view'] != 'all' ||
              !mutation.isCompleted) {
            return null;
          }

          // Capture the phase as the request leaves so an earlier in-flight
          // response cannot stand in for either fresh History read.
          final isReopenedRead = reopening;
          return (response) {
            final body = jsonDecode(response.body) as Map<String, dynamic>;
            expect(body['errors'], isNull);
            final feed = (body['data'] as Map)['attentionFeed'] as Map;
            final items = ((feed['page'] as Map)['items'] as List)
                .cast<Map<String, dynamic>>()
                .where((item) => item['id'] == closeId)
                .map(
                  (item) => {
                    'id': item['id'],
                    if (item.containsKey('seenAt')) 'seenAt': item['seenAt'],
                  },
                )
                .toList(growable: false);
            if (isReopenedRead) {
              if (!reopenedFeed.isCompleted) reopenedFeed.complete(items);
            } else if (!reread.isCompleted) {
              reread.complete((
                unreadTotal: (feed['summary'] as Map)['unreadTotal'] as int,
                items: items,
              ));
            }
          };
        },
      );
    },
  );
}
