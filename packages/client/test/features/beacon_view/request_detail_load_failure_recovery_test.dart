// A Request whose first load failed because the network was down reloads on
// its own once the network is back: the viewer should not have to find and
// tap «Try again» after the offline banner goes away.
//
// Real path: the Request route's BeaconViewScope, BeaconViewCubit, the
// production BeaconViewCase, its repositories, the Ferry link chain (with the
// reachability link) and RemoteApiService. Only HTTP is substituted: while
// the network is "down" every GraphQL request fails the way a browser fetch
// does (`ClientException('Failed to fetch')`); once it is back, the requests
// reach a GraphqlRoundTripServer holding one Request.
//
// Recovery is signalled the way the app learns about it: the server answers
// again and NetworkReachability reports success (standing in for the
// reachability probe, which has its own tests).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/service/network_reachability.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/network_reachability_port.dart';
import 'package:tentura/domain/use_case/author_invite_case.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/author_invite_repository.dart';
import 'package:tentura/features/beacon/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura/features/beacon_plan/data/repository/beacon_plan_repository.dart';
import 'package:tentura/features/beacon_plan/domain/use_case/beacon_plan_case.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/post_view/data/repository/beacon_kind_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart'
    show InMemoryBeaconChildCommandStore;
import '../../support/graphql_round_trip_server.dart';
import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'request_open_round_trips_support.dart';

class _SignedInProfileCubit extends Mock implements ProfileCubit {
  _SignedInProfileCubit(this._profile);

  final Profile _profile;

  @override
  ProfileState get state => ProfileState(profile: _profile);

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

/// The network between the client and [server]: down until [up] is set.
/// Counts every GraphQL operation the client tries to send, whether or not
/// it got through.
class _Network {
  _Network({required this.up})
    : server = openRoundsServer(
        viewerId: kOpenRoundsAuthorId,
        status: BeaconStatus.open,
      );

  final GraphqlRoundTripServer server;
  bool up;
  final attempts = <String, int>{};

  int attemptsOf(String operation) => attempts[operation] ?? 0;

  /// Snapshot of [attempts], to diff against later.
  Map<String, int> snapshot() => Map.of(attempts);

  String describe() => [
    for (final entry in attempts.entries) '${entry.key}: ${entry.value}',
  ].join(', ');

  http.Client createClient() {
    final inner = server.client;
    return MockClient((request) async {
      if (!request.url.path.endsWith('/session/access-token')) {
        final body = jsonDecode(request.body);
        for (final operation in body is List ? body : [body]) {
          final name =
              (operation as Map<String, dynamic>)['operationName'] as String? ??
              '';
          attempts[name] = attemptsOf(name) + 1;
        }
        if (!up) throw http.ClientException('Failed to fetch');
      }
      final forwarded = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes;
      return http.Response.fromStream(await inner.send(forwarded));
    });
  }
}

class _RequestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      usesPathAsKey: true,
      page: BeaconViewRoute.page,
      path: '$kPathBeaconView/:id',
      initial: true,
      children: [
        AutoRoute(
          page: BeaconViewOperationalRoute.page,
          path: '',
          initial: true,
        ),
      ],
    ),
  ];
}

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  required String reason,
}) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(done(), isTrue, reason: 'timed out waiting: $reason');
}

/// Opens the Request route over the real Request stack, with [network] as
/// the only substituted boundary, and runs [body] with the reachability the
/// HTTP link reports to.
Future<void> _withRequestRoute(
  WidgetTester tester,
  _Network network,
  Future<void> Function(NetworkReachability reachability) body, {
  Locale locale = const Locale('en'),
}) => http.runWithClient(() async {
  final reachability = NetworkReachability.forTesting();
  final effects = FakeUiEffectPort();
  final remote = RemoteApiService(
    const Env(),
    const WebSocketClientRealtimeSocketFactory(),
    reachability: reachability,
  );
  final realtime = buildTestRealtimeSync();
  final router = _RequestRouter();
  await GetIt.I.reset();
  GetIt.I
    ..registerSingleton<NetworkReachabilityPort>(reachability)
    ..registerSingleton<NetworkReachability>(reachability);
  try {
    await tester.runAsync(remote.setSessionAuth);
    final wired = buildWiredBeaconViewCase(remote, realtime);
    final images = ImageRepository();
    final profile = _SignedInProfileCubit(
      const Profile(id: kOpenRoundsAuthorId, displayName: 'Viewer'),
    );
    final screen = ScreenCubit(effects);
    GetIt.I
      ..registerSingleton<UiEffectPort>(effects)
      ..registerSingleton<ProfileCubit>(profile)
      ..registerSingleton<ScreenCubit>(screen)
      ..registerSingleton<ImageRepository>(images)
      ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository())
      ..registerSingleton<BeaconKindRepository>(BeaconKindRepository(remote))
      ..registerSingleton<BeaconViewCase>(wired.viewCase)
      ..registerSingleton<BeaconThreadsCase>(wired.threadsCase)
      ..registerSingleton<BeaconHierarchyCase>(
        BeaconHierarchyCase(
          BeaconHierarchyRepository(remote),
          BeaconCreateCase(wired.beacons, images),
          wired.beacons,
          InMemoryBeaconChildCommandStore(),
          realtime.case_,
        ),
      )
      ..registerSingleton<BeaconPlanCase>(
        BeaconPlanCase(
          BeaconPlanRepository(remote, realtime.port),
          env: const Env(),
          logger: Logger('request-load-recovery'),
        ),
      )
      ..registerSingleton<AuthorInviteCase>(
        AuthorInviteCase(
          AuthorInviteRepository(remote),
          env: const Env(),
          logger: Logger('request-load-recovery'),
        ),
      );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        builder: (context, child) => MultiBlocProvider(
          providers: [
            BlocProvider<ScreenCubit>.value(value: screen),
            BlocProvider<ProfileCubit>.value(value: profile),
          ],
          child: child!,
        ),
        routerConfig: router.config(
          deepLinkBuilder: (_) =>
              const DeepLink.path('$kPathBeaconView/$kOpenRoundsBeaconId'),
        ),
      ),
    );
    await body(reachability);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    router.dispose();
    await realtime.port.dispose();
    await tester.runAsync(remote.close);
    await GetIt.I.reset();
    await reachability.dispose();
  }
}, network.createClient);

/// The operation the Request screen's first load reads the Request with.
const _requestRead = 'BeaconFetchById';

/// Answers the reads in flight until the client goes quiet.
Future<void> _serve(WidgetTester tester, _Network network) async {
  await network.server.drain(
    wait: () => tester.pump(const Duration(milliseconds: 10)),
  );
  await _pumpFor(tester, const Duration(milliseconds: 500));
}

/// The Request's title somewhere on screen (app bar or body).
Finder _requestTitle() => find.text(kOpenRoundsTitle, findRichText: true);

BeaconViewCubit _requestCubit(WidgetTester tester) =>
    tester.element(find.byType(BeaconViewScreen)).read<BeaconViewCubit>();

Future<void> _expectReloadsOnceWhenOnline(
  WidgetTester tester, {
  required Locale locale,
  double? maxWidth,
}) async {
  final network = _Network(up: false);
  await _withRequestRoute(tester, network, (reachability) async {
    await _pumpUntil(
      tester,
      () => find.byType(BeaconViewScreen).evaluate().isNotEmpty,
      reason: 'the Request screen mounts',
    );
    final cubit = _requestCubit(tester);
    await _pumpUntil(
      tester,
      () => cubit.state.hasError,
      reason: 'the first load fails (${network.describe()})',
    );
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(reachability.isOnline, isFalse);

    final l10n = L10n.of(tester.element(find.byType(BeaconViewScreen)))!;
    // A Request that cannot be read offline shows the shared screen-load
    // error panel, like Requests, Activity and the Field: «No connection»
    // with «Try again».
    final title = find.text(l10n.screenLoadErrorNetworkTitle);
    final retry = find.text(l10n.myWorkRetry);
    expect(find.byType(ScreenLoadErrorPanel), findsOneWidget);
    expect(title, findsOneWidget);
    expect(retry, findsOneWidget);
    if (maxWidth != null) {
      for (final finder in [title, retry]) {
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(maxWidth));
      }
    }
    expect(_requestTitle(), findsNothing);
    expect(network.attemptsOf(_requestRead), greaterThan(0));

    // Still offline: nothing retries behind the error, so a later read can
    // only come from the online transition.
    final before = network.attemptsOf(_requestRead);
    await _pumpFor(tester, const Duration(seconds: 3));
    expect(
      network.attemptsOf(_requestRead),
      before,
      reason: 'no retry reaches the server while offline',
    );
    expect(retry, findsOneWidget);

    network.up = true;
    reachability.reportSuccess();
    await _serve(tester, network);
    expect(tester.takeException(), isNull, reason: 'no overflow');

    expect(
      _requestTitle(),
      findsWidgets,
      reason:
          'the Request loads without a tap once the network is back '
          '(attempts: ${network.describe()})',
    );
    expect(find.byType(ScreenLoadErrorPanel), findsNothing);
    expect(find.text(l10n.myWorkRetry), findsNothing);
    expect(
      network.attemptsOf(_requestRead) - before,
      1,
      reason: '$_requestRead is sent again exactly once',
    );

    // Nothing keeps reloading once the Request is on screen.
    await _pumpFor(tester, const Duration(seconds: 3));
    expect(
      network.attemptsOf(_requestRead) - before,
      1,
      reason: '$_requestRead is sent again exactly once',
    );
  }, locale: locale);
}

void main() {
  group('A Request whose first load failed while offline', () {
    testWidgets('reloads on its own once the network is back', (
      tester,
    ) async {
      await _expectReloadsOnceWhenOnline(tester, locale: const Locale('en'));
    });

    testWidgets('reloads on its own on a 375×667 phone in Russian', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await _expectReloadsOnceWhenOnline(
        tester,
        locale: const Locale('ru'),
        maxWidth: kPhoneSurface.width,
      );
    });

    testWidgets('reloads on its own on a 1280×800 desktop in English', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1280, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _expectReloadsOnceWhenOnline(
        tester,
        locale: const Locale('en'),
        maxWidth: 1280,
      );
    });
  });

  group('A Request that loaded', () {
    testWidgets('is not reloaded when the network drops and comes back', (
      tester,
    ) async {
      final network = _Network(up: true);
      await _withRequestRoute(tester, network, (reachability) async {
        await _serve(tester, network);
        expect(tester.takeException(), isNull);
        expect(
          _requestTitle(),
          findsWidgets,
          reason: 'the Request loads (attempts: ${network.describe()})',
        );
        expect(_requestCubit(tester).state.hasError, isFalse);
        expect(network.attemptsOf(_requestRead), 1);

        final transitions = <bool>[];
        final sub = reachability.onlineChanges.listen(transitions.add);
        addTearDown(sub.cancel);
        network.up = false;
        reachability.reportTransportFailure();
        await _pumpFor(tester, const Duration(milliseconds: 500));
        expect(reachability.isOnline, isFalse);

        network.up = true;
        reachability.reportSuccess();
        await tester.pump();
        expect(transitions.last, isTrue, reason: 'onlineChanges emitted true');
        await _serve(tester, network);
        await _pumpFor(tester, const Duration(seconds: 3));
        expect(tester.takeException(), isNull);

        expect(_requestTitle(), findsWidgets);
        expect(
          network.attemptsOf(_requestRead),
          1,
          reason: 'a loaded Request is not read again',
        );
      });
    });
  });
}
