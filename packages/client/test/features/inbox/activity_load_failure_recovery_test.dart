// Activity (For You) after an HTTP transport failure.
//
// Real path: HTTP (MockClient) → RemoteApiService (with the real reachability
// link) → AttentionRepository / InboxRepository → AttentionCase / InboxCase →
// ActivityOffersCubit, UpdatesFeedCubit, InboxCubit → InboxScreen. Only HTTP
// and unrelated shell dependencies (profile, home chrome, realtime socket
// port, forward/room fakes) are substituted.
//
// Activity's first load issues `ActivityOffersV2` (the pinned zone) and
// `AttentionFeed` (the stream); the screen opens once both have landed.
// `InboxFetch` (InboxCubit) and `AttentionSurfaceSummary` (AttentionCase on
// account change) load alongside them.
//
// Reachability: `NetworkReachability.forTesting()` with no probe injected
// does not probe the server on its own, so `reachability.reportSuccess()`
// stands in for a successful reachability probe (the probe itself is covered
// by test/data/service/network_reachability_probe_test.dart). Going offline
// is never faked: the MockClient throws «Failed to fetch» and the real
// reachability link reports the transport failure.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/data/service/network_reachability.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/network_reachability_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/inbox_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

import '../../support/noop_attention_actor_profiles.dart';
import '../../support/noop_posts_case.dart';
import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../block/support/controllable_block_case.dart' show noopBlockCase;
import '../my_work/my_work_test_support.dart'
    show FakeForwardRepository, FakeRoomHints, buildTestBeaconThreadsCase;
import '../updates/support/noop_invite_setup_port.dart';

const _viewerId = 'Uviewer0000001';

/// The Activity row seeded by the server once it answers.
const _receiptTitle = 'Delivery arranged for Friday';

/// Activity's two primary reads: the screen opens when both have landed.
const _offersOp = 'ActivityOffersV2';
const _feedOp = 'AttentionFeed';

enum _Transport {
  /// Every GraphQL request fails in the transport (browser: «Failed to
  /// fetch»), the way an offline network looks to the HTTP client.
  down,

  /// Every GraphQL request is sent and never answered.
  silent,

  /// The server answers.
  up,
}

/// The fake server behind the only substituted boundary: HTTP.
class _Server {
  _Transport transport = _Transport.down;

  final requests = <String, int>{};
  final unexpected = <String>[];
  final _held = <Completer<http.Response>>[];

  int count(String operation) => requests[operation] ?? 0;

  /// Unblocks never-answered requests so the service can close.
  void releaseHeld() {
    for (final held in _held) {
      if (!held.isCompleted) {
        held.completeError(http.ClientException('test finished'));
      }
    }
  }

  http.Client createClient() => MockClient((request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return _json({
        'subject': _viewerId,
        'access_token': 'test-token',
        'expires_in': 3600,
      });
    }
    final payload = jsonDecode(request.body) as Map<String, dynamic>;
    final name = payload['operationName'] as String;
    requests[name] = count(name) + 1;
    switch (transport) {
      case _Transport.down:
        throw http.ClientException('Failed to fetch', request.url);
      case _Transport.silent:
        final held = Completer<http.Response>();
        _held.add(held);
        return held.future;
      case _Transport.up:
        break;
    }
    final data = switch (name) {
      _offersOp => <String, dynamic>{
        'activityOffers': {
          '__typename': 'ActivityOffersPage',
          'totalCount': 0,
          'nextCursor': null,
          'items': <Object>[],
        },
      },
      _feedOp => <String, dynamic>{
        'attentionFeed': {
          '__typename': 'AttentionFeed',
          'summary': {
            '__typename': 'AttentionSummary',
            'unreadTotal': 1,
            'needsYouTotal': 0,
          },
          'page': {
            '__typename': 'AttentionPage',
            'nextCursor': null,
            'items': [_wireReceipt()],
          },
        },
      },
      'AttentionSurfaceSummary' => <String, dynamic>{
        'attentionSurfaceSummary': {
          '__typename': 'AttentionSurfaceSummary',
          'unreadTotal': 1,
          'needsYouTotal': 0,
          'myDeskDot': false,
          'myDeskCount': 0,
          'forYouDot': false,
          'forYouSweepEligible': false,
        },
      },
      'InboxFetch' => <String, dynamic>{'inbox_item': <Object>[]},
      _ => null,
    };
    if (data == null) {
      unexpected.add(name);
      return _json({
        'data': null,
        'errors': [
          {'message': 'Unexpected operation in test: $name'},
        ],
      });
    }
    return _json({'data': data});
  });
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _wireReceipt() => {
  '__typename': 'v2_AttentionReceipt',
  'id': 'Ndelivery00001',
  'category': 'requestProgress',
  'kind': 'relayReceived',
  'priority': 'normal',
  'title': _receiptTitle,
  'body': 'A neighbour has confirmed',
  'actionUrl': '/#/',
  'createdAt': '2026-10-28T00:00:00.000Z',
  'seenAt': null,
  'collapsedCount': 1,
  'beaconId': null,
  'coordinationItemId': null,
  'actorUserId': null,
  'sourceEventKey': null,
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
  'historyLifecycleEligible': null,
  'surface': 'activity',
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
  'eventsPreview': <Object>[],
};

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: _viewerId, displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => const Stream.empty();

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

class _EmptyForwardRepository extends FakeForwardRepository {
  @override
  Stream<String> get forwardCommandCompleted => const Stream.empty();
}

enum _Surface {
  phoneRu(Locale('ru'), 'ru 375x667'),
  desktopEn(Locale('en'), 'en 1280x800');

  const _Surface(this.locale, this.label);

  final Locale locale;
  final String label;
}

Future<void> _useSurface(WidgetTester tester, _Surface surface) async {
  switch (surface) {
    case _Surface.phoneRu:
      await usePhoneSurface(tester);
    case _Surface.desktopEn:
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
  }
}

/// Builds the real chain on [server] and shows the Activity screen, then runs
/// [body]. Everything is torn down before the service closes.
Future<void> _withActivity(
  WidgetTester tester,
  _Server server,
  Future<void> Function(NetworkReachability reachability) body, {
  _Surface surface = _Surface.desktopEn,
}) => http.runWithClient(() async {
  await _useSurface(tester, surface);
  final reachability = NetworkReachability.forTesting();
  GetIt.I
    ..registerSingleton<NetworkReachabilityPort>(reachability)
    ..registerSingleton<NetworkReachability>(reachability);
  final remote = RemoteApiService(
    const Env(),
    const WebSocketClientRealtimeSocketFactory(),
    reachability: reachability,
  );
  await tester.runAsync(remote.setSessionAuth);

  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final logger = Logger('activity-load-failure-recovery');
  final effects = FakeUiEffectPort();
  final attention = AttentionCase(
    AttentionRepository(remote),
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    logger,
  );
  final inboxRepository = InboxRepository(
    remote,
    BeaconRoomHintsRepository(remote),
  );
  final inboxCase = InboxCase(
    inboxRepository,
    buildTestBeaconThreadsCase(FakeRoomHints()),
    _EmptyForwardRepository(),
    sync.case_,
    BookkeepingRefreshSignal(),
    noopBlockCase(),
    env: const Env(),
    logger: logger,
  );
  registerNoopPostsCase(sync.case_);
  ensureNoopAttentionActorProfilesRegistered();
  GetIt.I
    ..registerSingleton<AttentionCase>(attention)
    ..registerSingleton<InboxCase>(inboxCase)
    ..registerSingleton<InviteAcceptedSetupPort>(NoopInviteAcceptedSetupPort())
    ..registerSingleton<RealtimeSyncCase>(sync.case_)
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<Logger>(logger);

  accounts.emit(_viewerId);
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }

  final inboxCubit = InboxCubit(
    userId: _viewerId,
    inboxCase: inboxCase,
    effects: effects,
  );
  final homeAttention = HomeAttentionCubit(attention, accounts, logger);
  final reselect = HomeTabReselectCubit();
  final screen = ScreenCubit.local(effects);

  try {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<InboxCubit>.value(value: inboxCubit),
          BlocProvider<HomeAttentionCubit>.value(value: homeAttention),
          BlocProvider<HomeTabReselectCubit>.value(value: reselect),
          BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
          BlocProvider<ScreenCubit>.value(value: screen),
        ],
        child: MaterialApp(
          locale: surface.locale,
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const TenturaResponsiveScope(child: InboxScreen()),
        ),
      ),
    );
    await body(reachability);
  } finally {
    server.releaseHeld();
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    // Not awaited: a broadcast controller's close() waits for listeners that
    // asBroadcastStream() keeps subscribed for good, which would hang under
    // fake async.
    unawaited(inboxCubit.close());
    unawaited(homeAttention.close());
    unawaited(reselect.close());
    unawaited(screen.close());
    unawaited(attention.dispose());
    unawaited(accounts.close());
    unawaited(sync.port.dispose());
    unawaited(inboxRepository.dispose());
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    await tester.runAsync(remote.close);
    unawaited(reachability.dispose());
    await GetIt.I.reset();
  }
}, server.createClient);

/// Pumps [total] of fake time in bounded 100 ms frames.
Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

/// Well past the gate's 150 ms spinner delay and its 2.5 s timeout.
const _settle = Duration(seconds: 3);

L10n _l10n(WidgetTester tester) =>
    L10n.of(tester.element(find.byType(InboxScreen)))!;

/// What a user sees after a failed load: «No connection» with «Try again»,
/// and no spinner promising that something is still on its way.
void _expectNoConnectionPanel(WidgetTester tester, {required String reason}) {
  final l10n = _l10n(tester);
  expect(
    find.byType(ScreenLoadErrorPanel),
    findsOneWidget,
    reason: '$reason: Activity must show the shared load error panel',
  );
  expect(
    find.text(l10n.screenLoadErrorNetworkTitle),
    findsOneWidget,
    reason: '$reason: the panel must say «${l10n.screenLoadErrorNetworkTitle}»',
  );
  expect(
    find.text(l10n.myWorkRetry),
    findsOneWidget,
    reason: '$reason: the panel must offer «${l10n.myWorkRetry}»',
  );
  expect(
    find.byType(CircularProgressIndicator),
    findsNothing,
    reason: '$reason: no endless spinner over a failed load',
  );
}

void _expectInBounds(WidgetTester tester, Finder finder, double width) {
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(width));
}

void main() {
  group('Activity load over a failing transport', () {
    for (final surface in _Surface.values) {
      testWidgets(
        '${surface.label}: shows «No connection» with «Try again» instead of '
        'a spinner, and keeps it when retrying while still offline',
        (tester) async {
          final server = _Server()..transport = _Transport.down;
          await _withActivity(tester, server, surface: surface, (
            reachability,
          ) async {
            await _pumpFor(tester, _settle);
            expect(
              server.count(_offersOp),
              greaterThan(0),
              reason: 'harness: Activity issued its pinned-zone read',
            );
            expect(
              server.count(_feedOp),
              greaterThan(0),
              reason: 'harness: Activity issued its stream read',
            );
            expect(
              reachability.isOnline,
              isFalse,
              reason: 'harness: the real link reported the transport failure',
            );
            expect(tester.takeException(), isNull);
            _expectNoConnectionPanel(tester, reason: 'after the failed load');
            if (surface == _Surface.phoneRu) {
              final l10n = _l10n(tester);
              _expectInBounds(
                tester,
                find.text(l10n.screenLoadErrorNetworkTitle),
                kPhoneSurface.width,
              );
              _expectInBounds(
                tester,
                find.text(l10n.myWorkRetry),
                kPhoneSurface.width,
              );
            }

            final offersBefore = server.count(_offersOp);
            final feedBefore = server.count(_feedOp);
            await tester.tap(find.text(_l10n(tester).myWorkRetry));
            await _pumpFor(tester, _settle);
            expect(
              server.count(_offersOp),
              greaterThan(offersBefore),
              reason: '«Try again» reloads the pinned zone',
            );
            expect(
              server.count(_feedOp),
              greaterThan(feedBefore),
              reason: '«Try again» reloads the stream',
            );
            expect(tester.takeException(), isNull);
            _expectNoConnectionPanel(
              tester,
              reason: 'after «Try again» while the transport still fails',
            );
          });
        },
      );
    }
  });

  group('Activity recovers on its own when the network comes back', () {
    for (final surface in _Surface.values) {
      testWidgets(
        '${surface.label}: a failed load reloads once when the network is '
        'back and shows its content without a tap',
        (tester) async {
          final server = _Server()..transport = _Transport.down;
          await _withActivity(tester, server, surface: surface, (
            reachability,
          ) async {
            await _pumpFor(tester, _settle);
            expect(
              reachability.isOnline,
              isFalse,
              reason: 'harness: the real link reported the transport failure',
            );
            expect(find.text(_receiptTitle), findsNothing);
            final offersBefore = server.count(_offersOp);
            final feedBefore = server.count(_feedOp);
            expect(offersBefore, greaterThan(0));
            expect(feedBefore, greaterThan(0));

            // The server is reachable again; a probe would now succeed.
            server.transport = _Transport.up;
            reachability.reportSuccess();
            await _pumpFor(tester, _settle);
            expect(tester.takeException(), isNull);
            expect(
              find.text(_receiptTitle),
              findsOneWidget,
              reason:
                  'Activity must reload on its own and show its content '
                  'once the network is back',
            );
            expect(find.byType(ScreenLoadErrorPanel), findsNothing);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(
              (
                offers: server.count(_offersOp) - offersBefore,
                feed: server.count(_feedOp) - feedBefore,
              ),
              (offers: 1, feed: 1),
              reason: 'the online transition reloads the failed load once',
            );

            // And it does not keep reloading.
            await _pumpFor(tester, const Duration(seconds: 30));
            expect(
              (
                offers: server.count(_offersOp) - offersBefore,
                feed: server.count(_feedOp) - feedBefore,
              ),
              (offers: 1, feed: 1),
              reason: 'a recovered Activity must not keep reloading',
            );
            expect(find.text(_receiptTitle), findsOneWidget);
            expect(server.unexpected, isEmpty);
          });
        },
      );
    }
  });

  group('Activity that loaded', () {
    testWidgets(
      'does not reload when the network goes offline and back online',
      (tester) async {
        final server = _Server()..transport = _Transport.up;
        await _withActivity(tester, server, (reachability) async {
          await _pumpFor(tester, _settle);
          expect(
            find.text(_receiptTitle),
            findsOneWidget,
            reason: 'harness: the first load succeeded',
          );
          final before = Map<String, int>.of(server.requests);
          final onlineChanges = <bool>[];
          final sub = reachability.onlineChanges.listen(onlineChanges.add);
          addTearDown(sub.cancel);

          reachability
            ..reportTransportFailure()
            ..reportSuccess();
          await _pumpFor(tester, _settle);
          expect(
            onlineChanges,
            contains(true),
            reason: 'harness: the flip reached onlineChanges listeners',
          );
          expect(
            server.requests,
            before,
            reason: 'a screen whose last load succeeded must not reload',
          );
          expect(find.text(_receiptTitle), findsOneWidget);
          expect(find.byType(ScreenLoadErrorPanel), findsNothing);
          expect(server.unexpected, isEmpty);
        });
      },
    );
  });

  group('Activity load that is never answered', () {
    testWidgets(
      'ends in the error panel with «Try again» after the request timeout',
      (tester) async {
        final server = _Server()..transport = _Transport.silent;
        await _withActivity(tester, server, (reachability) async {
          await _pumpFor(tester, const Duration(seconds: 1));
          expect(
            server.count(_offersOp) + server.count(_feedOp),
            greaterThan(0),
            reason: 'harness: Activity sent its reads',
          );
          await _pumpFor(
            tester,
            const Duration(seconds: kRequestTimeout + 2),
          );
          expect(tester.takeException(), isNull);
          final l10n = _l10n(tester);
          expect(
            find.byType(ScreenLoadErrorPanel),
            findsOneWidget,
            reason:
                'after $kRequestTimeout s without an answer Activity must '
                'stop waiting and show the load error panel',
          );
          expect(find.text(l10n.myWorkRetry), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
        });
      },
    );
  });
}
