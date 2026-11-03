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

import '../../domain/attention/attention_case_test_support.dart';
import '../block/support/controllable_block_case.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/phone_surface.dart';
import '../../support/production_receipt_transport.dart';
import '../../support/test_realtime_sync.dart';
import 'support/noop_invite_setup_port.dart';

// Coverage: production PG/GraphQL -> Ferry -> repository -> case -> cubit ->
// History widgets. Closed/open Posts, cold load, All/Unread, RU phone/desktop.
// Input and browser lifecycle are outside this read-projection contract.
const _viewer = 'Ua00000000001';
const _closed = 'Bdotclosed001';
const _open = 'Bdotopen00001';

Future<void> _until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('History did not finish loading');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

final class _MutationGate {
  _MutationGate(this.operation);
  final String operation;
  late final Completer<void> entered;
  late final Completer<void> release;
  late final Completer<Map<String, dynamic>> response;
  late final Completer<void> unreadAfterSweep;
  void arm() {
    entered = Completer<void>();
    release = Completer<void>();
    response = Completer<Map<String, dynamic>>();
    unreadAfterSweep = Completer<void>();
  }
}

Future<void> _withHistory(
  WidgetTester tester,
  Future<void> Function(UpdatesFeedCubit cubit, AttentionCase attention) body, {
  bool closedOnly = false,
  bool clearedClosed = false,
  _MutationGate? gate,
}) async {
  await tester.runAsync(() async {
    gate?.arm();
    final transport = await ProductionReceiptTransport.start(
      postLifecycleFixture: closedOnly
          ? 'closedOnly'
          : clearedClosed
          ? 'clearedClosed'
          : 'mixed',
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
            Logger('post-lifecycle-history'),
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
              logger: Logger('post-lifecycle-history'),
              actorProfiles: buildNoopAttentionActorProfiles(),
            );
            await _until(() => cubit!.state.firstLoadDone);
            expect(cubit.state.refreshError, isNull);
            expect(
              cubit.state.items.map((r) => r.beaconId),
              unorderedEquals([_closed, if (!closedOnly) _open]),
            );
            expect(cubit.state.summary.unreadTotal, closedOnly ? 0 : 1);
            await body(cubit, attention);
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
          if (requestBody['operationName'] == gate?.operation) {
            gate!.entered.complete();
            await gate.release.future;
          }
          final response = await transport.graphql(_viewer, requestBody);
          if (gate != null) {
            if (requestBody['operationName'] == gate.operation) {
              gate.response.complete(
                jsonDecode(response.body) as Map<String, dynamic>,
              );
            } else if (gate.response.isCompleted &&
                requestBody['operationName'] == 'AttentionFeed' &&
                (requestBody['variables'] as Map?)?['view'] == 'unread' &&
                !gate.unreadAfterSweep.isCompleted) {
              gate.unreadAfterSweep.complete();
            }
          }
          return response;
        }),
      );
    } finally {
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

Finder _dotFor(String beaconId) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is UpdatesFeedTile && w.receipt.beaconId == beaconId,
  ),
  matching: find.byKey(UpdatesFeedTile.unreadDotKey),
);

Finder get _readAllButton => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is TenturaTextAction && w.label == 'Прочитать всё',
  ),
  matching: find.byType(TextButton),
);

bool _readAllEnabled(WidgetTester tester) =>
    tester.widget<TextButton>(_readAllButton).onPressed != null;

Map<String, Object?> _visibleUnread(
  WidgetTester tester,
  UpdatesFeedCubit cubit,
) => {
  'count': cubit.state.summary.unreadTotal,
  'closed dots': _dotFor(_closed).evaluate().length,
  'open dots': _dotFor(_open).evaluate().length,
  'visible count one': find.text('1').evaluate().length,
};

Future<void> _readAllThroughControl(
  WidgetTester tester,
  UpdatesFeedCubit cubit,
  _MutationGate gate, {
  Map<String, Object?>? initialViews,
}) async {
  final closedId = cubit.state.items
      .singleWhere((r) => r.beaconId == _closed)
      .id;
  final openId = cubit.state.items.singleWhere((r) => r.beaconId == _open).id;
  expect(
    _readAllEnabled(tester),
    isTrue,
    reason: 'the open Post enables Read all in a mixed History',
  );
  await tester.tap(_readAllButton);
  Map<String, Object?>? pending;
  try {
    await gate.entered.future.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(Duration.zero);
    await _pumpHistory(tester, cubit);
    expect(
      cubit.state.summary.unreadTotal,
      0,
      reason:
          'the pending sweep removes the only eligible unread receipt from the count',
    );
    pending = {
      'unread count': cubit.state.summary.unreadTotal,
      'visible count one': find.text('1').evaluate().length,
      'archived receipt read': cubit.state.items
          .singleWhere((r) => r.id == closedId)
          .isSeen,
      'archived receipt swept': cubit.state.items
          .singleWhere((r) => r.id == closedId)
          .isCleared,
      'eligible receipt swept': cubit.state.items
          .singleWhere((r) => r.id == openId)
          .isCleared,
      'dots': find.byKey(UpdatesFeedTile.unreadDotKey).evaluate().length,
    };
  } finally {
    gate.release.complete();
  }
  final response = await gate.response.future.timeout(
    const Duration(seconds: 15),
  );
  expect(response['errors'], isNull);
  final sweep = (response['data'] as Map)['attentionDismissAll'] as Map;
  await gate.unreadAfterSweep.future.timeout(const Duration(seconds: 15));
  // The leftover page and the account-wide sweep summary are independent
  // requests. The page response alone does not finish Read all enablement.
  await _until(() => !cubit.state.sweepEligible);
  await Future<void>.delayed(Duration.zero);
  await _pumpHistory(tester, cubit);
  final closed = cubit.state.items.singleWhere((r) => r.id == closedId);
  final open = cubit.state.items.singleWhere((r) => r.id == openId);
  expect(
    {
      'initial views': initialViews,
      'pending': pending,
      'applied receipt IDs': sweep['appliedReceiptIds'],
      'skipped members': sweep['skipped'],
      'failed members': sweep['failed'],
      'archived receipt read': closed.isSeen,
      'archived receipt cleared': closed.isCleared,
      'eligible receipt read': open.isSeen,
      'eligible receipt cleared': open.isCleared,
      'visible': _visibleUnread(tester, cubit),
      'Read all enabled': _readAllEnabled(tester),
    },
    {
      'initial views': initialViews == null
          ? null
          : {
              'All': {
                'count': 1,
                'closed dots': 0,
                'open dots': 1,
                'visible count one': 1,
              },
              'Unread': {
                'count': 1,
                'closed dots': 0,
                'open dots': 1,
                'visible count one': 1,
              },
            },
      'pending': {
        'unread count': 0,
        'visible count one': 0,
        'archived receipt read': true,
        'archived receipt swept': false,
        'eligible receipt swept': true,
        'dots': 0,
      },
      'applied receipt IDs': [openId],
      'skipped members': <Object?>[],
      'failed members': <Object?>[],
      'archived receipt read': true,
      'archived receipt cleared': false,
      'eligible receipt read': true,
      'eligible receipt cleared': true,
      'visible': {
        'count': 0,
        'closed dots': 0,
        'open dots': 0,
        'visible count one': 0,
      },
      'Read all enabled': false,
    },
    reason:
        'Read all reads archives without admitting them to the sweep and clears the remaining eligible attention',
  );
  expect(tester.takeException(), isNull);
}

void main() {
  for (final phone in [true, false]) {
    testWidgets(
      'History dots and Read all honour Post lifecycle in RU ${phone ? 'phone' : 'desktop'}',
      (tester) async {
        if (phone) {
          await usePhoneSurface(tester);
        } else {
          await tester.binding.setSurfaceSize(const Size(1280, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
        }
        final gate = _MutationGate('AttentionDismissAll');
        await _withHistory(tester, (cubit, attention) async {
          await _pumpHistory(tester, cubit);
          expect(find.byType(UpdatesFeedTile), findsNWidgets(2));
          expect(find.text('Прочитать всё'), findsOneWidget);
          final initial = _visibleUnread(tester, cubit);
          expect(_readAllEnabled(tester), isTrue);
          await tester.tap(
            find.byKey(const ValueKey<String>('updates-unread')),
          );
          await _until(
            () =>
                cubit.state.items.length == 1 &&
                cubit.state.items.single.beaconId == _open,
          );
          await _pumpHistory(tester, cubit);
          final unread = _visibleUnread(tester, cubit);
          expect(_readAllEnabled(tester), isTrue);
          // Return to All so both the archived row and the remaining open
          // receipt are visible while the actual Read all control runs.
          await tester.tap(find.byKey(const ValueKey<String>('updates-all')));
          await _until(() => cubit.state.items.length == 2);
          await _pumpHistory(tester, cubit);
          await _readAllThroughControl(
            tester,
            cubit,
            gate,
            initialViews: {'All': initial, 'Unread': unread},
          );
          expect(tester.takeException(), isNull);
        }, gate: gate);
      },
    );
  }

  testWidgets(
    'Read all becomes disabled when only closed Post receipts remain',
    (tester) async {
      await usePhoneSurface(tester);
      await _withHistory(tester, (cubit, attention) async {
        await _pumpHistory(tester, cubit);
        expect(cubit.state.items.single.isSeen, isFalse);
        expect(cubit.state.sweepEligible, isFalse);
        expect(find.text('Прочитать всё'), findsOneWidget);
        final readAll = tester.widget<TenturaTextAction>(
          find.byWidgetPredicate(
            (w) => w is TenturaTextAction && w.label == 'Прочитать всё',
          ),
        );
        expect(
          readAll.onPressed,
          isNull,
          reason: 'archived unseen receipts do not enable Read all',
        );
        expect(cubit.state.canReadAll, isFalse);
        expect(tester.takeException(), isNull);
      }, closedOnly: true);
    },
  );

  testWidgets(
    'Read all reads archived Posts and clears only eligible attention',
    (tester) async {
      final gate = _MutationGate('AttentionDismissAll');
      await _withHistory(tester, (cubit, attention) async {
        await _pumpHistory(tester, cubit);
        await _readAllThroughControl(tester, cubit, gate);
      }, gate: gate);
    },
  );
  testWidgets(
    'Clearing an archived Post preserves the eligible unread count while saving',
    (tester) async {
      final gate = _MutationGate('AttentionClear');
      await _withHistory(tester, (cubit, attention) async {
        final receipt = cubit.state.items.singleWhere(
          (r) => r.beaconId == _closed,
        );
        final action = attention.clearReceipt(receiptId: receipt.id);
        try {
          await gate.entered.future.timeout(const Duration(seconds: 15));
          await Future<void>.delayed(Duration.zero);
          await _pumpHistory(tester, cubit);
          expect(
            _visibleUnread(tester, cubit),
            {
              'count': 1,
              'closed dots': 0,
              'open dots': 1,
              'visible count one': 1,
            },
            reason:
                'clearing an archive preserves the open Post count and dot without restoring an archived dot',
          );
        } finally {
          gate.release.complete();
          await action;
        }
      }, gate: gate);
    },
  );

  testWidgets(
    'Mark unread on an archived Post does not restore a dot or increase the count while saving',
    (tester) async {
      final gate = _MutationGate('AttentionMarkUnread');
      await _withHistory(
        tester,
        (cubit, attention) async {
          final receipt = cubit.state.items.singleWhere(
            (r) => r.beaconId == _closed,
          );

          expect(
            cubit.state.items.singleWhere((r) => r.id == receipt.id).isCleared,
            isTrue,
          );
          expect(cubit.state.summary.unreadTotal, 1);
          final action = cubit.markUnseen(receipt.id);
          try {
            await gate.entered.future.timeout(const Duration(seconds: 15));
            await Future<void>.delayed(Duration.zero);
            await _pumpHistory(tester, cubit);
            expect(
              {
                'unread count': cubit.state.summary.unreadTotal,
                'archived dots': _dotFor(_closed).evaluate().length,
                'open dots': _dotFor(_open).evaluate().length,
              },
              {'unread count': 1, 'archived dots': 0, 'open dots': 1},
            );
          } finally {
            gate.release.complete();
            await action;
          }
        },
        gate: gate,
        clearedClosed: true,
      );
    },
  );
}
