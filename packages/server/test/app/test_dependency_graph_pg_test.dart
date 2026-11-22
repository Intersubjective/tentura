@Tags(['pg'])
library;

import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/repository/fcm_remote_repository_module.dart';
import 'package:tentura_server/data/repository/mock/data/users.dart';
import 'package:tentura_server/data/service/fcm_service.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/forward_attribution_repository_port.dart';
import 'package:tentura_server/domain/port/forward_candidate_context_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_admission_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/env.dart';

import '../support/disposable_pg_target.dart';
import '../support/mocks/beacon_repository_mock.dart';
import '../support/test_dependency_graph_expectations.dart';
import '../support/test_di.config.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_TEST_DEPENDENCY_GRAPH_DB',
    defaultNamePrefix: 'tentura_test_di_graph',
  );
  final skipReason = await pgSkipReason(target);

  setUpAll(() async {
    final session = await setUpDisposablePgWriter(target: target);
    addTearDown(() => tearDownDisposablePgWriter(session: session));
  });

  test(
    'the live test graph gets its repository mocks from the test initializer',
    () async {
      addTearDown(getIt.reset);
      await expectTestDependencyGraph(target.databaseEnv);

      final testOnly = GetIt.asNewInstance()
        ..registerSingleton<Logger>(getIt<Logger>())
        ..initTestMocks(environment: Environment.test);
      addTearDown(testOnly.reset);
      await expectTestSupportRepositoryBindings(testOnly);
    },
    skip: skipReason,
  );

  test(
    'the server test graph resolves the moved mock and application dependencies',
    () async {
      addTearDown(getIt.reset);
      await expectTestDependencyGraph(target.databaseEnv);
    },
    skip: skipReason,
  );

  test(
    'the server test graph uses test-support repositories and shares beacon state',
    () async {
      addTearDown(getIt.reset);
      await expectTestDependencyGraph(target.databaseEnv);

      final writer = getIt<BeaconRepositoryPort>();
      const authorId = 'beacon-test-graph-author';
      final created = await writer.createBeacon(
        authorId: authorId,
        title: 'Test graph beacon',
      );
      addTearDown(() => writer.deleteBeaconById(created.id, userId: authorId));
      final imageId = 'staged-for-${created.id}';
      await writer.insertStage(beaconId: created.id, imageId: imageId);
      addTearDown(() => writer.deleteStage(imageId: imageId));

      // The DI factory may return a canonical const instance. Construct a
      // fresh instance of the bound implementation to exercise shared state.
      final createMock = BeaconRepositoryMock.new;
      final reader = createMock();
      expect(reader, isNot(same(writer)));
      expect(await reader.getBeaconById(beaconId: created.id), created);

      const fixtureId = 'B20f3d51e498f';
      final fixture = await reader.getBeaconById(beaconId: fixtureId);
      expect(fixture.id, fixtureId);
      expect(fixture.title, 'Protect Our Forests');

      final stages = await reader.staleStages(
        olderThan: DateTime.timestamp().add(const Duration(minutes: 1)),
      );
      expect(
        stages
            .where((stage) => stage.beaconId == created.id)
            .map(
              (stage) => (stage.imageId, stage.authorId),
            ),
        [(imageId, authorId)],
      );

      expect(
        writer.runtimeType,
        reader.runtimeType,
        reason: 'The live test graph must use the relocated Beacon mock.',
      );
    },
    skip: skipReason,
  );
  test(
    'the live graph uses test-support repositories and retains delivery and fixtures',
    () async {
      addTearDown(getIt.reset);
      await expectTestDependencyGraph(target.databaseEnv);

      const mockTypes = {
        CoordinationRepositoryPort: 'CoordinationRepositoryMock',
        FcmRemoteRepositoryPort: 'FcmRemoteRepositoryMock',
        FcmTokenRepositoryPort: 'FcmTokenRepositoryMock',
        ForwardAttributionRepositoryPort: 'ForwardAttributionRepositoryMock',
        ForwardCandidateContextRepositoryPort:
            'ForwardCandidateContextRepositoryMock',
        ForwardEdgeRepositoryPort: 'ForwardEdgeRepositoryMock',
        HelpOfferAdmissionRepositoryPort: 'HelpOfferAdmissionRepositoryMock',
        HelpOfferRepositoryPort: 'HelpOfferRepositoryMock',
        ImageObjectGcPort: 'ImageObjectGcRepositoryMock',
        ImageRepositoryPort: 'ImageRepositoryMock',
        InboxRepositoryPort: 'InboxRepositoryMock',
        InvitationRepositoryPort: 'InvitationRepositoryMock',
      };
      final liveTypes = {
        for (final port in mockTypes.keys)
          port: getIt.get<Object>(type: port).runtimeType,
      };
      expect(
        liveTypes.map(
          (port, implementation) => MapEntry(port, '$implementation'),
        ),
        mockTypes,
      );

      const invitationId = 'I286f94380611';
      final invitation = await getIt<InvitationRepositoryPort>().getById(
        invitationId: invitationId,
      );
      expect(invitation?.id, invitationId);
      expect(invitation?.issuer, kUserThorin);

      const beaconId = 'B20f3d51e498f';
      final beacon = await getIt<BeaconRepositoryPort>().getBeaconById(
        beaconId: beaconId,
      );
      expect(beacon.id, beaconId);
      expect(beacon.title, 'Protect Our Forests');

      final logLevel = Logger.root.level;
      addTearDown(() => Logger.root.level = logLevel);
      for (final environment in [Environment.dev, Environment.prod]) {
        await _expectUnconfiguredFcmFallback(environment);
      }

      // Resolve from the generated test initializer in isolation so legacy
      // registrations from the application initializer cannot satisfy these
      // lookups. Compare actual Types to the repositories in the live graph.
      final testOnly = GetIt.asNewInstance()
        ..registerSingleton<Logger>(getIt<Logger>())
        ..initTestMocks(environment: Environment.test);
      addTearDown(testOnly.reset);
      final testOnlyTypes = {
        for (final port in mockTypes.keys)
          port: testOnly.maybeGet<Object>(type: port)?.runtimeType,
      };
      expect(testOnlyTypes, liveTypes);
    },
    skip: skipReason,
  );
}

class _FcmRepositoryModule extends FcmRemoteRepositoryModule {}

Future<void> _expectUnconfiguredFcmFallback(String environment) async {
  final env = Env(
    environment: environment,
    serverUri: Uri.parse('https://test.tentura.local'),
    googleClientId: '',
    logLevel: Level.WARNING,
    fbProjectId: '',
    fbClientEmail: '',
    fbPrivateKey: '',
  );
  expect(env.isFcmConfigured, isFalse);

  final logger = Logger('unconfigured FCM delivery ($environment)');
  final warnings = <String>[];
  final logs = logger.onRecord.listen((record) {
    if (record.loggerName == logger.name && record.level == Level.WARNING) {
      warnings.add(record.message);
    }
  });
  addTearDown(logs.cancel);

  final requests = <http.Request>[];
  final result = await http.runWithClient(
    () => _FcmRepositoryModule()
        .fcmRemoteRepository(
          env,
          FcmService(env),
          getIt<FcmTokenRepositoryPort>(),
          logger,
        )
        .sendChatNotification(
          fcmTokens: ['t'],
          message: const FcmNotificationEntity(title: 'Title', body: 'Message'),
        ),
    () => MockClient((request) async {
      requests.add(request);
      return http.Response('Unexpected FCM HTTP request', 500);
    }),
  );
  expect(result, isEmpty);
  expect(requests, isEmpty);
  expect(
    warnings,
    contains(
      startsWith('[FCM] Push mocking enabled — missing server Firebase creds:'),
    ),
  );
}
