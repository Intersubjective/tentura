import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/screen/updates_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/attention/attention_case_test_support.dart';
import '../../support/attention_case_factory.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import 'support/noop_invite_setup_port.dart';

const _history = AttentionFeedDestinationId.history;
const _activity = AttentionFeedDestinationId.activityStream;
const _viewer = 'Uviewer000001';
const _readId = 'Nread00000001';
const _newId = 'Nnew000000001';
const _nextId = 'Nnew000000002';
const _deskId = 'Ndesk00000001';
const _deskBeaconId = 'Bdesk00000001';
const _readTitle = 'Earlier message';
const _newTitle = 'New reply';
const _noMatch = 'zzz';
const _timestamp = '2026-11-01T08:00:00Z';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('History Read all after a delayed response', () {
    test('keeps the new search after a page for the old search arrives', () {
      return _withFeed((feed) async {
        final history = feed.open(_history);
        await feed.deliverReceipt();
        await feed.search(history, _history, _newId);
        expect(_readAll(history), (true, true));

        final page = feed.server.holdNext(
          (request) =>
              request.operationName == 'AttentionFeed' &&
              request.variables['search'] == _newId,
        );
        final oldSearchRefresh = history.refresh();
        await _expectRefreshWaitingForPage(page, oldSearchRefresh);
        history.setSearch(_readId);
        await _sweepWithResponseHeld(feed, history, page, oldSearchRefresh);
        await feed.waitForSearch(_history, _readId);

        expect(history.state.searchText, _readId);
        expect(history.state.items.map((row) => row.id), [_readId]);
      });
    });

    test('prevents a second sweep while the fresh summary is pending', () {
      return _withFeed((feed) async {
        final history = feed.open(_history);
        await feed.deliverReceipt();
        await _until(() => history.state.firstLoadDone, 'History head');
        expect(_readAll(history), (true, true));

        final (summary, settled) = await feed.holdSurfaceSummary();
        await feed.search(history, _history, _noMatch);
        final freshSummary = feed.holdSurfaceSummaryWithUnread(0);
        expect(await history.markAllSeen(), isTrue);
        await summary.releaseAndWaitFor(settled());
        await freshSummary.waitForCapture(unread: 0);
        final afterStaleSummary = _readAll(history);
        if (history.state.canReadAll) await history.markAllSeen();
        final operationsAfterStaleSummary = feed.readAllOperations;
        await freshSummary.releaseAndWaitFor(feed.waitForSummary(0));
        expect(_readAll(history), (false, false));
        expect(history.state.searchText, _noMatch);

        final beforeDelivery = feed.sent.length;
        await feed.deliverReceipt(id: _nextId);
        await _until(
          () => _readAll(history) == (true, true),
          'Read all enabled',
        );
        expect(history.state.searchText, _noMatch);
        expect(await history.markAllSeen(), isTrue);
        await feed.waitForSummary(0);
        expect(_readAll(history), (false, false));
        expect(history.state.searchText, _noMatch);
        expect(
          feed.sent
              .skip(beforeDelivery)
              .where(
                (request) => request.operationName == 'AttentionDismissAll',
              ),
          hasLength(1),
        );
        final all = await feed.repository.fetch(view: AttentionView.all);
        final fresh = all.page.items.singleWhere((row) => row.id == _nextId);
        expect(fresh.isSeen, isTrue);
        expect(fresh.isCleared, isTrue);
        expect(
          [afterStaleSummary, operationsAfterStaleSummary],
          [
            (false, false),
            ['AttentionMarkAllSeen', 'AttentionDismissAll'],
          ],
        );
      });
    });

    test('keeps All selected when a page for Unread arrives', () {
      return _withFeed((feed) async {
        final history = feed.open(_history);
        await feed.deliverReceipt();
        await history.setView(AttentionView.unread);
        await feed.search(history, _history, _newId);
        expect(_readAll(history), (true, true));

        final page = feed.server.holdNext(
          (request) =>
              request.operationName == 'AttentionFeed' &&
              request.variables['search'] == _newId &&
              request.variables['view'] == 'unread',
        );
        final unreadRefresh = history.refresh();
        await _expectRefreshWaitingForPage(page, unreadRefresh);
        await history.setView(AttentionView.all);
        await _sweepWithResponseHeld(feed, history, page, unreadRefresh);

        expect(history.state.view, AttentionView.all);
        expect(history.state.searchText, _newId);
      });
    });

    testWidgets('disables the Russian phone button while totals catch up', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await tester.runAsync(
        () => _withFeed((feed) async {
          final services = GetIt.I;
          services.pushNewScope();
          services.registerSingleton(feed.attention);
          services.registerSingleton(feed.sync.case_);
          services.registerSingleton(Logger('history-delayed-response-screen'));
          services.registerSingleton<InviteAcceptedSetupPort>(
            NoopInviteAcceptedSetupPort(),
          );
          ensureNoopAttentionActorProfilesRegistered();
          try {
            await tester.pumpWidget(
              StackRouterScope(
                controller: _HistoryRouter(),
                stateHash: 0,
                child: MaterialApp(
                  theme: TenturaTheme.light(),
                  locale: const Locale('ru'),
                  localizationsDelegates: L10n.localizationsDelegates,
                  supportedLocales: L10n.supportedLocales,
                  home: const MediaQuery(
                    data: MediaQueryData(size: kPhoneSurface),
                    child: TenturaResponsiveScope(child: UpdatesScreen()),
                  ),
                ),
              ),
            );
            final history = tester
                .element(find.byType(Scaffold))
                .read<UpdatesFeedCubit>();
            await feed.deliverReceipt();
            await _until(() => history.state.firstLoadDone, 'History head');
            await tester.pumpAndSettle();

            final (summary, settled) = await feed.holdSurfaceSummary();
            await tester.tap(
              find.byTooltip(lookupL10n(const Locale('ru')).updatesSearchHint),
            );
            await tester.pumpAndSettle();
            final field = find.byType(TextField);
            await tester.enterText(field, _noMatch);
            await feed.waitForSearch(_history, _noMatch);
            await tester.pumpAndSettle();

            final readAll = find.widgetWithText(TextButton, 'Прочитать всё');
            expect(tester.widget<TextButton>(readAll).enabled, isTrue);
            final sweep = feed.attention.lastSweepOutcome
                .firstWhere((result) => result != null)
                .timeout(const Duration(seconds: 5));
            final freshSummary = feed.holdSurfaceSummaryWithUnread(0);
            await tester.tap(readAll);
            final firstSweep = await sweep;
            await summary.releaseAndWaitFor(settled());
            await freshSummary.waitForCapture(unread: 0);
            await tester.pumpAndSettle();

            final enabledAfterResponse = tester
                .widget<TextButton>(readAll)
                .enabled;
            if (enabledAfterResponse) {
              final secondSweep = feed.attention.lastSweepOutcome
                  .firstWhere(
                    (result) =>
                        result != null &&
                        result.operationId != firstSweep?.operationId,
                  )
                  .timeout(const Duration(seconds: 5));
              await tester.tap(readAll);
              await secondSweep;
            }
            final operationsAfterStaleSummary = feed.readAllOperations;
            await freshSummary.releaseAndWaitFor(feed.waitForSummary(0));
            await tester.pumpAndSettle();
            expect(tester.widget<TextButton>(readAll).enabled, isFalse);
            expect(tester.widget<TextField>(field).controller!.text, _noMatch);
            expect(tester.takeException(), isNull);
            expect(
              [enabledAfterResponse, operationsAfterStaleSummary],
              [
                false,
                ['AttentionMarkAllSeen', 'AttentionDismissAll'],
              ],
            );
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await services.popScope();
          }
        }),
      );
    });
  });

  for (final (name, view, beaconId, includeActivity) in [
    (
      'clears My Desk by Request from Unread',
      AttentionView.unread,
      _deskBeaconId,
      false,
    ),
    (
      'clears My Desk by receipt from Unread',
      AttentionView.unread,
      null,
      false,
    ),
    (
      'clears My Desk and Activity from All',
      AttentionView.all,
      _deskBeaconId,
      true,
    ),
  ]) {
    test(
      'History Read all with an empty search result $name',
      () => _withFeed((feed) async {
        feed.server.desk = _DeskReceipt(beaconId);
        feed.server.delivered = includeActivity;
        final history = feed.open(_history);
        await history.setView(view);
        await feed.search(history, _history, _noMatch);
        expect(history.state.view, view);
        expect(history.state.items, isEmpty);

        final before = await feed.repository.fetch(view: AttentionView.unread);
        expect(
          before.page.items.map((row) => row.id),
          unorderedEquals([_deskId, if (includeActivity) _newId]),
        );
        final desk = before.page.items.singleWhere((row) => row.id == _deskId);
        expect(desk.surface, AttentionSurface.myWork);
        expect(desk.beaconId, beaconId);
        expect(desk.isSeen, isFalse);
        expect(desk.isCleared, isFalse);
        expect(desk.requiresAction, isFalse);

        final beforeAction = feed.sent.length;
        expect(await history.markAllSeen(), isTrue);
        final requests = feed.sent.skip(beforeAction).toList();
        final sweep = requests.indexWhere(
          (request) => request.operationName == 'AttentionDismissAll',
        );
        expect(sweep, greaterThanOrEqualTo(0));
        final capture = requests.singleWhere(
          (request) => request.operationName == 'AttentionClearSnapshot',
        );
        expect(capture.variables['beaconId'], beaconId);
        expect(
          capture.variables['receiptId'],
          beaconId == null ? _deskId : null,
        );
        final readbacks = requests
            .skip(sweep + 1)
            .takeWhile((request) => request != capture)
            .where(
              (request) =>
                  request.operationName == 'AttentionFeed' &&
                  request.variables['view'] == 'unread',
            )
            // The open Unread tab also refreshes its own filtered head.
            .where(
              (request) =>
                  view != AttentionView.unread ||
                  request.variables['search'] != _noMatch,
            );
        expect(readbacks, isNotEmpty);
        expect(
          readbacks.map((request) => request.variables['search']),
          everyElement(isNull),
        );

        final deskUnread = await feed.repository.fetch(
          view: AttentionView.unread,
          surface: AttentionSurface.myWork,
        );
        expect(deskUnread.page.items, isEmpty);
        expect(deskUnread.summary.unreadTotal, 0);
        final historyUnread = await feed.repository.fetch(
          view: AttentionView.unread,
        );
        expect(historyUnread.page.items, isEmpty);
        final all = await feed.repository.fetch(view: AttentionView.all);
        final cleared = all.page.items.singleWhere((row) => row.id == _deskId);
        expect(cleared.isSeen, isTrue);
        expect(cleared.isCleared, isTrue);
        await feed.waitForSummary(0);
        expect(history.state.searchText, _noMatch);
        expect(history.state.items, isEmpty);
        expect(history.state.actionError, isNull);
      }),
    );
  }

  test(
    'History Read all follows new receipts outside an empty search through the sweep',
    () => _withFeed((feed) async {
      final history = feed.open(_history);
      final activity = feed.open(_activity);
      await feed.search(history, _history, _noMatch);
      await _until(() => activity.state.firstLoadDone, 'Activity head');
      expect(history.state.summary.unreadTotal, 0);
      expect(history.state.items, isEmpty);
      expect(_readAll(history), (false, false));

      final requestsBeforeRefresh = feed.sent.length;
      await history.refresh();
      expect(
        feed.sent
            .skip(requestsBeforeRefresh)
            .any(
              (request) =>
                  request.operationName == 'AttentionFeed' &&
                  request.variables['search'] == _noMatch,
            ),
        isTrue,
      );
      expect(history.state.refreshError, isNull);
      expect(history.state.summary.unreadTotal, 0);
      expect(_readAll(history), (false, false));
      expect(_readAll(activity), (false, false));

      await feed.deliverReceipt();
      expect(history.state.items, isEmpty);
      expect(history.state.searchText, _noMatch);
      expect(activity.state.searchText, isEmpty);
      expect(_readAll(activity), (true, true));
      final historyAfterDelivery = _readAll(history);
      final beforeSweep = await feed.repository.fetch(
        view: AttentionView.all,
        search: _noMatch,
      );
      expect(beforeSweep.page.items, isEmpty);
      final myWorkBeforeSweep = await feed.repository.fetch(
        view: AttentionView.all,
        surface: AttentionSurface.myWork,
      );

      // Record the enabled state before invoking the public action so the
      // baseline still exercises the real read and post-sweep refresh.
      expect(await history.markAllSeen(), isTrue);
      await feed.waitForSummary(0);
      final afterSweep = await feed.repository.fetch(
        view: AttentionView.all,
        search: _noMatch,
      );
      expect(afterSweep.page.items, isEmpty);
      expect(afterSweep.summary.unreadTotal, 0);
      expect(history.state.items, isEmpty);
      expect(history.state.searchText, _noMatch);
      expect(_readAll(history), (false, false));
      expect(activity.state.searchText, isEmpty);
      expect(_readAll(activity), (false, false));
      final activityRequests = feed.sent.where(
        (request) =>
            request.operationName == 'AttentionFeed' &&
            request.variables['surface'] == 'activity',
      );
      expect(activityRequests, isNotEmpty);
      expect(
        activityRequests.map((request) => request.variables['search']),
        everyElement(isNull),
      );
      expect(
        historyAfterDelivery,
        (true, true),
        reason: 'a sweepable receipt enables History even with no search hits',
      );
      expect(
        (
          beforeSweep.summary.unreadTotal,
          myWorkBeforeSweep.summary.unreadTotal,
        ),
        (1, 0),
        reason:
            'unread totals follow the requested surface even with no search hits',
      );
    }),
  );

  test(
    'History keeps matching read rows and enables Read all for a new nonmatching receipt',
    () => _withFeed((feed) async {
      final history = feed.open(_history);
      await feed.search(history, _history, _readId);
      expect(history.state.items.map((row) => row.id), [_readId]);
      expect(history.state.items.single.isSeen, isTrue);
      expect(history.state.summary.unreadTotal, 0);
      expect(_readAll(history), (false, false));

      await feed.deliverReceipt();
      expect(history.state.searchText, _readId);
      expect(history.state.items.map((row) => row.id), [_readId]);
      expect(history.state.items.single.isSeen, isTrue);
      final whileFiltered = _readAll(history);

      await feed.search(history, _history, '');
      expect(history.state.searchText, isEmpty);
      expect(history.state.items.map((row) => row.id), [_newId, _readId]);
      expect(history.state.summary.unreadTotal, 1);
      expect(_readAll(history), (true, true));
      expect(
        whileFiltered,
        (true, true),
        reason: 'the visible read row does not hide the new unread receipt',
      );
    }),
  );

  test(
    'AttentionFeed search ignores receipt titles and bodies',
    () => _withFeed((feed) async {
      final unfiltered = await feed.repository.fetch(view: AttentionView.all);
      expect(unfiltered.page.items.single.title, _readTitle);
      expect(unfiltered.page.items.single.body, 'Message preview');

      final matches = <String, List<String>>{};
      for (final search in ['Earlier', 'preview']) {
        final response = await feed.repository.fetch(
          view: AttentionView.all,
          search: search,
        );
        matches[search] = response.page.items.map((row) => row.id).toList();
      }
      expect(matches, {'Earlier': <String>[], 'preview': <String>[]});
    }),
  );

  test(
    'AttentionFeed search uses whole case-insensitive presentation payload tokens',
    () => _withFeed((feed) async {
      final matches = <String, List<String>>{};
      for (final search in [_readId, _readId.toUpperCase(), 'Nread']) {
        final response = await feed.repository.fetch(
          view: AttentionView.all,
          search: search,
        );
        matches[search] = response.page.items.map((row) => row.id).toList();
      }
      expect(matches, {
        _readId: [_readId],
        _readId.toUpperCase(): [_readId],
        'Nread': <String>[],
      });

      await feed.deliverReceipt();
      final unfiltered = await feed.repository.fetch(view: AttentionView.all);
      expect(unfiltered.page.items.map((row) => row.id), [_newId, _readId]);
      const searchableFields = {
        'eventType',
        'beaconId',
        'coordinationItemId',
        'targetEntityId',
        'messageId',
      };
      final searchedFields = <String>{};
      for (final row in unfiltered.page.items) {
        final payload =
            jsonDecode(row.presentationPayloadJson) as Map<String, dynamic>;
        if (row.id == _readId) {
          expect(payload['messageId'], _readId);
        }
        for (final field in searchableFields) {
          final value = payload[field] as String?;
          if (value == null || value.trim().isEmpty) {
            continue;
          }
          final response = await feed.repository.fetch(
            view: AttentionView.all,
            search: value,
          );
          expect(
            response.page.items.map((match) => match.id),
            contains(row.id),
            reason: field,
          );
          searchedFields.add(field);
        }
      }
      expect(searchedFields, searchableFields);
    }),
  );

  test(
    'AttentionFeed rejects a search on the Activity surface',
    () => _withFeed((feed) async {
      await expectLater(
        feed.repository.fetch(
          view: AttentionView.all,
          surface: AttentionSurface.activity,
          search: _noMatch,
        ),
        throwsA(
          isA<RemoteApiException>().having(
            (error) => error.message,
            'message',
            contains('must be null when surface is activity'),
          ),
        ),
      );
    }),
  );

  testWidgets(
    'History enables the Russian Read all button without changing the open search',
    (tester) async {
      await usePhoneSurface(tester);
      await tester.runAsync(
        () => _withFeed((feed) async {
          final services = GetIt.I;
          services.pushNewScope();
          services.registerSingleton(feed.attention);
          services.registerSingleton(feed.sync.case_);
          services.registerSingleton(Logger('history-search-screen'));
          services.registerSingleton<InviteAcceptedSetupPort>(
            NoopInviteAcceptedSetupPort(),
          );
          ensureNoopAttentionActorProfilesRegistered();
          try {
            final router = _HistoryRouter();
            await tester.pumpWidget(
              StackRouterScope(
                controller: router,
                stateHash: 0,
                child: MaterialApp(
                  theme: TenturaTheme.light(),
                  locale: const Locale('ru'),
                  localizationsDelegates: L10n.localizationsDelegates,
                  supportedLocales: L10n.supportedLocales,
                  home: const MediaQuery(
                    data: MediaQueryData(size: kPhoneSurface),
                    child: TenturaResponsiveScope(child: UpdatesScreen()),
                  ),
                ),
              ),
            );
            final screen = find.byType(Scaffold);
            final cubit = tester.element(screen).read<UpdatesFeedCubit>();
            await _until(() => cubit.state.firstLoadDone, 'History head');
            await tester.pumpAndSettle();
            await tester.tap(
              find.byTooltip(lookupL10n(const Locale('ru')).updatesSearchHint),
            );
            await tester.pumpAndSettle();
            final field = find.byType(TextField);
            await tester.enterText(field, _noMatch);
            await feed.waitForSearch(_history, _noMatch);
            await tester.pumpAndSettle();

            final readAll = find.widgetWithText(TextButton, 'Прочитать всё');
            expect(readAll, findsOneWidget);
            expect(cubit.state.items, isEmpty);
            expect(tester.widget<TextButton>(readAll).enabled, isFalse);
            expect(tester.takeException(), isNull);

            await feed.deliverReceipt();
            await tester.pumpAndSettle();
            expect(tester.widget<TextField>(field).controller!.text, _noMatch);
            expect(cubit.state.items, isEmpty);
            expect(tester.takeException(), isNull);
            expect(
              tester.widget<TextButton>(readAll).enabled,
              isTrue,
              reason: 'the incoming receipt enables the visible History action',
            );

            await tester.tap(readAll);
            await feed.waitForSummary(0);
            await tester.pumpAndSettle();
            expect(tester.widget<TextButton>(readAll).enabled, isFalse);
            expect(tester.widget<TextField>(field).controller!.text, _noMatch);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await services.popScope();
          }
        }),
      );
    },
  );
}

(bool, bool) _readAll(UpdatesFeedCubit cubit) =>
    (cubit.state.sweepEligible, cubit.state.canReadAll);

Future<void> _expectRefreshWaitingForPage(
  _HeldResponse page,
  Future<void> refresh,
) async {
  final capturedFirst = await Future.any([
    page.waitForCapture().then((_) => true),
    refresh.then((_) => false),
  ]);
  expect(capturedFirst, isTrue, reason: 'the refresh must await the held page');
}

Future<void> _sweepWithResponseHeld(
  _Feed feed,
  UpdatesFeedCubit history,
  _HeldResponse response,
  Future<void> refresh,
) async {
  expect(await history.markAllSeen(), isTrue);
  await feed.waitForSummary(0);
  expect(_readAll(history), (false, false));

  // The public refresh completes after the response goes through the
  // repository and the cubit projects the resulting state, even if the
  // response is discarded and the state stream has nothing to emit.
  await response.releaseAndWaitFor(refresh);
  expect(history.state.refreshError, isNull);
  final after = _readAll(history);
  if (history.state.canReadAll) await history.markAllSeen();
  expect(
    [after, feed.readAllOperations],
    [
      (false, false),
      ['AttentionMarkAllSeen', 'AttentionDismissAll'],
    ],
  );
}

Future<void> _until(bool Function() ready, String description) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline))
      fail('Timed out waiting for $description');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _withFeed(Future<void> Function(_Feed) body) async {
  final server = _ReceiptServer();
  final sent = <WireSent>[];
  await withRemoteWire(
    {},
    sent,
    (remote) async {
      final feed = _Feed(AttentionRepository(remote), server, sent);
      try {
        feed.accounts.emit(_viewer);
        await feed.waitForSummary(0);
        await body(feed);
      } finally {
        await feed.close();
      }
    },
    responseFor: server.respond,
    errorFor: server.errorFor,
  );
}

final class _Feed {
  _Feed(this.repository, this.server, this.sent) {
    attention = buildAttentionCase(
      repository: repository,
      accounts: accounts,
      realtimeSyncCase: sync.case_,
    );
  }

  final AttentionRepository repository;
  final _ReceiptServer server;
  final List<WireSent> sent;
  final accounts = AttentionCaseTestAccounts();
  final sync = buildTestRealtimeSync();
  final _cubits = <UpdatesFeedCubit>[];
  late final AttentionCase attention;

  List<String> get readAllOperations => [
    for (final request in sent)
      if (const {
        'AttentionMarkAllSeen',
        'AttentionDismissAll',
        'AttentionClear',
        'AttentionClearSnapshot',
      }.contains(request.operationName))
        request.operationName,
  ];

  UpdatesFeedCubit open(String destination) {
    final cubit = UpdatesFeedCubit(
      destinationId: destination,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('history-read-all-search'),
      actorProfiles: buildNoopAttentionActorProfiles(),
    );
    _cubits.add(cubit);
    return cubit;
  }

  Future<void> search(
    UpdatesFeedCubit cubit,
    String destination,
    String text,
  ) async {
    await _until(() => cubit.state.firstLoadDone, '$destination initial head');
    cubit.setSearch(text);
    await waitForSearch(destination, text);
  }

  Future<void> waitForSearch(String destination, String text) => _until(() {
    final session = attention.feedSession(destination);
    return session.searchText == text &&
        session.pages.containsKey(session.activeView);
  }, '$destination head for search "$text"');

  Future<void> deliverReceipt({String id = _newId}) async {
    server.receiptId = id;
    server.delivered = true;
    server._seen = false;
    server._cleared = false;
    _invalidateReceipts();
    await waitForSummary(1);
  }

  void _invalidateReceipts({String? beaconId}) {
    sync.port.emitChange(
      RealtimeEntityChange(
        kind: RealtimeEntityKind.notification,
        aggregateId: _viewer,
        childId: beaconId,
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
      ),
    );
  }

  Future<(_HeldResponse, Future<void> Function())> holdSurfaceSummary() async {
    const beaconId = 'Bbeacon000001';
    final hold = holdSurfaceSummaryWithUnread(1);
    // This notification is published when the coordinated refresh has
    // processed both wire responses, including when it discards them.
    final settled = attention.requestInvalidations.firstWhere(
      (id) => id == beaconId,
      orElse: () => '',
    );
    _invalidateReceipts(beaconId: beaconId);
    await hold.waitForCapture();
    return (
      hold,
      () async {
        expect(await settled.timeout(const Duration(seconds: 5)), beaconId);
      },
    );
  }

  _HeldResponse holdSurfaceSummaryWithUnread(int unread) => server.holdNext(
    (request) => request.operationName == 'AttentionSurfaceSummary',
    whereResponse: (response) =>
        (response['attentionSurfaceSummary']
            as Map<String, dynamic>)['unreadTotal'] ==
        unread,
  );

  Future<void> waitForSummary(int unread) => _until(() {
    final summary = attention.surfaceSummarySnapshot;
    return summary.historySummary?.unreadTotal == unread &&
        summary.forYouReceiptSweepEligible == (unread > 0);
  }, 'server surface summary with $unread unread');

  Future<void> close() async {
    server.releaseHeldResponses();
    for (final cubit in _cubits.reversed) {
      await cubit.close();
    }
    await attention.dispose();
    await sync.port.dispose();
    await accounts.dispose();
  }
}

class _HistoryRouter extends Mock implements StackRouter {
  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => false;
}

final class _DeskReceipt {
  _DeskReceipt(this.beaconId);

  final String? beaconId;
  bool seen = false;
  bool cleared = false;
}

// HTTP fixture for an already-cleared row, an optional Activity row taken by
// the sweep, and an optional My Desk row that requires a separate clear.
// The feed summary counts unread rows by surface independently of search.
// The server searches presentation payload fields and the actor name. These
// rows have no actor, so the fixture matches plain words against the payload.
// The Activity surface rejects non-blank search.
final class _ReceiptServer {
  bool delivered = false;
  String receiptId = _newId;
  _DeskReceipt? desk;
  bool _seen = false;
  bool _cleared = false;

  Map<String, dynamic>? errorFor(WireSent request) {
    if (request.operationName == 'AttentionFeed' &&
        request.variables['surface'] == AttentionSurface.activityWire &&
        _searchText(request).isNotEmpty) {
      return {'message': 'search must be null when surface is activity'};
    }
    return null;
  }

  String _searchText(WireSent request) =>
      (request.variables['search'] as String? ?? '').trim();

  final _heldResponses = <_HeldResponse>[];

  _HeldResponse holdNext(
    bool Function(WireSent) matches, {
    bool Function(Map<String, dynamic>)? whereResponse,
  }) {
    final hold = _HeldResponse(matches, whereResponse);
    _heldResponses.add(hold);
    return hold;
  }

  void releaseHeldResponses() {
    for (final hold in _heldResponses) {
      hold.open();
    }
  }

  Future<Map<String, dynamic>> respond(WireSent request) async {
    final response = _snapshot(request);
    for (final hold in _heldResponses) {
      if (hold.captured.isCompleted || !hold.matches(request, response)) {
        continue;
      }
      hold.captured.complete(response);
      await hold.gate.future;
      break;
    }
    return response;
  }

  Map<String, dynamic> _snapshot(WireSent request) {
    final desk = this.desk;
    final deskUnread = desk != null && !desk.cleared;
    switch (request.operationName) {
      case 'AttentionSurfaceSummary':
        final eligible = delivered && !_cleared;
        return {
          '__typename': 'query_root',
          'attentionSurfaceSummary': {
            '__typename': 'v2_AttentionSurfaceSummary',
            'myDeskDot': deskUnread,
            'myDeskCount': deskUnread ? 1 : 0,
            'forYouDot': eligible,
            'forYouSweepEligible': eligible,
            'forYouReceiptSweepEligible': eligible,
            'unreadTotal': (eligible ? 1 : 0) + (deskUnread ? 1 : 0),
            'needsYouTotal': 0,
          },
        };
      case 'AttentionFeed':
        final surface = request.variables['surface'];
        final onRequestedSurface =
            surface == null || surface == AttentionSurface.activityWire;
        final onDeskSurface =
            surface == null || surface == AttentionSurface.myWorkWire;
        final unread = onRequestedSurface && delivered && !_cleared;
        final all = request.variables['view'] == 'all';
        final search = _searchText(request);
        final searchWords = search.isEmpty
            ? null
            : search
                  .toLowerCase()
                  .split(RegExp('[^a-z0-9]+'))
                  .where(
                    (word) => word.isNotEmpty,
                  );
        return {
          '__typename': 'query_root',
          'attentionFeed': {
            '__typename': 'v2_AttentionFeed',
            'summary': {
              '__typename': 'v2_AttentionSummary',
              'unreadTotal':
                  (unread ? 1 : 0) + (onDeskSurface && deskUnread ? 1 : 0),
              'needsYouTotal': 0,
            },
            'page': {
              '__typename': 'v2_AttentionPage',
              'nextCursor': null,
              'items': [
                if (onRequestedSurface && delivered && (!_cleared || all))
                  _matchingReceipt(
                    receiptId,
                    _newTitle,
                    searchWords: searchWords,
                    seen: _seen,
                    cleared: _cleared,
                  ),
                if (onDeskSurface && desk != null && (deskUnread || all))
                  _matchingReceipt(
                    _deskId,
                    'My Desk reply',
                    searchWords: searchWords,
                    seen: desk.seen,
                    cleared: desk.cleared,
                    surface: AttentionSurface.myWorkWire,
                    beaconId: desk.beaconId,
                  ),
                if (onRequestedSurface && all)
                  _matchingReceipt(
                    _readId,
                    _readTitle,
                    searchWords: searchWords,
                    seen: true,
                    cleared: true,
                  ),
              ].nonNulls.toList(),
            },
          },
        };
      case 'AttentionMarkAllSeen':
        expect(request.variables['surface'], isNull);
        _seen = true;
        desk?.seen = true;
        return {
          '__typename': 'mutation_root',
          'attentionMarkAllSeen': (delivered ? 1 : 0) + (deskUnread ? 1 : 0),
        };
      case 'AttentionDismissAll':
        expect(request.variables['includeOutcomes'], isFalse);
        expect(_seen, isTrue);
        _cleared = true;
        return {
          '__typename': 'mutation_root',
          'attentionDismissAll': {
            '__typename': 'v2_AttentionDismissAllResult',
            'operationId': request.variables['operationId'],
            'status': 'complete',
            'appliedReceiptIds': [if (delivered) receiptId],
            'appliedOutcomeBeaconIds': <String>[],
            'appliedCount': delivered ? 1 : 0,
            'skipped': <Object>[],
            'failed': <Object>[],
            'pendingCount': 0,
            'undoToken': null,
            'undoDeadline': null,
          },
        };
      case 'AttentionClearSnapshot':
        final matched =
            deskUnread &&
            (desk.beaconId == null
                ? request.variables['receiptId'] == _deskId
                : request.variables['beaconId'] == desk.beaconId);
        return {
          '__typename': 'query_root',
          'attentionClearSnapshot': {
            '__typename': 'v2_AttentionClearSnapshot',
            'snapshotToken': matched ? 'desk-snapshot' : 'empty-snapshot',
            'receiptIds': [if (matched) _deskId],
            'outcomeGeneration': 0,
            'decisionRevision': 0,
          },
        };
      case 'AttentionClear':
        final applied =
            deskUnread && request.variables['snapshotToken'] == 'desk-snapshot';
        if (applied) desk.cleared = true;
        return {
          '__typename': 'mutation_root',
          'attentionClear': {
            '__typename': 'v2_AttentionClearResult',
            'operationId': request.variables['operationId'],
            'status': 'complete',
            'appliedReceiptIds': [if (applied) _deskId],
            'skippedReceiptIds': <String>[],
            'deniedReceiptIds': <String>[],
          },
        };
      default:
        fail('Unexpected GraphQL operation ${request.operationName}');
    }
  }
}

final class _HeldResponse {
  _HeldResponse(this._whereRequest, this._whereResponse);

  final bool Function(WireSent) _whereRequest;
  final bool Function(Map<String, dynamic>)? _whereResponse;
  final captured = Completer<Map<String, dynamic>>();
  final gate = Completer<void>();

  bool matches(WireSent request, Map<String, dynamic> response) =>
      _whereRequest(request) && (_whereResponse?.call(response) ?? true);

  Future<void> waitForCapture({int unread = 1}) async {
    final response = await captured.future.timeout(const Duration(seconds: 5));
    if (response['attentionSurfaceSummary']
        case final Map<String, dynamic> summary) {
      expect(summary['forYouReceiptSweepEligible'], unread > 0);
      expect(summary['unreadTotal'], unread);
    } else {
      final feed = response['attentionFeed'] as Map<String, dynamic>;
      expect((feed['summary'] as Map<String, dynamic>)['unreadTotal'], unread);
      expect(
        (feed['page'] as Map<String, dynamic>)['items'],
        contains(containsPair('id', _newId)),
      );
    }
  }

  void open() {
    if (!gate.isCompleted) gate.complete();
  }

  Future<void> releaseAndWaitFor(Future<void> processed) async {
    open();
    await processed.timeout(const Duration(seconds: 5));
  }
}

Map<String, dynamic>? _matchingReceipt(
  String id,
  String title, {
  required Iterable<String>? searchWords,
  required bool seen,
  required bool cleared,
  String surface = AttentionSurface.activityWire,
  String? beaconId = 'Bbeacon000001',
}) {
  final payload = {
    'eventType': 'roomMessagePosted',
    if (beaconId != null) 'beaconId': beaconId,
    'coordinationItemId': 'Icoord0000001',
    'targetEntityId': 'Ntarget000001',
    'messageId': id,
  };
  if (searchWords != null) {
    final tokens = payload.values.map((value) => value.toLowerCase()).toSet();
    if (searchWords.isEmpty || !searchWords.every(tokens.contains)) {
      return null;
    }
  }
  return {
    '__typename': 'v2_AttentionReceipt',
    'id': id,
    'category': 'requestProgress',
    'kind': 'newMessage',
    'priority': 'low',
    'title': title,
    'body': 'Message preview',
    'actionUrl': '/#/',
    'createdAt': _timestamp,
    'beaconId': surface == AttentionSurface.myWorkWire ? beaconId : null,
    'seenAt': seen ? _timestamp : null,
    'collapsedCount': 1,
    'sourceEventKey': id,
    'presentationPayloadJson': jsonEncode(payload),
    'requiresAction': false,
    'clearedAt': cleared ? _timestamp : null,
    'clearReason': cleared ? 'manual' : null,
    'surface': surface,
    'itemKind': 'receipt',
    'eventsPreview': <Object?>[],
  };
}
