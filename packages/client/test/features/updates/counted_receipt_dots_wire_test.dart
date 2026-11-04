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
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../domain/attention/attention_case_test_support.dart';
import '../block/support/controllable_block_case.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/phone_surface.dart';
import '../../support/production_receipt_transport.dart';
import '../../support/test_realtime_sync.dart';
import 'support/noop_invite_setup_port.dart';

// Coverage: real PG/GraphQL -> Ferry -> repository -> case -> cubit -> tiles.
// Read-all, All/Unread, RU phone and desktop. Browser
// reload and input-device guarantees need the web integration runner.
const _viewer = 'Ua00000000001';

Future<void> _until(
  bool Function() ready, {
  Object? Function()? diagnostic,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('History did not finish loading: ${diagnostic?.call()}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

// Hold a real mutation before it reaches PostgreSQL so the optimistic frame
// and the independently queried server state can be distinguished.
final class _MutationBarrier {
  final entered = Completer<void>();
  final released = Completer<void>();
  void release() {
    if (!released.isCompleted) released.complete();
  }
}

final class _MutationGates {
  final _pending = <String, _MutationBarrier>{};
  _MutationBarrier hold(String operation) =>
      _pending[operation] = _MutationBarrier();
  Future<void> intercept(String operation) async {
    final barrier = _pending.remove(operation);
    if (barrier == null) return;
    barrier.entered.complete();
    await barrier.released.future.timeout(const Duration(seconds: 15));
  }

  void releaseAll() {
    for (final barrier in _pending.values) {
      barrier.release();
    }
  }
}

Future<Map<String, Object?>> _responsibility(
  AttentionRepository repository,
) async {
  final feed = await repository.fetch(view: AttentionView.needsYou);
  return {
    'unreadTotal': feed.summary.unreadTotal,
    'needsYouTotal': feed.summary.needsYouTotal,
    'responsible Requests': await repository.liveObligationBeacons(),
    'obligations': [
      for (final r in feed.page.items)
        {
          'id': r.id,
          'beacon': r.beaconId,
          'thread': r.attentionThreadKey,
          'requiresAction': r.requiresAction,
          'settlement': r.settlementKind,
          'settledAt': r.settledAt,
        },
    ],
  };
}

void _expectCount(WidgetTester tester, UpdatesFeedCubit cubit, int count) {
  expect(cubit.state.summary.unreadTotal, count);
  expect(
    find.descendant(
      of: find.byKey(const ValueKey<String>('updates-unread')),
      matching: find.text('$count'),
    ),
    findsOneWidget,
  );
}

Future<void> _withHistory(
  WidgetTester tester,
  Future<void> Function(
    UpdatesFeedCubit cubit,
    AttentionCase attention,
    AttentionRepository repository,
    _MutationGates gates,
  )
  body, {
  bool siblings = false,
}) async {
  await tester.runAsync(() async {
    final gates = _MutationGates();
    final transport = await ProductionReceiptTransport.start(
      countedRowsFixture: !siblings,
      countedSiblingFixture: siblings,
    );
    try {
      await http.runWithClient(
        () async {
          final remote = RemoteApiService(
            const Env(),
            const WebSocketClientRealtimeSocketFactory(),
          );
          final accounts = AttentionCaseTestAccounts();
          final sync = buildTestRealtimeSync();
          final attention = AttentionCase(
            AttentionRepository(remote),
            accounts,
            sync.case_,
            noopBlockCase(),
            FeedSessionRegistry(),
            Logger('counted-receipt-history'),
          );
          UpdatesFeedCubit? cubit;
          try {
            await remote.setSessionAuth();
            accounts.emit(_viewer);
            await Future<void>.delayed(Duration.zero);
            cubit = UpdatesFeedCubit(
              destinationId: AttentionFeedDestinationId.history,
              attention: attention,
              setup: NoopInviteAcceptedSetupPort(),
              realtime: sync.case_,
              logger: Logger('counted-receipt-history'),
              actorProfiles: buildNoopAttentionActorProfiles(),
            );
            await _until(() => cubit!.state.firstLoadDone);
            expect(cubit.state.refreshError, isNull);
            expect(
              cubit.state.items.map((r) => r.id),
              unorderedEquals([
                if (siblings) ...[
                  'counted-plan',
                  'counted-trust',
                ] else ...[
                  'counted-forward',
                  'counted-offer',
                ],
                'counted-social',
              ]),
            );
            expect(cubit.state.summary.unreadTotal, 3);
            await body(cubit, attention, AttentionRepository(remote), gates);
          } finally {
            await cubit?.close();
            await attention.dispose();
            await sync.port.dispose();
            await accounts.dispose();
            await remote.close();
          }
        },
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
          final requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          await gates.intercept(requestBody['operationName'] as String);
          final response = await transport.graphql(_viewer, requestBody);
          return response;
        }),
      );
    } finally {
      gates.releaseAll();
      await transport.close();
    }
  });
}

Future<void> _pumpHistory(WidgetTester tester, UpdatesFeedCubit cubit) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: const Locale('ru'),
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

Finder get _readAllButton => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is TenturaTextAction && w.label == 'Прочитать всё',
  ),
  matching: find.byType(TextButton),
);

Map<String, Object> _visible(WidgetTester tester, UpdatesFeedCubit cubit) => {
  'count': cubit.state.summary.unreadTotal,
  'dots': find.byKey(UpdatesFeedTile.unreadDotKey).evaluate().length,
  'read all enabled':
      tester.widget<TextButton>(_readAllButton).onPressed != null,
  'forward dot': find
      .descendant(
        of: find.bySemanticsIdentifier(
          TestIds.updatesReceipt('counted-forward'),
        ),
        matching: find.byKey(UpdatesFeedTile.unreadDotKey),
      )
      .evaluate()
      .length,
  'obligation dot': find
      .descendant(
        of: find.bySemanticsIdentifier(TestIds.updatesReceipt('counted-offer')),
        matching: find.byKey(UpdatesFeedTile.unreadDotKey),
      )
      .evaluate()
      .length,
};

void main() {
  for (final phone in [true, false]) {
    testWidgets(
      'Read all leaves counted forwards and obligations dotted on both filters in RU ${phone ? 'phone' : 'desktop'}',
      (tester) async {
        if (phone) {
          await usePhoneSurface(tester);
        } else {
          await tester.binding.setSurfaceSize(const Size(1280, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
        }
        await _withHistory(tester, (cubit, attention, repository, gates) async {
          await _pumpHistory(tester, cubit);
          expect(find.byType(UpdatesFeedTile), findsNWidgets(3));
          expect(
            tester.widget<TextButton>(_readAllButton).onPressed,
            isNotNull,
          );
          final before = await _responsibility(repository);
          expect(before['needsYouTotal'], 1);
          expect(before['responsible Requests'], contains('Bseenby000001'));
          expect(before['obligations'], [
            allOf(
              containsPair('id', 'counted-offer'),
              containsPair('settlement', null),
              containsPair('settledAt', null),
            ),
          ]);
          final read = gates.hold('AttentionMarkAllSeen');
          final sweep = gates.hold('AttentionDismissAll');
          await tester.tap(_readAllButton);
          try {
            await read.entered.future.timeout(const Duration(seconds: 15));
            await _pumpHistory(tester, cubit);
            expect(cubit.state.items.every((r) => r.isSeen), isTrue);
            _expectCount(tester, cubit, 3);
            final serverBeforeRead = await repository.fetch(
              view: AttentionView.all,
            );
            expect(serverBeforeRead.page.items.every((r) => !r.isSeen), isTrue);
            expect(serverBeforeRead.summary.unreadTotal, 3);
            read.release();
            await sweep.entered.future.timeout(const Duration(seconds: 15));
            await _pumpHistory(tester, cubit);
            _expectCount(tester, cubit, 2);
            expect(cubit.state.summary.needsYouTotal, 1);
            final serverBeforeSweep = await repository.fetch(
              view: AttentionView.unread,
            );
            expect(serverBeforeSweep.summary.unreadTotal, 3);
            expect(
              serverBeforeSweep.page.items.every(
                (r) => r.isSeen && !r.isCleared,
              ),
              isTrue,
            );
          } finally {
            read.release();
            sweep.release();
          }
          await _until(
            () =>
                cubit.state.items.every((r) => r.isSeen) &&
                cubit.state.summary.unreadTotal == 2 &&
                !cubit.state.canReadAll,
            diagnostic: () => {
              'state': cubit.state,
              'items': cubit.state.items
                  .map(
                    (r) =>
                        '${r.id}: seen=${r.isSeen} clear=${r.isCleared} surface=${r.surface}',
                  )
                  .toList(),
            },
          );
          await _pumpHistory(tester, cubit);
          expect(
            cubit.state.items
                .singleWhere((r) => r.id == 'counted-forward')
                .requiresAction,
            isFalse,
          );
          expect(
            cubit.state.items
                .singleWhere((r) => r.id == 'counted-forward')
                .isCleared,
            isFalse,
          );
          expect(
            cubit.state.items
                .singleWhere((r) => r.id == 'counted-offer')
                .isLiveObligation,
            isTrue,
          );
          expect(
            cubit.state.items
                .singleWhere((r) => r.id == 'counted-social')
                .isCleared,
            isTrue,
          );
          final after = await _responsibility(repository);
          expect(after['unreadTotal'], 2);
          expect(after['needsYouTotal'], before['needsYouTotal']);
          expect(after['responsible Requests'], before['responsible Requests']);
          expect(
            after['obligations'],
            before['obligations'],
            reason:
                'reading and sweeping optional attention cannot settle the live responsibility',
          );
          final views = {'All': _visible(tester, cubit)};
          await tester.tap(
            find.byKey(const ValueKey<String>('updates-unread')),
          );
          await _until(
            () =>
                cubit.state.view == AttentionView.unread &&
                cubit.state.items.length == 2,
          );
          await _pumpHistory(tester, cubit);
          expect(find.byType(UpdatesFeedTile), findsNWidgets(2));
          expect(find.text('2'), findsOneWidget);
          views['Unread'] = _visible(tester, cubit);
          expect(tester.takeException(), isNull);
          const expected = {
            'count': 2,
            'dots': 2,
            'read all enabled': false,
            'forward dot': 1,
            'obligation dot': 1,
          };
          expect(
            views,
            {'All': expected, 'Unread': expected},
            reason:
                'seen optional forward shells and live obligations stay counted after Read all',
          );
        });
      },
    );
    testWidgets(
      'opened plan obligations and optional trust and invite receipts keep counted dots in the RU ${phone ? 'phone' : 'desktop'} feed',
      (tester) async {
        if (phone) {
          await usePhoneSurface(tester);
        } else {
          await tester.binding.setSurfaceSize(const Size(1280, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
        }
        await _withHistory(tester, (cubit, attention, repository, gates) async {
          await _pumpHistory(tester, cubit);
          for (final id in [
            'counted-plan',
            'counted-trust',
            'counted-social',
          ]) {
            final barrier = gates.hold('AttentionMarkSeen');
            final opening = cubit.markRead(id);
            try {
              await barrier.entered.future.timeout(const Duration(seconds: 15));
              await _pumpHistory(tester, cubit);
              expect(
                cubit.state.items.singleWhere((r) => r.id == id).isSeen,
                isTrue,
              );
              _expectCount(tester, cubit, 3);
              final beforeCommit = await repository.fetch(
                view: AttentionView.unread,
              );
              expect(
                beforeCommit.page.items.singleWhere((r) => r.id == id).isSeen,
                isFalse,
              );
              expect(beforeCommit.summary.unreadTotal, 3);
            } finally {
              barrier.release();
            }
            await opening;
            // DataSource.Link in repository.fetch guarantees a fresh production
            // server response, independent of the cubit's optimistic overlay.
            final persisted = await repository.fetch(
              view: AttentionView.unread,
            );
            expect(persisted.summary.unreadTotal, 3);
            final opened = persisted.page.items.singleWhere((r) => r.id == id);
            expect(opened.isSeen, isTrue);
            expect(opened.isCleared, isFalse);
            expect(opened.settlementKind, isNull);
            expect(opened.settledAt, isNull);
            expect(opened.isLiveObligation, id == 'counted-plan');
          }
          await _until(() => cubit.state.items.every((r) => r.isSeen));
          final views = <String, Object>{};
          for (final unread in [false, true]) {
            if (unread) {
              await tester.tap(
                find.byKey(const ValueKey<String>('updates-unread')),
              );
              await _until(
                () =>
                    cubit.state.view == AttentionView.unread &&
                    cubit.state.items.length == 3,
              );
            }
            await _pumpHistory(tester, cubit);
            expect(find.byType(UpdatesFeedTile), findsNWidgets(3));
            expect(find.text('Прочитать всё'), findsOneWidget);
            expect(find.text('3'), findsOneWidget);
            expect(
              tester.widget<TextButton>(_readAllButton).onPressed,
              isNotNull,
            );
            final l10n = L10n.of(tester.element(find.byType(UpdatesFeedPane)))!;
            final dots = <String, int>{};
            for (final (id, key, content, obligation) in [
              ('counted-plan', 'plan_step_due', 'Подготовить лестницу', true),
              (
                'counted-trust',
                'trust_given_changed_up',
                l10n.attentionEventTrustGivenUp,
                false,
              ),
              (
                'counted-social',
                'invite_accepted',
                l10n.attentionCardInviteAccepted('Алиса'),
                false,
              ),
            ]) {
              final row = find.bySemanticsIdentifier(
                TestIds.updatesReceipt(id),
              );
              expect(row, findsOneWidget);
              final tile = tester.widget<UpdatesFeedTile>(
                find.ancestor(
                  of: row,
                  matching: find.byType(UpdatesFeedTile),
                ),
              );
              expect(tile.receipt.presentationKey, key);
              expect(tile.receipt.isSeen, isTrue);
              expect(tile.receipt.isCleared, isFalse);
              expect(tile.receipt.isLiveObligation, obligation);
              expect(
                find.descendant(
                  of: row,
                  matching: find.text(content, findRichText: true),
                ),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: row,
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is Text &&
                        w.textSpan?.style?.fontWeight == FontWeight.w600,
                  ),
                ),
                findsNothing,
              );
              dots[id] = find
                  .descendant(
                    of: row,
                    matching: find.byKey(UpdatesFeedTile.unreadDotKey),
                  )
                  .evaluate()
                  .length;
            }
            views[unread ? 'Unread' : 'All'] = dots;
            expect(tester.takeException(), isNull);
          }
          const expected = {
            'counted-plan': 1,
            'counted-trust': 1,
            'counted-social': 1,
          };
          expect(views, {'All': expected, 'Unread': expected});
        }, siblings: true);
      },
    );
  }
}
