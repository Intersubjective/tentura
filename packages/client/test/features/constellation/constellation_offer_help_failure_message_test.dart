import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:tentura/data/service/network_reachability.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/port/network_reachability_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import '../../support/test_realtime_sync.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/test_forward_case.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
const _genericRetryCopy = 'Could not submit your offer. Try again.';

final class _FieldRepository implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => ConstellationField(
    loadedAt: DateTime.utc(2026, 9, 9),
    context: '',
    peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
    edges: [const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1)],
    requests: [
      const ConstellationRequest(
        id: 'req-a',
        authorId: 'a',
        title: 'Need tools',
        status: 0,
      ),
    ],
  );
}

/// The server behind `/api`: while down, every GraphQL request fails on
/// transport the way an aborted browser fetch does.
final class _Server {
  final operations = <String>[];

  int count(String operation) =>
      operations.where((name) => name == operation).length;

  http.Client createClient() => MockClient((request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return http.Response(
        jsonEncode({
          'subject': _ego.id,
          'access_token': 'test-token',
          'expires_in': 3600,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    final payload = jsonDecode(request.body) as Map<String, dynamic>;
    operations.add(payload['operationName'] as String);
    throw http.ClientException('Failed to fetch', request.url);
  });
}

class _NoBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

/// Opens the Field, selects the Request, taps Offer help, types a note and
/// submits it. Returns the effects the screen emitted.
Future<FakeUiEffectPort> _submitOfferFromField(
  WidgetTester tester,
  _Server server,
) async {
  final getIt = GetIt.I;
  if (!getIt.isRegistered<Logger>()) {
    getIt.registerSingleton<Logger>(Logger('test'));
  }
  final reachability = NetworkReachability.forTesting();
  getIt
    ..registerSingleton<NetworkReachabilityPort>(reachability)
    ..registerSingleton<NetworkReachability>(reachability);
  addTearDown(getIt.reset);
  final remote = RemoteApiService(
    const Env(),
    const WebSocketClientRealtimeSocketFactory(),
    reachability: reachability,
  );
  final forwardRepository = ForwardRepository(
    remote,
    _NoBeaconRepository(),
    buildTestRealtimeSync().port,
  );
  await tester.runAsync(remote.setSessionAuth);
  final cubit = (await tester.runAsync(() async {
    final fixture = ConstellationStoreFixture(
      _FieldRepository(),
      accountId: 'ego',
    );
    await fixture.ready();
    final created = fixture.createCubit(
      viewer: _ego,
      forwardCase: buildTestForwardCase(forwardRepository),
    );
    await created.load();
    return created;
  }))!;

  const size = Size(1200, 900);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final fx = FakeUiEffectPort();
  await tester.pumpPeopleTagsWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationCubit>.value(value: cubit),
              BlocProvider<GraphPersonContextCubit>(
                create: (_) => _StubContextCubit(),
              ),
              BlocProvider<ScreenCubit>(create: (_) => ScreenCubit(fx)),
            ],
            child: Scaffold(
              body: ConstellationBody(
                legendExpanded: false,
                onToggleLegend: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  cubit.selectRequest('req-a');
  await tester.pump();
  await tester.tap(
    find.byKey(const Key('constellation.request_preview.primary')),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(TestIds.key(TestIds.helpOfferMessage)),
    'I can lend a drill',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(TestIds.key(TestIds.helpOfferSubmit)));
  // Short, bounded pumps: a snackbar is gone once pumpAndSettle outlasts it.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return fx;
}

void main() {
  group('Offering help from the Field when the request fails in transit', () {
    testWidgets(
      'reports the transport failure as the shared error, not the retry copy',
      (tester) async {
        final server = _Server();
        late FakeUiEffectPort fx;
        await http.runWithClient(() async {
          fx = await _submitOfferFromField(tester, server);
        }, server.createClient);

        expect(server.count('BeaconOfferHelp'), 1);
        expect(
          find.text(_genericRetryCopy, findRichText: true),
          findsNothing,
          reason: 'a transport failure must not be reported as a bad offer',
        );
        expect(
          fx.emitted.whereType<ShowError>().map((e) => e.error),
          contains(isA<ConnectionUplinkException>()),
        );
      },
    );
  });
}
