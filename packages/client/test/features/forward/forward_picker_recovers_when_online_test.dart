// The Forward recipient picker over real HTTP while the server is
// unreachable: the first load fails on transport, the picker shows
// «No connection» + «Try again», and NetworkReachability goes offline through
// the real HTTP link. When reachability comes back online the picker must
// reload on its own — once — and show the candidates, with no tap. A picker
// whose load succeeded must not reload on a reachability flip.
//
// `reachability.reportSuccess()` stands in for a reachability probe that
// reached the server (the probe itself is covered by
// test/data/service/network_reachability_probe_test.dart).
//
// Only HTTP and unrelated dependencies are substituted; the load runs
// wire -> real ForwardRepository -> ForwardCase -> ForwardCubit ->
// ForwardBeaconPage / ForwardRecipientPicker. Bounded pumps only.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/data/service/network_reachability.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/network_reachability_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/forward_beacon_screen.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart' show noopBlockCase;
import '../contacts/contacts_case_test.dart'
    show FakeContactsRepository, StreamingAuthLocal;

const _me = Profile(id: 'Uviewer000001', displayName: 'Viewer');
const _author = Profile(id: 'Uauthor000001', displayName: 'Author');
const _candidateId = 'Ucandidate001';
const _candidateName = 'Clara Candidate';
const _beaconId = 'Bbeacon000001';

final _beacon = Beacon(
  id: _beaconId,
  title: 'Help moving the piano',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  viewerCanForward: true,
  author: _author,
);

Map<String, Object?> _wireData(String operationName) => switch (operationName) {
  'ForwardCandidatesFetch' => {
    '__typename': 'query_root',
    'forwardCandidates': [
      {
        '__typename': 'v2_user',
        'id': _candidateId,
        'displayName': _candidateName,
        'handle': null,
        'description': '',
        'my_vote': 1,
        'trusts_viewer': true,
        'is_mutual_friend': true,
        'shares_active_context': false,
        'image': null,
        'scores': <Object>[],
        'user_presence': null,
        'user_availability': null,
      },
    ],
  },
  'BeaconInvolvementData' => {
    '__typename': 'query_root',
    'beaconInvolvement': {
      '__typename': 'v2_BeaconInvolvement',
      'forwardedToIds': <String>[],
      'helpOfferedIds': <String>[],
      'withdrawnIds': <String>[],
      'rejectedIds': <String>[],
      'watchingIds': <String>[],
      'onwardForwarderIds': <String>[],
      'declinedOfferIds': <String>[],
      'myForwardedRecipients': <Map<String, dynamic>>[],
    },
  },
  _ => throw UnsupportedError('Unexpected operation: $operationName'),
};

/// The server behind `/api`: while [down], every GraphQL request fails on
/// transport the way an aborted browser fetch does.
final class _Server {
  bool down = false;

  /// Every GraphQL operation the client sent, in order.
  final operations = <String>[];

  int count(String operation, {int from = 0}) =>
      operations.skip(from).where((name) => name == operation).length;

  http.Client createClient() => MockClient((request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return http.Response(
        jsonEncode({
          'subject': _me.id,
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
    if (down) throw http.ClientException('Failed to fetch', request.url);
    return http.Response(
      jsonEncode({'data': _wireData(name)}),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

class _OneBeaconRepository implements BeaconRepository {
  @override
  Future<Beacon> fetchBeaconById(String id) async => _beacon;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _me);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _FakeInvitationRepository extends Fake implements InvitationRepository {
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 0,
    int acceptedOffset = 0,
    int acceptedLimit = 0,
  }) async => (
    pending: <InvitationEntity>[],
    accepted: <InvitationEntity>[],
    pendingCount: 0,
  );

  @override
  Future<InvitationFetchByIdResult?> fetchById(String id) async => null;

  @override
  Future<void> dispose() async {}
}

class _FakeBeaconFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Bounded: lets requests, retries and rebuilds finish in fake time.
Future<void> _settle(
  WidgetTester tester, {
  Duration total = const Duration(seconds: 3),
}) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

/// Pumps the real Forward page over a real HTTP stack, runs [body], then
/// tears everything down (bounded) before rethrowing any failure.
Future<void> _withForwardPage(
  WidgetTester tester,
  _Server server,
  Future<void> Function(NetworkReachability reachability) body,
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
  final forwards = ForwardRepository(
    remote,
    _OneBeaconRepository(),
    buildTestRealtimeSync().port,
  );
  final store = ContactNameStore();
  GetIt.I
    ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
    ..registerSingleton<Logger>(Logger('forward-picker-recovery'))
    ..registerSingleton<InvitationRepository>(_FakeInvitationRepository())
    ..registerSingleton<ContactNameStore>(store);
  final authLocal = StreamingAuthLocal(_me.id);
  final contactsCase = ContactsCase(
    FakeContactsRepository()..fetchMineHandler = () async => {},
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    buildTestRealtimeSync().case_,
    env: const Env(),
    logger: Logger('forward-picker-recovery'),
  );
  await tester.runAsync(
    () => remote.setSessionAuth().timeout(const Duration(seconds: 10)),
  );
  final cubit = ForwardCubit(
    beaconId: _beaconId,
    forwardCase: ForwardCase(
      forwards,
      authLocal,
      _FakeBeaconFactCardRepository(),
      _FakeProfileRepository(),
      contactsCase,
      noopBlockCase(),
      env: const Env(),
      logger: Logger('forward-picker-recovery'),
    ),
    effects: GetIt.I<UiEffectPort>(),
  );
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  Object? failure;
  StackTrace? failureTrace;
  try {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        builder: (context, child) => TenturaResponsiveScope(child: child!),
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ForwardCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
          ],
          child: const ForwardBeaconPage(beaconId: _beaconId),
        ),
      ),
    );
    await body(reachability);
  } catch (error, trace) {
    failure = error;
    failureTrace = trace;
  }
  await tester.pumpWidget(const SizedBox.shrink());
  unawaited(cubit.close());
  unawaited(contactsCase.dispose());
  unawaited(forwards.dispose());
  await _settle(tester, total: const Duration(seconds: 1));
  await tester.runAsync(
    () => remote.close().timeout(const Duration(seconds: 10), onTimeout: () {}),
  );
  await GetIt.I.reset();
  if (failure != null) {
    Error.throwWithStackTrace(failure, failureTrace!);
  }
}, server.createClient);

L10n _l10n(WidgetTester tester) =>
    L10n.of(tester.element(find.byType(ForwardBeaconPage)))!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Forward picker reloads on its own when the app is back online', () {
    testWidgets(
      'a picker whose load failed offline shows «No connection» and, once '
      'reachability is back, reloads once and shows the candidates with no '
      'tap',
      (tester) async {
        final server = _Server()..down = true;
        await _withForwardPage(tester, server, (reachability) async {
          await _settle(tester, total: const Duration(seconds: 5));
          final l10n = _l10n(tester);
          expect(find.byType(ScreenLoadErrorPanel), findsOneWidget);
          expect(find.text(l10n.screenLoadErrorNetworkTitle), findsOneWidget);
          expect(find.text(l10n.myWorkRetry), findsOneWidget);
          expect(find.text(_candidateName), findsNothing);
          expect(
            reachability.isOnline,
            isFalse,
            reason: 'the failed load took the app offline',
          );

          // The server is back and a probe reached it; nobody taps.
          server.down = false;
          final sentBeforeRecovery = server.operations.length;
          reachability.reportSuccess();
          await _settle(tester, total: const Duration(seconds: 5));

          expect(
            find.text(_candidateName),
            findsOneWidget,
            reason: 'the picker reloaded by itself after recovery',
          );
          expect(find.byType(ScreenLoadErrorPanel), findsNothing);
          expect(
            server.count('ForwardCandidatesFetch', from: sentBeforeRecovery),
            1,
            reason: 'one reload per recovery',
          );

          // Staying online issues no further reloads.
          await _settle(tester, total: const Duration(seconds: 30));
          expect(
            server.count('ForwardCandidatesFetch', from: sentBeforeRecovery),
            1,
          );
          expect(find.text(_candidateName), findsOneWidget);
        });
      },
    );

    testWidgets(
      'a picker that loaded issues no reload when the app comes back online',
      (tester) async {
        final server = _Server();
        await _withForwardPage(tester, server, (reachability) async {
          await _settle(tester, total: const Duration(seconds: 5));
          expect(find.text(_candidateName), findsOneWidget);
          expect(server.count('ForwardCandidatesFetch'), 1);

          reachability
            ..reportTransportFailure()
            ..reportSuccess();
          await _settle(tester, total: const Duration(seconds: 10));

          expect(server.count('ForwardCandidatesFetch'), 1);
          expect(find.text(_candidateName), findsOneWidget);
        });
      },
    );
  });
}
