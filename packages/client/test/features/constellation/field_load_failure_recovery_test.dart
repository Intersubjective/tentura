// The Field's first load goes through the real stack: RemoteApiService (with
// its reachability link) → ConstellationRepository (ConstellationFieldFetch)
// → ConstellationFieldStoreCase → ConstellationCubit (created as its route
// wrapper creates it, loading on create) → the real ConstellationScreen.
// Only HTTP (MockClient via http.runWithClient) and the shell cubits around
// the screen are substituted.
//
// A load that cannot reach the server must end in the shared load-error panel
// («No connection» + «Try again»), never a blank canvas; when the network
// comes back the Field reloads once on its own; a Field that loaded fine does
// not reload on an offline→online flip; a transport that never answers ends
// in the error panel once the request timeout has passed.
//
// The screen is mounted without its DI route wrapper (as the other Field
// screen tests do), so the panel and the reload are expected below
// ConstellationScreen: the cubit/store, the screen and its body.
//
// NetworkReachability.forTesting() with no probe injected does not probe, so
// reportSuccess() stands in for a successful probe.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tentura/data/service/network_reachability.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/network_reachability_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/screen/constellation_screen.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _fieldFetch = 'ConstellationFieldFetch';

const _viewer = Profile(id: 'Uviewer000001', displayName: 'Bob');

const _contacts = {
  'Uanna00000001': 'Anna',
  'Uboris0000001': 'Boris',
};

/// The map node of person [id]: map node widgets are keyed by the raw id
/// (the `fp:` prefix is only on the layout graph's ids).
Finder _personNode(String id) => find.byKey(TestIds.key(TestIds.graphNode(id)));

Map<String, dynamic> _peer(String id, String displayName) => {
  '__typename': 'v2_ConstellationPeer',
  'id': id,
  'contactOnly': false,
  'displayName': displayName,
  'handle': null,
  'image': null,
  'isNew': false,
  'pinState': null,
  'presence': 'visible',
  'temporaryBeaconId': null,
  'bondContexts': <dynamic>[],
};

/// Bob's Field as the server sends it: Bob and two direct contacts.
Map<String, dynamic> _fieldData() => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': '2026-11-09T12:00:00.000Z',
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': _contacts.keys.toList(),
    'peers': [
      _peer(_viewer.id, _viewer.displayName),
      for (final MapEntry(:key, :value) in _contacts.entries) _peer(key, value),
    ],
    'edges': [
      for (final id in _contacts.keys)
        {
          '__typename': 'v2_ConstellationEdge',
          'src': _viewer.id,
          'dst': id,
          'tier': 1,
        },
    ],
    'requests': <dynamic>[],
    'posts': <dynamic>[],
    'memberWebs': <dynamic>[],
    'anchorProjection': {
      '__typename': 'v2_ConstellationAnchorProjection',
      'revision': '0',
      'anchors': <dynamic>[],
      'pinnedPeers': <dynamic>[],
      'pinnedRequests': <dynamic>[],
      'supportPeers': <dynamic>[],
      'supportEdges': <dynamic>[],
      'serverFilteredBeaconIds': <dynamic>[],
      'serverFilteredBeaconCount': 0,
    },
  },
};

enum _Transport {
  /// The browser cannot reach the server: `fetch` rejects.
  down,

  /// The request goes out and nothing ever comes back.
  silent,

  /// The server answers the Field read.
  up,
}

/// The fake server behind the real HTTP link. Counts requests per GraphQL
/// operation name.
final class _FieldServer {
  _FieldServer(this.transport);

  _Transport transport;
  final operations = <String>[];
  final _never = Completer<http.Response>();

  int requests(String operationName) =>
      operations.where((name) => name == operationName).length;

  http.Client createClient() => MockClient((request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return http.Response(
        jsonEncode({
          'subject': _viewer.id,
          'access_token': 'test-token',
          'expires_in': 3600,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    final payload = jsonDecode(request.body) as Map<String, dynamic>;
    final name = payload['operationName'] as String;
    operations.add(name);
    switch (transport) {
      case _Transport.down:
        throw http.ClientException('Failed to fetch', request.url);
      case _Transport.silent:
        return _never.future;
      case _Transport.up:
        break;
    }
    return http.Response(
      jsonEncode(
        name == _fieldFetch
            ? {'data': _fieldData()}
            : {
                'data': null,
                'errors': [
                  {'message': 'Unexpected operation $name'},
                ],
              },
      ),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

final class _Field {
  _Field(this.server, this.reachability, this.remote);

  final _FieldServer server;
  final NetworkReachability reachability;
  final RemoteApiService remote;
}

/// Runs [body] with a real [RemoteApiService] over [server], reporting to a
/// [NetworkReachability] registered in GetIt before any cubit is built.
Future<void> _withField(
  WidgetTester tester,
  _FieldServer server,
  Future<void> Function(_Field field) body,
) => http.runWithClient(() async {
  final reachability = NetworkReachability.forTesting();
  GetIt.I
    ..registerSingleton<NetworkReachabilityPort>(reachability)
    ..registerSingleton<NetworkReachability>(reachability);
  final remote = RemoteApiService(
    const Env(),
    const WebSocketClientRealtimeSocketFactory(),
    reachability: reachability,
  );
  try {
    await tester.runAsync(remote.setSessionAuth);
    await body(_Field(server, reachability, remote));
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    await tester.runAsync(remote.close);
    await GetIt.I.reset();
    await reachability.dispose();
  }
}, server.createClient);

final class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {}
}

/// Mounts the real Field screen on [surface]. Its cubit is created (and
/// starts loading) when the screen is first built, as the route wrapper does.
Future<void> _pumpField(
  WidgetTester tester,
  _Field field, {
  Locale locale = const Locale('en'),
  Size? surface,
}) async {
  final store = ConstellationStoreFixture(
    ConstellationRepository(field.remote),
    accountId: _viewer.id,
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) => surface == null
          ? TenturaResponsiveScope(child: child!)
          : MediaQuery(
              data: MediaQuery.of(context).copyWith(size: surface),
              child: TenturaResponsiveScope(child: child!),
            ),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ConstellationCubit>(
            lazy: false,
            create: (_) =>
                ConstellationCubit(case_: store.store, viewer: _viewer),
          ),
          BlocProvider(create: (_) => ConstellationSelectionCubit()),
          BlocProvider(create: (_) => HomeTabReselectCubit()),
          BlocProvider<GraphPersonContextCubit>(
            create: (_) => _StubContextCubit(),
          ),
          BlocProvider<ScreenCubit>(
            create: (_) => ScreenCubit(FakeUiEffectPort()),
          ),
        ],
        child: const ConstellationScreen(),
      ),
    ),
  );
  await _pumpFor(tester, const Duration(seconds: 1));
}

/// Bounded pumping: the Field may run layout animations, so never settle.
Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var elapsed = Duration.zero; elapsed < total; elapsed += step) {
    await tester.pump(step);
  }
}

L10n _l10n(WidgetTester tester) =>
    L10n.of(tester.element(find.byType(ConstellationScreen)))!;

void _expectNetworkErrorPanel(WidgetTester tester) {
  final l10n = _l10n(tester);
  expect(
    find.byType(ScreenLoadErrorPanel),
    findsOneWidget,
    reason: 'a failed Field load shows the load-error panel, not a blank map',
  );
  expect(find.text(l10n.screenLoadErrorNetworkTitle), findsOneWidget);
  expect(find.text(l10n.myWorkRetry), findsOneWidget);
}

void _expectFieldLoaded(WidgetTester tester) {
  expect(find.byType(ScreenLoadErrorPanel), findsNothing);
  for (final id in _contacts.keys) {
    expect(
      _personNode(id),
      findsOneWidget,
      reason: 'direct contact $id is on the map',
    );
  }
}

/// The transport fails, then the server recovers and the network is reported
/// back: the Field loads with no tap, reloading exactly once.
Future<void> _expectRecoversOnItsOwn(
  WidgetTester tester, {
  required Locale locale,
  Size? surface,
}) async {
  final server = _FieldServer(_Transport.down);
  await _withField(tester, server, (field) async {
    await _pumpField(tester, field, locale: locale, surface: surface);
    expect(
      field.reachability.isOnline,
      isFalse,
      reason: 'the failed Field read went through the real reachability link',
    );
    expect(server.requests(_fieldFetch), 1);

    server.transport = _Transport.up;
    field.reachability.reportSuccess();
    await _pumpFor(tester, const Duration(seconds: 3));

    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(
      server.requests(_fieldFetch),
      2,
      reason: 'the Field reloads once on its own when the network is back',
    );
    _expectFieldLoaded(tester);

    await _pumpFor(tester, const Duration(seconds: 5));
    expect(
      server.requests(_fieldFetch),
      2,
      reason: 'the online transition reloads exactly once',
    );
    _expectFieldLoaded(tester);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Field load cannot reach the server', () {
    testWidgets(
      'shows «No connection» with «Try again» instead of an empty canvas, '
      'and keeps it while retries still fail',
      (tester) async {
        final server = _FieldServer(_Transport.down);
        await _withField(tester, server, (field) async {
          await _pumpField(tester, field);
          expect(field.reachability.isOnline, isFalse);
          expect(server.requests(_fieldFetch), 1);
          _expectNetworkErrorPanel(tester);

          await tester.tap(find.text(_l10n(tester).myWorkRetry));
          await _pumpFor(tester, const Duration(seconds: 1));

          expect(server.requests(_fieldFetch), 2);
          _expectNetworkErrorPanel(tester);
          expect(tester.takeException(), isNull);
        });
      },
    );

    testWidgets(
      'a request that never answers ends in the error panel after the '
      'request timeout',
      (tester) async {
        final server = _FieldServer(_Transport.silent);
        await _withField(tester, server, (field) async {
          await _pumpField(tester, field);
          expect(server.requests(_fieldFetch), 1);

          await _pumpFor(
            tester,
            const Duration(seconds: kRequestTimeout + 2),
          );

          expect(
            find.byType(ScreenLoadErrorPanel),
            findsOneWidget,
            reason:
                'a Field read with no answer after ${kRequestTimeout}s '
                'shows the load-error panel',
          );
          expect(find.text(_l10n(tester).myWorkRetry), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      },
    );
  });

  group('Field reloads by itself when the network comes back', () {
    testWidgets(
      'on a 375×667 phone in Russian: loaded with no tap, reloaded once',
      (tester) async {
        await usePhoneSurface(tester);
        await _expectRecoversOnItsOwn(
          tester,
          locale: const Locale('ru'),
          surface: kPhoneSurface,
        );
      },
    );

    testWidgets(
      'on a 1280×800 desktop in English: loaded with no tap, reloaded once',
      (tester) async {
        tester.view
          ..physicalSize = const Size(1280, 800)
          ..devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await _expectRecoversOnItsOwn(tester, locale: const Locale('en'));
      },
    );

    testWidgets(
      'a Field that loaded is not reloaded by an offline→online flip',
      (tester) async {
        final server = _FieldServer(_Transport.up);
        await _withField(tester, server, (field) async {
          final changes = <bool>[];
          final sub = field.reachability.onlineChanges.listen(changes.add);
          addTearDown(sub.cancel);

          await _pumpField(tester, field);
          _expectFieldLoaded(tester);
          expect(server.requests(_fieldFetch), 1);

          field.reachability.reportTransportFailure();
          await _pumpFor(tester, const Duration(seconds: 1));
          field.reachability.reportSuccess();
          await _pumpFor(tester, const Duration(seconds: 5));

          expect(
            changes,
            contains(true),
            reason: 'the network did come back online during the test',
          );
          expect(
            server.requests(_fieldFetch),
            1,
            reason: 'a Field that loaded is not reloaded on reconnect',
          );
          _expectFieldLoaded(tester);
          expect(tester.takeException(), isNull);
        });
      },
    );
  });
}
