@Tags(['pg', 'repo-files'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/inbox/ui/widget/tombstone_row.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/attention_case_factory.dart';
import '../../domain/attention/attention_case_test_support.dart';
import '../../support/fake_app_navigator.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/phone_surface.dart';
import '../../support/production_receipt_transport.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../inbox/inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;
import '../inbox/author_invite_test_support.dart';
import 'support/noop_invite_setup_port.dart';

// What the viewer sees on screen: tapping «Read all» on History must clear
// the unread dots on the Activity rows and leave the rows themselves. Real
// path: production GraphQL server on Postgres -> Ferry -> repository -> case
// -> cubits -> widgets. Only the Hasura-side hydration of the pending
// forwarded Request's card is a fake (the receipt server speaks GraphQL
// only); which Requests are pending, and whether they are unread, is the
// server's answer.
const _viewer = 'Ua00000000005';
const _tombstoneBeaconId = 'Bfwdtomb00001';
const _pendingBeaconId = 'Bfwdreq000001';

Future<void> _until(bool Function() ready, {Object? Function()? why}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out: ${why?.call()}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _HarnessRouter extends Mock implements StackRouter {}

final class _ForwardRepo implements ForwardRepository {
  final _helpOfferChanges = StreamController<HelpOfferEvent>.broadcast();
  final _forwardChanges = StreamController<String>.broadcast();
  final _forwardCommandCompleted = StreamController<String>.broadcast();

  @override
  Stream<HelpOfferEvent> get helpOfferChanges => _helpOfferChanges.stream;

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Stream<String> get forwardCommandCompleted => _forwardCommandCompleted.stream;

  @override
  Future<void> dispose() async {
    await _helpOfferChanges.close();
    await _forwardChanges.close();
    await _forwardCommandCompleted.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestInboxCubit extends Cubit<InboxState> implements InboxCubit {
  _TestInboxCubit(super.initialState);

  @override
  Future<bool> fetch({bool showLoading = true, bool showError = true}) async =>
      true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

InboxItem _pendingItem() {
  final at = DateTime.utc(2026, 6, 20);
  return InboxItem(
    beaconId: _pendingBeaconId,
    latestForwardAt: at,
    beacon: Beacon(
      id: _pendingBeaconId,
      title: 'Pending forwarded Request',
      author: const Profile(id: 'Ua00000000001', displayName: 'Anna'),
      createdAt: at,
      updatedAt: at,
    ),
  );
}

/// History pane, Activity stream and Activity offers over one case, like an
/// open app.
final class _App {
  _App._(
    this.remote,
    this.accounts,
    this.sync,
    this.attention,
    this.history,
    this.activity,
    this.offers,
    this.inbox,
  );

  final RemoteApiService remote;
  final AttentionCaseTestAccounts accounts;
  final ({RealtimeSyncCase case_, TestRealtimeSyncPort port}) sync;
  final AttentionCase attention;
  final UpdatesFeedCubit history;
  final UpdatesFeedCubit activity;
  final ActivityOffersCubit offers;
  final FakeInboxRepository inbox;

  static Future<_App> open() async {
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
    );
    await remote.setSessionAuth();
    final accounts = AttentionCaseTestAccounts();
    final sync = buildTestRealtimeSync();
    final attention = buildAttentionCase(
      repository: AttentionRepository(remote),
      accounts: accounts,
      realtimeSyncCase: sync.case_,
      blockCase: noopBlockCase(),
      feedSessions: FeedSessionRegistry(),
      logger: Logger('history-read-all-activity-widget'),
    );
    accounts.emit(_viewer);
    await Future<void>.delayed(Duration.zero);
    final inbox = FakeInboxRepository()
      ..inboxItemsByBeacon = {_pendingBeaconId: _pendingItem()}
      ..openForwardsCount = 1;
    final inboxCase = buildTestInboxCase(
      inbox,
      buildTestBeaconThreadsCase(),
      forwardRepository: _ForwardRepo(),
      realtimeSyncCase: sync.case_,
    );
    UpdatesFeedCubit cubit(String destination) => UpdatesFeedCubit(
      destinationId: destination,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('history-read-all-activity-widget-cubit'),
      actorProfiles: buildNoopAttentionActorProfiles(),
    );
    final history = cubit(AttentionFeedDestinationId.history);
    final activity = cubit(AttentionFeedDestinationId.activityStream);
    final offers = ActivityOffersCubit(
      userId: _viewer,
      inboxCase: inboxCase,
      attentionCase: attention,
      authorInviteCase: buildAuthorInviteCase(FakeAuthorInvitePort()),
      actorProfiles: buildNoopAttentionActorProfiles(),
    );
    final app = _App._(
      remote,
      accounts,
      sync,
      attention,
      history,
      activity,
      offers,
      inbox,
    );
    try {
      await offers.loadFirst();
      await _until(() => history.state.firstLoadDone, why: () => 'History');
      await _until(() => activity.state.firstLoadDone, why: () => 'Activity');
    } on Object {
      await app.close();
      rethrow;
    }
    return app;
  }

  Future<void> close() async {
    await history.close();
    await activity.close();
    await offers.close();
    await attention.dispose();
    await sync.port.dispose();
    await accounts.dispose();
    await remote.close();
  }
}

Future<void> _withApp(
  WidgetTester tester,
  Future<void> Function(_App app, ProductionReceiptTransport transport) body, {
  void Function(Map<String, dynamic> request, http.Response response)?
  onGraphqlResponse,
}) =>
    tester.runAsync(() async {
          final transport = await ProductionReceiptTransport.start(
            activityRowsFixture: true,
          );
          try {
            await http.runWithClient(
              () async {
                final app = await _App.open();
                try {
                  await body(app, transport);
                } finally {
                  await app.close();
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
                final payload =
                    jsonDecode(request.body) as Map<String, dynamic>;
                final response = await transport.graphql(_viewer, payload);
                onGraphqlResponse?.call(payload, response);
                return response;
              }),
            );
          } finally {
            await transport.close();
          }
        })
        as Future<void>;

MaterialApp _materialApp(Locale locale, Widget body) => MaterialApp(
  theme: TenturaTheme.light(),
  locale: locale,
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: TenturaResponsiveScope(child: Scaffold(body: body)),
);

Future<void> _pumpHistory(
  WidgetTester tester,
  _App app,
  Locale locale,
) async {
  await tester.pumpWidget(
    _materialApp(
      locale,
      BlocProvider.value(value: app.history, child: const UpdatesFeedPane()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpActivity(
  WidgetTester tester,
  _App app,
  Locale locale,
) async {
  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(app.attention);
  addTearDown(() async {
    if (GetIt.I.isRegistered<AttentionCase>()) {
      GetIt.I.unregister<AttentionCase>();
    }
  });
  ensureNoopAttentionActorProfilesRegistered();
  if (!GetIt.I.isRegistered<AppNavigator>()) registerFakeAppNavigator();
  await tester.pumpWidget(
    StackRouterScope(
      controller: _HarnessRouter(),
      stateHash: 0,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ActivityOffersCubit>.value(value: app.offers),
          BlocProvider<UpdatesFeedCubit>.value(value: app.activity),
          BlocProvider<InboxCubit>.value(
            value: _TestInboxCubit(const InboxState(projectionLoaded: true)),
          ),
        ],
        child: _materialApp(locale, const ActivityStreamView()),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _identified(String identifier) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == identifier,
  description: 'semantics $identifier',
);

Finder _tombstoneRow() =>
    _identified(TestIds.activityForwardRow(_tombstoneBeaconId));

Finder _pendingRow() => _identified(TestIds.activityOffer(_pendingBeaconId));

Finder _tombstoneDot() => find.descendant(
  of: _tombstoneRow(),
  matching: find.byKey(TombstoneRow.unreadDotKey),
);

/// Whether Activity marks the pending forwarded Request unread. The pinned
/// card draws no dot of its own for a plain Request, so the read state is
/// what the offers cubit hands the view (`unseenBeaconIds`, which feeds the
/// card's unseen flag).
bool _pendingIsUnread(_App app) =>
    app.offers.state.unseenQueryComplete &&
    app.offers.state.unseenBeaconIds.contains(_pendingBeaconId);

Future<void> _readAllOnHistory(
  WidgetTester tester,
  _App app,
  String label,
) async {
  await tester.tap(find.text(label));
  await _until(
    () => app.history.state.summary.unreadTotal == 0,
    why: () => app.history.state,
  );
  // Opening Activity afterwards shows the server's current stream.
  await app.activity.refresh();
  await app.offers.loadFirst();
}

void main() {
  testWidgets(
    'History Unread offers Read all for a newly closed forward and clears '
    'its Activity dot',
    (tester) async {
      await usePhoneSurface(tester);
      const locale = Locale('ru');
      const closedLabel = 'Автор закрыл запрос до вашего ответа';
      final readAll = find.widgetWithText(TextButton, 'Прочитать всё');
      var markAllResponses = 0;
      Map<String, dynamic>? activityFeed;
      Map<String, dynamic>? historyUnreadFeed;
      Iterable<Map<String, dynamic>> requestItems(Map<String, dynamic>? feed) {
        expect(feed, isNotNull, reason: 'The app fetched the feed');
        final page = feed!['page'] as Map<String, dynamic>;
        return (page['items'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .where((item) => item['beaconId'] == _pendingBeaconId);
      }

      await _withApp(
        tester,
        (app, transport) async {
          await _until(() => app.history.state.canReadAll);
          await _pumpHistory(tester, app, locale);
          expect(tester.widget<TextButton>(readAll).onPressed, isNotNull);
          await tester.tap(readAll);
          await _until(
            () =>
                markAllResponses == 1 &&
                app.history.state.summary.unreadTotal == 0 &&
                !app.history.state.canReadAll,
            why: () =>
                'History after reading the open forward: ${app.history.state}',
          );

          // The transport seeds Postgres and executes these queries with the
          // production schema. Compare the same Request across the mutation.
          expect(
            requestItems(activityFeed).where(
              (item) => item['forwardOutcome'] == 'closedBeforeResponse',
            ),
            isEmpty,
            reason: 'Activity has no closure outcome before the author closes',
          );
          final close = await transport.graphql('Ua00000000001', {
            'query': r'''
              mutation CloseForwardedRequest($beaconId: String!) {
                beaconClose(beaconId: $beaconId)
              }
            ''',
            'variables': {'beaconId': _pendingBeaconId},
          });
          expect(jsonDecode(close.body), {
            'data': {'beaconClose': true},
          });

          activityFeed = null;
          historyUnreadFeed = null;
          await app.activity.refresh();
          await app.offers.loadFirst();
          await app.history.setView(AttentionView.unread);
          await app.history.refresh();
          await _until(
            () =>
                activityFeed != null &&
                historyUnreadFeed != null &&
                !app.history.state.isLoading,
            why: () => 'Activity and History Unread responses after closure',
          );
          expect(app.history.state.hasRefreshError, isFalse);
          final wireForward = requestItems(
            activityFeed,
          ).where((item) => item['itemKind'] == 'forward');
          expect(wireForward, hasLength(1));
          expect(
            wireForward.single,
            containsPair('forwardOutcome', 'closedBeforeResponse'),
          );
          expect(wireForward.single, containsPair('seenAt', isNull));
          final closedRow = _identified(
            TestIds.activityForwardRow(_pendingBeaconId),
          );
          final dot = find.descendant(
            of: closedRow,
            matching: find.byKey(TombstoneRow.unreadDotKey),
          );
          final outcome = find.descendant(
            of: closedRow,
            matching: find.text(closedLabel),
          );
          await _pumpActivity(tester, app, locale);
          expect(outcome, findsOneWidget);
          expect(dot, findsOneWidget);
          expect(tester.takeException(), isNull);

          await _pumpHistory(tester, app, locale);
          expect(
            {
              'wire has unread closure':
                  requestItems(
                    historyUnreadFeed,
                  ).any(
                    (item) =>
                        item.containsKey('seenAt') && item['seenAt'] == null,
                  ),
              'History Unread lists the closure': app.history.state.items.any(
                (item) => item.beaconId == _pendingBeaconId && !item.isSeen,
              ),
              'canReadAll': app.history.state.canReadAll,
              'Read all button enabled':
                  tester.widget<TextButton>(readAll).onPressed != null,
            },
            {
              'wire has unread closure': true,
              'History Unread lists the closure': true,
              'canReadAll': true,
              'Read all button enabled': true,
            },
            reason: 'History before reading the closure',
          );

          await tester.tap(readAll);
          await _until(
            () =>
                markAllResponses == 2 &&
                app.history.state.summary.unreadTotal == 0 &&
                !app.history.state.canReadAll,
            why: () =>
                'History after reading the closure: ${app.history.state}',
          );
          activityFeed = null;
          historyUnreadFeed = null;
          await app.history.refresh();
          await app.activity.refresh();
          await _until(
            () =>
                activityFeed != null &&
                historyUnreadFeed != null &&
                !app.history.state.isLoading,
            why: () => 'Refetched Activity and History Unread after Read all',
          );
          expect(requestItems(historyUnreadFeed), isEmpty);
          expect(
            historyUnreadFeed!['summary'],
            containsPair('unreadTotal', 0),
          );
          final readForward = requestItems(
            activityFeed,
          ).singleWhere((item) => item['itemKind'] == 'forward');
          expect(readForward, containsPair('seenAt', isNotNull));
          expect(app.history.state.hasRefreshError, isFalse);
          expect(app.history.state.items, isEmpty);
          expect(app.history.state.summary.unreadTotal, 0);
          expect(app.history.state.canReadAll, isFalse);
          await _pumpHistory(tester, app, locale);
          expect(tester.widget<TextButton>(readAll).onPressed, isNull);
          await _pumpActivity(tester, app, locale);
          expect(outcome, findsOneWidget);
          expect(dot, findsNothing);
          expect(tester.takeException(), isNull);
        },
        onGraphqlResponse: (request, response) {
          final operation = request['operationName'];
          if (operation != 'AttentionMarkAllSeen' &&
              operation != 'AttentionFeed') {
            return;
          }
          final envelope = jsonDecode(response.body) as Map<String, dynamic>;
          final data = envelope['data'] as Map<String, dynamic>?;
          if (envelope['errors'] != null || data == null) return;
          if (operation == 'AttentionMarkAllSeen') {
            if (data['attentionMarkAllSeen'] is int) markAllResponses++;
            return;
          }
          final variables = request['variables'] as Map<String, dynamic>;
          final feed = data['attentionFeed'] as Map<String, dynamic>;
          if (variables['surface'] == 'activity' &&
              variables['view'] == 'all') {
            activityFeed = feed;
          }
          if (variables['surface'] == null && variables['view'] == 'unread') {
            historyUnreadFeed = feed;
          }
        },
      );
    },
  );

  for (final (locale, label) in const [
    (Locale('en'), 'Read all'),
    (Locale('ru'), 'Прочитать всё'),
  ]) {
    testWidgets(
      'tapping "$label" on History leaves the outcome row and the pending '
      'forwarded Request in Activity and clears both unread dots '
      '(${locale.languageCode})',
      (tester) async {
        await usePhoneSurface(tester);
        await _withApp(tester, (app, _) async {
          await _pumpActivity(tester, app, locale);
          expect(_tombstoneRow(), findsOneWidget, reason: 'precondition');
          expect(_pendingRow(), findsOneWidget, reason: 'precondition');
          expect(_tombstoneDot(), findsOneWidget, reason: 'precondition: dot');
          expect(
            _pendingIsUnread(app),
            isTrue,
            reason: 'precondition: pending forwarded Request is unread',
          );

          await _pumpHistory(tester, app, locale);
          await _readAllOnHistory(tester, app, label);
          await _pumpActivity(tester, app, locale);

          expect(_tombstoneRow(), findsOneWidget);
          expect(
            find.descendant(
              of: _tombstoneRow(),
              matching: find.byType(TombstoneRow),
            ),
            findsOneWidget,
          );
          expect(_pendingRow(), findsOneWidget);
          expect(_tombstoneDot(), findsNothing);
          expect(_pendingIsUnread(app), isFalse);
        });
      },
    );
  }

  testWidgets(
    'tapping Read all on History never drops the outcome row or the pending '
    'forwarded Request from Activity, not even for one frame',
    (tester) async {
      await usePhoneSurface(tester);
      await _withApp(tester, (app, _) async {
        await _pumpHistory(tester, app, const Locale('en'));
        final streamFrames = <List<String>>[];
        final offerFrames = <List<String>>[];
        final subs = [
          app.activity.stream.listen(
            (state) => streamFrames.add([for (final r in state.items) r.id]),
          ),
          app.offers.stream.listen(
            (state) => offerFrames.add([
              for (final i in state.items) i.beaconId,
            ]),
          ),
        ];
        await _readAllOnHistory(tester, app, 'Read all');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        for (final sub in subs) {
          await sub.cancel();
        }
        expect(
          streamFrames,
          isNotEmpty,
          reason: 'Read all moved the Activity stream',
        );
        expect(
          offerFrames,
          isNotEmpty,
          reason: 'Read all moved the Activity offers',
        );
        for (final ids in streamFrames) {
          expect(ids, contains('inbox:$_tombstoneBeaconId'));
        }
        for (final ids in offerFrames) {
          expect(ids, contains(_pendingBeaconId));
        }
        expect(app.offers.state.items.map((i) => i.beaconId), [
          _pendingBeaconId,
        ]);
      });
    },
  );
}
