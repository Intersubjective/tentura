import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/platform/tab_attention_indicator.dart';
import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/model/tab_attention_display.dart';
import 'package:tentura/ui/widget/tab_attention_scope.dart';

import '../../support/noop_attention_actor_profiles.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'support/noop_invite_setup_port.dart';

const _history = AttentionFeedDestinationId.history;
const _activity = AttentionFeedDestinationId.activityStream;

// Only HTTP is replaced. These tests exercise Ferry, the repository mapper,
// AttentionCase, both destination cubits, the production Updates pane, and
// the title channel of TabAttentionController. Browser reload/scroll and
// document.title itself require the web integration runner.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sign-in without a mounted feed uses the account-wide count', () async {
    await _exercise(_Server(), (h) async {
      h.accounts.signIn();
      await _drain();
      await _titleTick();
      expect(h.attention.snapshot.summary.unreadTotal, 33);
      expect(h.indicator.titles.last.count, 33);
    });
  });

  for (final historyFirst in [true, false]) {
    test(
      'Updates keeps 33 and its rows when startup '
      '${historyFirst ? 'history finishes before Activity' : 'Activity finishes before history'}',
      () async {
        final server = _Server()..holdHeads = true;
        await _exercise(server, (h) async {
          h.accounts.signIn();
          await _drain();
          final history = h.mount(_history);
          final projectedCounts = <int>[];
          final subscription = history.stream.listen(
            (state) => projectedCounts.add(state.summary.unreadTotal),
          );
          try {
            await _until(() => server.hasHeldHead(null), 'history request');
            server.release(historyFirst ? null : 'activity');
            await _drain();
            await _titleTick();
            final firstRows = historyFirst
                ? history.state.items.toList()
                : null;
            server.release(historyFirst ? 'activity' : null);
            await _until(() => history.state.firstLoadDone, 'history rows');
            await _drain();
            await _titleTick();
            expect(history.state.items.map((row) => row.id), [
              'Nactivity0001',
              'Nmywork000001',
            ]);
            if (firstRows != null) expect(history.state.items, firstRows);
            expect(
              projectedCounts,
              isNot(contains(15)),
              reason: 'Activity must never become the Updates summary',
            );
            expect(history.state.summary.unreadTotal, 33);
            expect(h.indicator.titles.last.count, 33);
            expect(
              h.indicator.titles.map((display) => display.count),
              isNot(contains(15)),
            );
          } finally {
            await subscription.cancel();
          }
        });
      },
    );
  }

  for (final historyAttachedFirst in [true, false]) {
    for (final historyCompletedFirst in [true, false]) {
      test(
        'refresh preserves each destination count with '
        '${historyAttachedFirst ? 'history' : 'Activity'} attached first and '
        '${historyCompletedFirst ? 'history' : 'Activity'} completed first',
        () async {
          final server = _Server();
          await _exercise(server, (h) async {
            await h.seed(historyAttachedFirst: historyAttachedFirst);
            final history = h.cubits[_history]!;
            final activity = h.cubits[_activity]!;
            final priorRows = history.state.items.toList();
            expect(history.state.summary.unreadTotal, 33);
            await _titleTick();
            h.indicator.titles.clear();
            server.holdHeads = true;
            h.sync.port.emitChange(
              const RealtimeEntityChange(
                kind: RealtimeEntityKind.notification,
                aggregateId: 'Uviewer000001',
                operation: RealtimeOperation.update,
                source: RealtimeChangeSource.serverInvalidation,
              ),
            );
            await _until(
              () => server.hasHeldHead(null) && server.hasHeldHead('activity'),
              'both destination refresh requests',
            );
            server.release(historyCompletedFirst ? null : 'activity');
            await _drain();
            server.release(historyCompletedFirst ? 'activity' : null);
            await _drain();
            await _titleTick();
            expect(history.state.items, priorRows);
            expect(
              (
                history.state.summary.unreadTotal,
                activity.state.summary.unreadTotal,
                h.attention.snapshot.summary.unreadTotal,
              ),
              (33, 15, 33),
              reason:
                  'feeds keep their own counts; the title keeps the account total',
            );
            expect(
              h.indicator.titles.map((display) => display.count),
              everyElement(33),
            );
          });
        },
      );
    }
  }

  for (final destination in [_activity, _history]) {
    test(
      'loading more ${destination == _history ? 'Updates' : 'Activity'} '
      'rows does not replace the Updates or account count',
      () async {
        final server = _Server()
          ..accountWideCount = 13
          ..historyCount = 13;
        await _exercise(server, (h) async {
          await h.seed();
          final history = h.cubits[_history]!;
          final paged = h.cubits[destination]!;
          expect(history.state.summary.unreadTotal, 13);
          expect(paged.state.hasNextPage, isTrue);
          await _titleTick();
          final priorRows = history.state.items.toList();
          final requestsBefore = h.sent.length;
          await paged.loadNextPage();
          await _drain();
          await _titleTick();
          expect(
            paged.state.items.any((row) => row.id == 'Npage00000001'),
            isTrue,
          );
          expect(
            h.sent.skip(requestsBefore).map((request) => request.operationName),
            everyElement('AttentionFeed'),
            reason: 'pagination performs no read or clear',
          );
          expect(
            history.state.items.take(priorRows.length).toList(),
            priorRows,
          );
          expect(
            (
              history.state.summary.unreadTotal,
              h.attention.snapshot.summary.unreadTotal,
              h.indicator.titles.last.count,
            ),
            (13, 13, 13),
            reason: 'a page with 5 cannot replace the account summary of 13',
          );
        });
      },
    );

    test(
      'search in ${destination == _history ? 'Updates' : 'Activity'} '
      'keeps filtered counts out of the account title',
      () async {
        await _exercise(_Server(), (h) async {
          await h.seed();
          final history = h.cubits[_history]!;
          final searched = h.cubits[destination]!;
          expect(history.state.summary.unreadTotal, 33);
          await _titleTick();
          searched.setSearch('Событие');
          await _until(
            () => searched.state.items.any((row) => row.id == 'Nsearch000001'),
            'filtered rows',
          );
          await _drain();
          await _titleTick();
          expect(
            searched.state.summary.unreadTotal,
            destination == _history ? 33 : 5,
          );
          expect(history.state.summary.unreadTotal, 33);
          expect(h.attention.snapshot.summary.unreadTotal, 33);
          expect(h.indicator.titles.last.count, 33);
        });
      },
    );
  }

  test(
    'optimistic un-clear changes only feeds containing that receipt',
    () async {
      final server = _Server()..includeClearedMyWork = true;
      await _exercise(server, (h) async {
        await h.seed();
        final history = h.cubits[_history]!;
        final activity = h.cubits[_activity]!;
        expect(history.state.items.last.isCleared, isTrue);
        expect(
          activity.state.items.any((row) => row.id == 'Ncleared00001'),
          isFalse,
        );
        final mutation = history.markUnseen('Ncleared00001');
        try {
          await _until(() => server.unreadRequested, 'un-clear mutation');
          await _drain();
          expect(history.state.items.last.isCleared, isFalse);
          expect(
            (
              history.state.summary.unreadTotal,
              activity.state.summary.unreadTotal,
              h.attention.snapshot.summary.unreadTotal,
            ),
            (34, 15, 34),
            reason: 'the un-cleared My Desk receipt is absent from Activity',
          );
        } finally {
          server.unreadGate.complete();
          await mutation;
        }
      });
    },
  );

  for (final historyFirst in [true, false]) {
    testWidgets(
      'Russian Updates badge and title keep 33 when '
      '${historyFirst ? 'history completes before Activity' : 'Activity completes before history'}',
      (tester) async {
        final server = _Server()..holdHeads = true;
        await _phoneScenario(
          tester,
          server,
          (h) async {
            h.accounts.signIn();
            await _drain();
            // A fixed startup may fetch only the account total. Mount Activity
            // explicitly as well, so both destination responses are still raced.
            h.mount(_activity);
            final history = h.mount(_history);
            await _until(
              () =>
                  server.hasPendingHead(null) &&
                  server.hasPendingHead('activity'),
              'both HTTP responses held at the transport boundary',
            );
            expect(server.completedFeedSurfaces, isEmpty);
            final first = historyFirst ? null : 'activity';
            final second = historyFirst ? 'activity' : null;
            server.release(first);
            await _until(
              () => server.completedFeedSurfaces.contains(first),
              'the first feed response',
            );
            await _drain();
            await _titleTick();
            expect(server.hasPendingHead(second), isTrue);
            expect(server.completedFeedSurfaces, isNot(contains(second)));
            final firstRows = historyFirst
                ? history.state.items.toList()
                : null;
            server.release(second);
            await _until(
              () =>
                  server.completedFeedSurfaces.contains(second) &&
                  history.state.firstLoadDone,
              'the delayed feed response and the history rows',
            );
            await _drain();
            await _titleTick();
            expect(
              server.completedFeedSurfaces.indexOf(first),
              lessThan(server.completedFeedSurfaces.indexOf(second)),
            );
            if (firstRows != null) expect(history.state.items, firstRows);
          },
          (h) {
            _expectRows(tester);
            _expectRussianBadgeLayout(tester);
            expect(
              _renderedUnreadCount(tester),
              33,
              reason: 'the Updates badge stays 33 after both feed responses',
            );
            expect(h.indicator.titles.last.count, 33);
            expect(
              h.indicator.titles.map((display) => display.count),
              isNot(contains(15)),
              reason:
                  'neither completion order may publish Activity to the title',
            );
          },
        );
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  }

  testWidgets(
    'Russian Updates badge keeps its destination count when reconcile changes the account title',
    (tester) async {
      final server = _Server();
      await _phoneScenario(
        tester,
        server,
        (h) async {
          await h.seed();
          server.accountWideCount = 40;
          final repaired = await h.attention.reconcile();
          expect(repaired.createdObligationCount, 0);
          expect(
            h.sent.any(
              (request) => request.operationName == 'AttentionReconcile',
            ),
            isTrue,
          );
          await _drain();
          await _titleTick();
        },
        (h) {
          _expectRows(tester);
          _expectRussianBadgeLayout(tester);
          expect(
            (
              _renderedUnreadCount(tester),
              h.attention.snapshot.summary.unreadTotal,
              h.indicator.titles.last.count,
            ),
            (33, 40, 40),
            reason:
                'the account total is authoritative for the title; Updates keeps its own feed summary',
          );
        },
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  for (final destination in [_activity, _history]) {
    testWidgets(
      'Russian Updates badge and title keep 13 after '
      '${destination == _history ? 'Updates' : 'Activity'} pagination',
      (tester) async {
        final server = _Server()
          ..accountWideCount = 13
          ..historyCount = 13;
        await _phoneScenario(
          tester,
          server,
          (h) async {
            await h.seed();
            final paged = h.cubits[destination]!;
            final history = h.cubits[_history]!;
            final priorRows = history.state.items.toList();
            expect(history.state.summary.unreadTotal, 13);
            expect(paged.state.hasNextPage, isTrue);
            await paged.loadNextPage();
            await _drain();
            await _titleTick();
            expect(
              paged.state.items.any((row) => row.id == 'Npage00000001'),
              isTrue,
            );
            expect(
              history.state.items.take(priorRows.length).toList(),
              priorRows,
            );
          },
          (h) {
            _expectRows(tester, rowCount: destination == _history ? 3 : 2);
            _expectRussianBadgeLayout(tester);
            expect(
              (
                _renderedUnreadCount(tester),
                h.attention.snapshot.summary.unreadTotal,
                h.indicator.titles.last.count,
                h.cubits[destination]!.state.summary.unreadTotal,
              ),
              (13, 13, 13, destination == _history ? 13 : 5),
              reason:
                  'the destination page is loaded without borrowing its 5 for Updates',
            );
          },
        );
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    testWidgets(
      'Russian Updates badge and title keep 33 after '
      '${destination == _history ? 'Updates' : 'Activity'} search',
      (tester) async {
        await _phoneScenario(
          tester,
          _Server(),
          (h) async {
            await h.seed();
            h.cubits[destination]!.setSearch('Событие');
            await _until(
              () => h.cubits[destination]!.state.items.any(
                (row) => row.id == 'Nsearch000001',
              ),
              'filtered destination rows',
            );
            await _drain();
            await _titleTick();
          },
          (h) {
            if (destination == _history) {
              expect(find.byType(UpdatesFeedTile), findsOneWidget);
              expect(find.text('Событие найдено'), findsOneWidget);
              expect(find.text('Событие My Desk'), findsNothing);
            } else {
              _expectRows(tester);
            }
            _expectRussianBadgeLayout(tester);
            expect(
              (
                _renderedUnreadCount(tester),
                h.attention.snapshot.summary.unreadTotal,
                h.indicator.titles.last.count,
                h.cubits[destination]!.state.summary.unreadTotal,
              ),
              (33, 33, 33, destination == _history ? 33 : 5),
              reason:
                  'search filters rows without filtering the Updates badge or account title',
            );
            expect(tester.takeException(), isNull);
          },
        );
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  }
}

Future<void> _phoneScenario(
  WidgetTester tester,
  _Server server,
  Future<void> Function(_Harness) load,
  void Function(_Harness) verify,
) async {
  late _Harness h;
  final sent = <WireSent>[];
  await tester.runAsync(
    () => withRemoteWire({}, sent, (remote) async {
      h = _Harness(remote, sent);
      try {
        await load(h);
      } finally {
        server.release(null);
        server.release('activity');
        await _drain();
      }
    }, responseFor: server.respond),
  );
  try {
    await _pumpHistory(tester, h.cubits[_history]!);
    verify(h);
  } finally {
    h.controller.dispose();
    unawaited(h.dispose());
  }
}

Future<void> _titleTick() =>
    Future<void>.delayed(const Duration(milliseconds: 300));

Future<void> _exercise(
  _Server server,
  Future<void> Function(_Harness) body,
) async {
  final sent = <WireSent>[];
  await withRemoteWire({}, sent, (remote) async {
    final h = _Harness(remote, sent);
    try {
      await body(h);
    } finally {
      server.release(null);
      server.release('activity');
      await _drain();
      await h.dispose();
    }
  }, responseFor: server.respond);
}

final class _Harness {
  _Harness(RemoteApiService remote, this.sent) {
    attention = AttentionCase(
      AttentionRepository(remote),
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('attention-destination-counts'),
    );
    controller = TabAttentionController(
      indicator: indicator,
      attention: attention,
    );
  }

  final List<WireSent> sent;
  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final indicator = _TitleRecorder();
  final cubits = <String, UpdatesFeedCubit>{};
  late final AttentionCase attention;
  late final TabAttentionController controller;

  UpdatesFeedCubit mount(String destination) => cubits.putIfAbsent(
    destination,
    () => UpdatesFeedCubit(
      destinationId: destination,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      actorProfiles: buildNoopAttentionActorProfiles(),
      logger: Logger('attention-destination-cubit'),
    ),
  );

  Future<void> seed({bool historyAttachedFirst = false}) async {
    accounts.signIn();
    await _drain();
    for (final id
        in historyAttachedFirst
            ? [_history, _activity]
            : [_activity, _history]) {
      mount(id);
      await _drain();
    }
    await cubits[_history]!.refresh();
    await _drain();
  }

  Future<void> dispose() async {
    controller.dispose();
    for (final cubit in cubits.values) {
      await cubit.close();
    }
    await attention.dispose();
    await accounts.close();
    await sync.port.dispose();
  }
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();
  @override
  Stream<String> get currentAccountChanges => _changes.stream;
  void signIn() => _changes.add('Uviewer000001');
  Future<void> close() => _changes.close();
}

final class _TitleRecorder extends TabAttentionIndicator {
  final titles = <TabAttentionDisplay>[];
  @override
  bool get isBackground => true;
  @override
  void apply(
    TabAttentionDisplay display,
    TenturaTabIndicatorStyle style, {
    required String baseTitle,
    bool applyTitle = true,
    bool applyFavicon = true,
    bool applyBadge = true,
  }) {
    if (applyTitle) titles.add(display);
  }
}

final class _Server {
  int accountWideCount = 33;
  final completedFeedSurfaces = <String?>[];
  int historyCount = 33;
  bool holdHeads = false;
  bool includeClearedMyWork = false;
  bool unreadRequested = false;
  final unreadGate = Completer<void>();
  final _held = <({String? surface, Completer<void> gate})>[];
  final _released = <String?>{};

  bool hasPendingHead(String? surface) => _held.any(
    (request) => request.surface == surface && !request.gate.isCompleted,
  );

  bool hasHeldHead(String? surface) =>
      _held.any((request) => request.surface == surface);

  void release(String? surface) {
    _released.add(surface);
    for (final request in _held.where(
      (request) => request.surface == surface,
    )) {
      if (!request.gate.isCompleted) request.gate.complete();
    }
  }

  // The requested account-summary contract includes History totals. The
  // current Ferry mapper ignores these fields: that missing adoption is the
  // regression being tested. Both authoritative operations carry the same
  // unscoped, search-free totals, independently of any destination's response.
  Map<String, dynamic> get accountSummary => {
    '__typename': 'v2_AttentionSurfaceSummary',
    'myDeskDot': true,
    'myDeskCount': 0,
    'forYouDot': true,
    'forYouSweepEligible': true,
    'unreadTotal': accountWideCount,
    'needsYouTotal': 0,
  };

  Future<Map<String, dynamic>> respond(WireSent request) async {
    if (request.operationName == 'AttentionSurfaceSummary') {
      return {
        '__typename': 'query_root',
        'attentionSurfaceSummary': accountSummary,
      };
    }
    if (request.operationName == 'AttentionReconcile') {
      return {
        '__typename': 'mutation_root',
        'attentionReconcile': {
          '__typename': 'v2_AttentionReconcileResult',
          'createdObligationCount': 0,
          'settledObligationCount': 0,
          'unrepairableObligationCount': 0,
          'summary': accountSummary,
        },
      };
    }
    if (request.operationName == 'AttentionMarkUnread') {
      unreadRequested = true;
      await unreadGate.future;
      return {'attentionMarkUnread': 1};
    }
    if (request.operationName != 'AttentionFeed') {
      throw StateError('Unexpected operation: ${request.operationName}');
    }
    final surface = request.variables['surface'] as String?;
    final nextPage = request.variables['cursor'] != null;
    final search =
        (request.variables['search'] as String?)?.isNotEmpty ?? false;
    if (holdHeads && !nextPage && !_released.contains(surface)) {
      final gate = Completer<void>();
      _held.add((surface: surface, gate: gate));
      await gate.future;
    }
    completedFeedSurfaces.add(surface);
    final items = nextPage
        ? [_receipt('Npage00000001', 'Ещё событие', 'activity')]
        : search
        ? [_receipt('Nsearch000001', 'Событие найдено', 'activity')]
        : [
            _receipt('Nactivity0001', 'Событие Activity', 'activity'),
            if (surface == null)
              _receipt('Nmywork000001', 'Событие My Desk', 'myWork'),
            if (surface == null && includeClearedMyWork)
              _receipt('Ncleared00001', 'Завершённое событие', 'myWork')
                ..['clearedAt'] = '2026-11-01T10:00:00.000Z'
                ..['clearReason'] = 'manual',
          ];
    return {
      '__typename': 'query_root',
      'attentionFeed': {
        '__typename': 'v2_AttentionFeed',
        'summary': {
          '__typename': 'v2_AttentionSummary',
          'unreadTotal': nextPage || search
              ? 5
              : surface == null
              ? historyCount
              : 15,
          'needsYouTotal': 0,
        },
        'page': {
          '__typename': 'v2_AttentionPage',
          'nextCursor': nextPage || search ? null : 'next-page',
          'items': items,
        },
      },
    };
  }
}

Map<String, dynamic> _receipt(String id, String title, String surface) => {
  '__typename': 'v2_AttentionReceipt',
  'id': id,
  'category': 'requestProgress',
  'kind': 'newMessage',
  'priority': 'low',
  'title': title,
  'body': 'Короткий текст',
  'actionUrl': '/#/',
  'createdAt': '2026-11-01T08:00:00.000Z',
  'seenAt': null,
  'collapsedCount': 1,
  'beaconId': null,
  'coordinationItemId': null,
  'actorUserId': null,
  'sourceEventKey': id,
  'destinationKind': null,
  'targetEntityId': null,
  'presentationKey': null,
  'presentationPayloadJson': '{}',
  'inAppPreferenceClass': null,
  'requiresAction': false,
  'attentionThreadKey': null,
  'settlementKind': null,
  'settledAt': null,
  'clearedAt': null,
  'clearReason': null,
  'surface': surface,
  'itemKind': 'receipt',
  'forwardOutcome': null,
  'forwardCount': null,
  'digestCount': null,
  'eventTotal': null,
  'eventUnseenCount': null,
  'provenanceJson': null,
  'beaconAuthorId': null,
  'beaconAuthorName': null,
  'beaconAuthorImageId': null,
  'beaconImageId': null,
  'beaconEndAt': null,
  'allowsForward': null,
  'beaconTitle': null,
  'beaconKind': null,
  'postRootExcerpt': null,
  'postRootImageId': null,
  'eventsPreview': <Object?>[],
};

Future<void> _pumpHistory(WidgetTester tester, UpdatesFeedCubit cubit) async {
  const requiredPhoneSize = Size(375, 667);
  expect(kPhoneSurface, requiredPhoneSize);
  await usePhoneSurface(tester);
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: kPhoneSurface),
      child: TenturaResponsiveScope(
        child: MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: const UpdatesFeedPane(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.getSize(find.byType(Scaffold)), requiredPhoneSize);
  final paneContext = tester.element(find.byType(UpdatesFeedPane));
  expect(MediaQuery.sizeOf(paneContext), requiredPhoneSize);
  expect(Localizations.localeOf(paneContext), const Locale('ru'));
}

void _expectRows(WidgetTester tester, {int rowCount = 2}) {
  expect(find.byType(UpdatesFeedTile), findsNWidgets(rowCount));
  expect(find.text('Событие Activity'), findsOneWidget);
  expect(find.text('Событие My Desk'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

int _renderedUnreadCount(WidgetTester tester) {
  final tab = find.byKey(const ValueKey<String>('updates-unread'));
  expect(tab, findsOneWidget);
  final count = find.descendant(
    of: tab,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Text && RegExp(r'^\d+$').hasMatch(widget.data ?? ''),
    ),
  );
  expect(count, findsOneWidget);
  return int.parse(tester.widget<Text>(count).data!);
}

void _expectRussianBadgeLayout(WidgetTester tester) {
  final tab = find.byKey(const ValueKey<String>('updates-unread'));
  expect(find.text('Непрочитанные'), findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(
      of: tab,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText() == 'Непрочитанные',
      ),
    ),
  );
  expect(paragraph.didExceedMaxLines, isFalse);
}

Future<void> _drain() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _until(bool Function() done, String description) async {
  for (var i = 0; i < 200; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for $description');
}
