// Offer help, Edit offer and Forward while the server is unreachable: every
// GraphQL request fails on transport the way an aborted browser fetch does
// (a stand-in for a server restart while the live socket stays up). The
// action must tell the person it failed — the existing error (ShowError →
// error bar with the «No Internet connection» copy) — and must not leave
// anything stuck submitting.
//
// Only HTTP and unrelated dependencies are substituted: each mutation runs
// through the real `ForwardRepository` and a real `RemoteApiService` (real
// Ferry link chain, real reachability link).
//
// Every await is bounded with `.timeout(...)`; the widget test uses bounded
// pumps only, so a missing error fails an assertion instead of hanging.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/data/service/network_reachability.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/port/network_reachability_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/inbox_card_actions.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_bus.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../beacon_view/beacon_view_case_test_support.dart';
import '../block/support/controllable_block_case.dart' show noopBlockCase;
import '../contacts/contacts_case_test.dart'
    show FakeContactsRepository, StreamingAuthLocal;

const _me = Profile(id: 'Uhelper000001', displayName: 'Helper');
const _author = Profile(id: 'Uauthor000001', displayName: 'Author');
const _recipientId = 'Urecipient001';
const _recipientName = 'Clara Recipient';
const _beaconId = 'Bbeacon000001';
const _bound = Duration(seconds: 10);

final _beacon = Beacon(
  id: _beaconId,
  title: 'Help moving the piano',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  viewerCanForward: true,
  author: _author,
);

/// The server behind `/api`: while [down], every GraphQL request fails on
/// transport the way an aborted browser fetch does.
final class _Server {
  bool down = false;

  /// Every GraphQL operation the client sent, in order.
  final operations = <String>[];

  int count(String operation) =>
      operations.where((name) => name == operation).length;

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

Map<String, Object?> _wireData(String operationName) => switch (operationName) {
  'ForwardCandidatesFetch' => {
    '__typename': 'query_root',
    'forwardCandidates': [
      {
        '__typename': 'v2_user',
        'id': _recipientId,
        'displayName': _recipientName,
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

class _OneBeaconRepository implements BeaconRepository {
  @override
  Future<Beacon> fetchBeaconById(String id) async => _beacon;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedNavigator extends Mock implements AppNavigator {}

class _FakeBeaconFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The Request page's reads stay on the shared view fakes; the offer itself
/// is written by the real [ForwardRepository] over real HTTP.
class _RealOfferForwardRepository extends FakeBeaconViewForwardRepository {
  _RealOfferForwardRepository(this._real);

  final ForwardRepository _real;

  @override
  Future<bool> offerHelp({
    required String beaconId,
    String? message,
    List<String>? helpTypes,
    int? expectedOfferKind,
    bool notifyHelpOfferListeners = true,
  }) => _real.offerHelp(
    beaconId: beaconId,
    message: message,
    helpTypes: helpTypes,
    expectedOfferKind: expectedOfferKind,
    notifyHelpOfferListeners: notifyHelpOfferListeners,
  );
}

NetworkReachability _registerReachability() {
  final reachability = NetworkReachability.forTesting();
  GetIt.I
    ..registerSingleton<NetworkReachabilityPort>(reachability)
    ..registerSingleton<NetworkReachability>(reachability);
  return reachability;
}

RemoteApiService _remote(NetworkReachability reachability) => RemoteApiService(
  const Env(),
  const WebSocketClientRealtimeSocketFactory(),
  reachability: reachability,
);

ForwardRepository _forwards(RemoteApiService remote) => ForwardRepository(
  remote,
  _OneBeaconRepository(),
  buildTestRealtimeSync().port,
);

/// Real-async harness for the cubit-level flows.
Future<void> _withServer(
  _Server server,
  Future<void> Function(ForwardRepository forwards) body,
) => http.runWithClient(() async {
  final reachability = _registerReachability();
  final remote = _remote(reachability);
  final forwards = _forwards(remote);
  try {
    await remote.setSessionAuth().timeout(_bound);
    await body(forwards).timeout(const Duration(seconds: 30));
  } finally {
    await forwards.dispose().timeout(_bound, onTimeout: () {});
    await remote.close().timeout(_bound, onTimeout: () {});
    await reachability.dispose().timeout(_bound, onTimeout: () {});
    await GetIt.I.reset().timeout(_bound, onTimeout: () {});
  }
}, server.createClient);

Future<void> _until(bool Function() condition, String what) async {
  final deadline = DateTime.now().add(_bound);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// A Request page cubit whose reads come from the shared view fakes.
BeaconViewCubit _requestCubit(
  ForwardRepository forwards,
  UiEffectPort effects, {
  List<FakeHelpOfferCoordinationRow> offers = const [],
}) => BeaconViewCubit(
  id: _beaconId,
  myProfile: _me,
  beaconViewCase: buildTestBeaconViewCase(
    forward: _RealOfferForwardRepository(forwards),
    beaconRepo: TrackingBeaconRepository()
      ..fetchByIdHandler = (_) async => _beacon,
    coordinationRepo: FakeBeaconViewCoordinationRepository(rows: offers),
  ),
  effects: effects,
);

FakeHelpOfferCoordinationRow _myActiveOffer() => (
  beaconId: _beaconId,
  userId: _me.id,
  user: _me,
  message: 'I can bring a trolley',
  helpType: null,
  roleLabel: null,
  status: 0,
  withdrawReason: null,
  createdAt: DateTime.utc(2026, 1, 2),
  updatedAt: DateTime.utc(2026, 1, 2),
  editedAt: null,
  responseType: null,
  responseUpdatedAt: null,
  responseAuthorUserId: null,
  roomAccess: null,
  admissionAction: null,
  lastDeclineReason: null,
  lastRemoveReason: null,
  stakeState: 0,
  offerKind: 0,
  isDirectAuthorForward: false,
  authorSeenAt: null,
);

void _expectNoConnectionError(FakeUiEffectPort effects) => expect(
  effects.emitted.whereType<ShowError>().map((e) => e.error),
  contains(isA<ConnectionUplinkException>()),
  reason: 'the transport failure is reported as the existing error',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Offer help that fails on transport shows the error', () {
    test(
      'on a Request page: the error is shown and the page is not left busy',
      () async {
        addTearDown(() => GetIt.I.reset());
        final server = _Server();
        await _withServer(server, (forwards) async {
          final effects = FakeUiEffectPort();
          final cubit = _requestCubit(forwards, effects);
          try {
            await _until(
              () => cubit.state.beaconContentLoaded,
              'the Request to load',
            );
            server.down = true;
            await cubit
                .offerHelp(message: 'I can bring a trolley')
                .timeout(_bound);

            expect(server.count('BeaconOfferHelp'), 1);
            _expectNoConnectionError(effects);
            expect(cubit.state.isLoading, isFalse, reason: 'not left busy');
            expect(cubit.state.isHelpOffered, isFalse);
          } finally {
            await cubit.close().timeout(_bound, onTimeout: () {});
          }
        });
      },
    );
  });

  group('Edit offer that fails on transport shows the error', () {
    test(
      'on a Request page: the error is shown, the page is not left busy and '
      'the offer keeps its text',
      () async {
        addTearDown(() => GetIt.I.reset());
        final server = _Server();
        await _withServer(server, (forwards) async {
          final effects = FakeUiEffectPort();
          final cubit = _requestCubit(
            forwards,
            effects,
            offers: [_myActiveOffer()],
          );
          try {
            await _until(
              () => cubit.state.myActiveHelpOffer != null,
              'my offer to load',
            );
            server.down = true;
            // What the Edit help offer sheet submits.
            await cubit
                .offerHelp(message: 'I can bring two trolleys')
                .timeout(_bound);

            expect(server.count('BeaconOfferHelp'), 1);
            _expectNoConnectionError(effects);
            expect(cubit.state.isLoading, isFalse, reason: 'not left busy');
            expect(
              cubit.state.myActiveHelpOffer?.message,
              'I can bring a trolley',
            );
          } finally {
            await cubit.close().timeout(_bound, onTimeout: () {});
          }
        });
      },
    );
  });

  group('Forward that fails on transport shows the error', () {
    test(
      'the error is shown, sending is not left busy and the selection is '
      'kept for a retry',
      () async {
        addTearDown(() => GetIt.I.reset());
        final server = _Server();
        await _withServer(server, (forwards) async {
          final store = ContactNameStore();
          GetIt.I.registerSingleton<ContactNameStore>(store);
          final authLocal = StreamingAuthLocal(_me.id);
          final contactsCase = ContactsCase(
            FakeContactsRepository()..fetchMineHandler = () async => {},
            buildTestAuthCase(authLocal, EmptyAuthRemote()),
            store,
            buildTestRealtimeSync().case_,
            env: const Env(),
            logger: Logger('transport-failure-actions'),
          );
          final effects = FakeUiEffectPort();
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
              logger: Logger('transport-failure-actions'),
            ),
            effects: effects,
          );
          try {
            await _until(
              () => cubit.state.candidatesLoad is ForwardCandidatesReady,
              'Forward candidates to load',
            );
            expect(
              cubit.toggleSelection(_recipientId),
              ForwardSelectionResult.selected,
            );

            server.down = true;
            final sent = await cubit.forward().timeout(_bound);

            expect(sent, isFalse);
            expect(server.count('ForwardBeacon'), 1);
            _expectNoConnectionError(effects);
            expect(cubit.state.isLoading, isFalse, reason: 'not left busy');
            expect(cubit.state.selectedIds, {_recipientId});
          } finally {
            await cubit.close().timeout(_bound, onTimeout: () {});
            await contactsCase.dispose().timeout(_bound, onTimeout: () {});
          }
        });
      },
    );
  });

  group('Offer help from an Activity card that fails on transport', () {
    testWidgets(
      'the sheet closes and «No Internet connection» shows on the error bar',
      (tester) async {
        addTearDown(() => GetIt.I.reset());
        final server = _Server();
        await http.runWithClient(() async {
          final reachability = _registerReachability();
          final remote = _remote(reachability);
          final forwards = _forwards(remote);
          final bus = UiEffectBus();
          final raised = <UiEffect>[];
          final sub = bus.effects.listen(raised.add);
          GetIt.I
            ..registerSingleton<UiEffectPort>(bus)
            ..registerSingleton<AppNavigator>(_UnusedNavigator())
            ..registerSingleton<Logger>(Logger('transport-failure-actions'))
            ..registerSingleton<ForwardRepository>(forwards);
          final escaped = <Object>[];
          await tester.binding.setSurfaceSize(const Size(1280, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.runAsync(
            () => remote.setSessionAuth().timeout(_bound),
          );
          await tester.pumpWidget(
            MaterialApp(
              scaffoldMessengerKey: snackbarKey,
              locale: const Locale('en'),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              theme: TenturaTheme.light(),
              builder: (context, child) => TenturaResponsiveScope(
                child: UiEffectHandler(effects: bus, child: child!),
              ),
              home: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) => TextButton(
                      // The card's own call, with any escaped error recorded
                      // instead of lost in an unawaited future.
                      onPressed: () => unawaited(
                        inboxOfferHelp(
                          context,
                          _beacon,
                        ).catchError(escaped.add),
                      ),
                      child: const Text('Offer help'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await _pump(tester);

          server.down = true;
          await tester.tap(find.text('Offer help'));
          await _pump(tester);
          final sheetOpened = find
              .byType(HelpOfferMessageDialog)
              .evaluate()
              .isNotEmpty;
          if (sheetOpened) {
            await tester.enterText(
              find.byKey(TestIds.key(TestIds.helpOfferMessage)),
              'I can bring a trolley',
            );
            await tester.pump();
            await tester.tap(
              find.byKey(TestIds.key(TestIds.helpOfferSubmit)),
            );
            await _pump(tester);
          }

          final sheetLeftOpen = find
              .byType(HelpOfferMessageDialog)
              .evaluate()
              .isNotEmpty;
          final shown = raised.whereType<ShowError>().any(
            (e) => e.error is ConnectionUplinkException,
          );
          final barFound = find
              .descendant(
                of: find.byType(SnackBar),
                // showSnackBar draws the message as a bare RichText.
                matching: find.text(
                  const ConnectionUplinkException().toEn,
                  findRichText: true,
                ),
              )
              .evaluate()
              .length;

          // Tear down before asserting. Nothing that closes the real stack's
          // broadcast streams is awaited in fake time: each close gets a
          // real-time cap through runAsync and is left behind if it stalls.
          await tester.pumpWidget(const SizedBox.shrink());
          await _pump(tester, total: const Duration(seconds: 1));
          unawaited(sub.cancel());
          await tester.runAsync(
            () => Future.any([
              remote.close(),
              reachability.dispose(),
              Future<void>.delayed(const Duration(seconds: 2)),
            ]),
          );
          // forwards.dispose() is not called: under fake async its realtime
          // unsubscription stalls the next pump.

          expect(sheetOpened, isTrue, reason: 'the offer sheet opened');
          expect(server.count('BeaconOfferHelp'), 1);
          expect(sheetLeftOpen, isFalse, reason: 'the sheet is not left busy');
          expect(
            shown,
            isTrue,
            reason: 'the transport failure is reported as the existing error',
          );
          expect(barFound, 1, reason: 'the person sees the error bar');
          expect(
            escaped,
            isEmpty,
            reason: 'the card action handles the failure itself',
          );
        }, server.createClient);
      },
    );
  });
}

/// Bounded: lets the request, error mapping and bar finish in fake time.
Future<void> _pump(
  WidgetTester tester, {
  Duration total = const Duration(seconds: 3),
}) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}
