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
const _readTitle = 'Earlier message';
const _newTitle = 'New reply';
const _noMatch = 'zzz';
const _timestamp = '2026-11-01T08:00:00Z';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Future<void> deliverReceipt() async {
    server.delivered = true;
    sync.port.emitChange(
      const RealtimeEntityChange(
        kind: RealtimeEntityKind.notification,
        aggregateId: _viewer,
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
      ),
    );
    await waitForSummary(1);
  }

  Future<void> waitForSummary(int unread) => _until(() {
    final summary = attention.surfaceSummarySnapshot;
    return summary.historySummary?.unreadTotal == unread &&
        summary.forYouReceiptSweepEligible == (unread > 0);
  }, 'server surface summary with $unread unread');

  Future<void> close() async {
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

// HTTP fixture for one already-read, cleared row and a later sweepable row.
// The feed summary counts unread rows by surface independently of search.
// The server searches presentation payload fields and the actor name. These
// rows have no actor, so the fixture matches plain words against the payload.
// The Activity surface rejects non-blank search.
final class _ReceiptServer {
  bool delivered = false;
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

  Future<Map<String, dynamic>> respond(WireSent request) async {
    switch (request.operationName) {
      case 'AttentionSurfaceSummary':
        final eligible = delivered && !_cleared;
        return {
          '__typename': 'query_root',
          'attentionSurfaceSummary': {
            '__typename': 'v2_AttentionSurfaceSummary',
            'myDeskDot': false,
            'myDeskCount': 0,
            'forYouDot': eligible,
            'forYouSweepEligible': eligible,
            'forYouReceiptSweepEligible': eligible,
            'unreadTotal': eligible ? 1 : 0,
            'needsYouTotal': 0,
          },
        };
      case 'AttentionFeed':
        final surface = request.variables['surface'];
        final onRequestedSurface =
            surface == null || surface == AttentionSurface.activityWire;
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
              'unreadTotal': unread ? 1 : 0,
              'needsYouTotal': 0,
            },
            'page': {
              '__typename': 'v2_AttentionPage',
              'nextCursor': null,
              'items': [
                if (onRequestedSurface && delivered && (!_cleared || all))
                  _matchingReceipt(
                    _newId,
                    _newTitle,
                    searchWords: searchWords,
                    seen: _seen,
                    cleared: _cleared,
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
        expect(delivered, isTrue);
        _seen = true;
        return {'__typename': 'mutation_root', 'attentionMarkAllSeen': 1};
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
            'appliedReceiptIds': [_newId],
            'appliedOutcomeBeaconIds': <String>[],
            'appliedCount': 1,
            'skipped': <Object>[],
            'failed': <Object>[],
            'pendingCount': 0,
            'undoToken': null,
            'undoDeadline': null,
          },
        };
      default:
        fail('Unexpected GraphQL operation ${request.operationName}');
    }
  }
}

Map<String, dynamic>? _matchingReceipt(
  String id,
  String title, {
  required Iterable<String>? searchWords,
  required bool seen,
  required bool cleared,
}) {
  final payload = {
    'eventType': 'roomMessagePosted',
    'beaconId': 'Bbeacon000001',
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
    'seenAt': seen ? _timestamp : null,
    'collapsedCount': 1,
    'sourceEventKey': id,
    'presentationPayloadJson': jsonEncode(payload),
    'requiresAction': false,
    'clearedAt': cleared ? _timestamp : null,
    'clearReason': cleared ? 'manual' : null,
    'surface': AttentionSurface.activityWire,
    'itemKind': 'receipt',
    'eventsPreview': <Object?>[],
  };
}
