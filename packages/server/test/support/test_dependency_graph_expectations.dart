import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:tentura_server/app/di.dart' show configureDependencies;
import 'package:tentura_server/data/service/email/logging_email_sender.dart';
import 'package:tentura_server/data/service/pg_notification_service.dart';
import 'package:tentura_server/domain/port/band_candidate_port.dart';
import 'package:tentura_server/domain/port/beacon_member_webs_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/capability_cell_port.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';
import 'package:tentura_server/domain/port/capability_own_evidence_port.dart';
import 'package:tentura_server/domain/port/capability_telemetry_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/complaint_repository_port.dart';
import 'package:tentura_server/domain/port/constellation_field_repository_port.dart';
import 'package:tentura_server/domain/port/constellation_field_requests_port.dart';
import 'package:tentura_server/domain/port/constellation_mutual_trust_port.dart';
import 'package:tentura_server/domain/port/constellation_trust_chain_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
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
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/invite_seed_prompt_port.dart';
import 'package:tentura_server/domain/port/lineage_memory_read_port.dart';
import 'package:tentura_server/domain/port/meritrank_repository_port.dart';
import 'package:tentura_server/domain/port/meritrank_status_port.dart';
import 'package:tentura_server/domain/port/mutual_friends_repository_port.dart';
import 'package:tentura_server/domain/port/pair_block_query_port.dart';
import 'package:tentura_server/domain/port/people_tags_repository_port.dart';
import 'package:tentura_server/domain/port/person_capability_event_repository_port.dart';
import 'package:tentura_server/domain/port/polling_act_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/routing_mute_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/trust_ledger_port.dart';
import 'package:tentura_server/domain/port/trust_preference_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/port/user_availability_repository_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';
import 'package:tentura_server/domain/use_case/user_trust_edge_case.dart';
import 'package:tentura_server/env.dart';

import 'mocks/band_candidate_repository_mock.dart';
import 'mocks/beacon_member_webs_repository_mock.dart';
import 'mocks/beacon_repository_mock.dart';
import 'mocks/capability_cell_repository_mock.dart';
import 'mocks/capability_evidence_repository_mock.dart';
import 'mocks/capability_own_evidence_repository_mock.dart';
import 'mocks/capability_telemetry_repository_mock.dart';
import 'mocks/closure_repository_mock.dart';
import 'mocks/commitment_repository_mock.dart';
import 'mocks/complaint_repository_mock.dart';
import 'mocks/constellation_field_repository_mock.dart';
import 'mocks/constellation_field_requests_repository_mock.dart';
import 'mocks/constellation_mutual_trust_repository_mock.dart';
import 'mocks/constellation_trust_chain_repository_mock.dart';
import 'mocks/coordination_repository_mock.dart';
import 'mocks/fcm_remote_repository_mock.dart';
import 'mocks/fcm_token_repository_mock.dart';
import 'mocks/forward_attribution_repository_mock.dart';
import 'mocks/forward_candidate_context_repository_mock.dart';
import 'mocks/forward_edge_repository_mock.dart';
import 'mocks/help_offer_admission_repository_mock.dart';
import 'mocks/help_offer_repository_mock.dart';
import 'mocks/image_object_gc_repository_mock.dart';
import 'mocks/image_repository_mock.dart';
import 'mocks/inbox_repository_mock.dart';
import 'mocks/invitation_repository_mock.dart';
import 'mocks/user_trust_edge_repository_mock.dart';
import 'test_di.dart';
import 'test_di.config.dart';

Future<void> expectRepositoryImplementationsByEnvironment(Env database) async {
  const repositories = {
    InviteSeedPromptPort: 'InviteSeedPromptRepository',
    TrustLedgerPort: 'TrustLedgerRepository',
    TrustPreferencePort: 'TrustPreferenceRepository',
    UploadQuotaRepositoryPort: 'UploadQuotaRepository',
    UserAvailabilityRepositoryPort: 'UserAvailabilityRepository',
    UserBlockRepositoryPort: 'UserBlockRepository',
    UserContactRepositoryPort: 'UserContactRepository',
    UserPresenceRepositoryPort: 'UserPresenceRepository',
    UserRepositoryPort: 'UserRepository',
    WitnessWindowPort: 'WitnessWindowRepository',
  };
  Map<Type, Type?> resolvedTypes(GetIt registry) => {
    for (final port in repositories.keys)
      port: registry.maybeGet<Object>(type: port)?.runtimeType,
  };

  for (final environment in [Environment.dev, Environment.prod]) {
    final env = Env(
      environment: environment,
      serverUri: Uri.parse('http://127.0.0.1:2080'),
      publicOrigin: 'http://127.0.0.1:2080',
      publicKey: Env.kJwtPublicKey,
      privateKey: Env.kJwtPrivateKey,
      pgHost: database.pgHost,
      pgPort: database.pgPort,
      pgDatabase: database.pgDatabase,
      pgUsername: database.pgUsername,
      pgPassword: database.pgPassword,
      printEnv: false,
      workersCount: 1,
    );
    await configureDependencies(env);
    await getIt.getAsync<PgNotificationService>();
    expect(
      resolvedTypes(
        getIt,
      ).map((port, type) => MapEntry(port, type?.toString())),
      repositories,
      reason: '$environment must resolve the real repositories.',
    );
    await getIt.reset();
  }

  await expectTestDependencyGraph(database);
  final liveTypes = resolvedTypes(getIt);
  expect(
    liveTypes.map((port, type) => MapEntry(port, type?.toString())),
    repositories.map((port, name) => MapEntry(port, '${name}Mock')),
    reason: 'The live test graph must resolve every repository mock.',
  );

  final testOnly = GetIt.asNewInstance()
    ..registerSingleton<Logger>(getIt<Logger>())
    ..initTestMocks(environment: Environment.test);
  addTearDown(testOnly.reset);
  expect(
    resolvedTypes(testOnly),
    liveTypes,
    reason: 'The test-support initializer must supply the live graph mocks.',
  );
}

Future<void> expectTestDependencyGraph(Env env) async {
  await configureTestDependencies(env);

  expect(getIt<Env>(), same(env));
  expect(getIt<BandCandidatePort>(), isA<BandCandidateRepositoryMock>());
  expect(
    getIt<BeaconMemberWebsRepositoryPort>(),
    isA<BeaconMemberWebsRepositoryMock>(),
  );
  expect(getIt<BeaconRepositoryPort>(), isA<BeaconRepositoryMock>());
  expect(getIt<CapabilityCellPort>(), isA<CapabilityCellRepositoryMock>());
  expect(
    getIt<CapabilityEvidencePort>(),
    isA<CapabilityEvidenceRepositoryMock>(),
  );
  expect(
    getIt<CapabilityOwnEvidencePort>(),
    isA<CapabilityOwnEvidenceRepositoryMock>(),
  );
  expect(
    getIt<CapabilityTelemetryPort>(),
    isA<CapabilityTelemetryRepositoryMock>(),
  );
  expect(getIt<ClosureRepositoryPort>(), isA<ClosureRepositoryMock>());
  expect(getIt<CommitmentRepositoryPort>(), isA<CommitmentRepositoryMock>());
  expect(getIt<ComplaintRepositoryPort>(), isA<ComplaintRepositoryMock>());
  expect(
    getIt<ConstellationFieldRepositoryPort>(),
    isA<ConstellationFieldRepositoryMock>(),
  );
  expect(
    getIt<ConstellationFieldRequestsPort>(),
    isA<ConstellationFieldRequestsRepositoryMock>(),
  );
  expect(
    getIt<ConstellationMutualTrustPort>(),
    isA<ConstellationMutualTrustRepositoryMock>(),
  );
  expect(
    getIt<ConstellationTrustChainPort>(),
    isA<ConstellationTrustChainRepositoryMock>(),
  );
  expect(
    getIt<UserTrustEdgeRepositoryPort>(),
    isA<UserTrustEdgeRepositoryMock>(),
  );
  expect(
    getIt<CoordinationRepositoryPort>(),
    isA<CoordinationRepositoryMock>(),
  );
  expect(getIt<FcmRemoteRepositoryPort>(), isA<FcmRemoteRepositoryMock>());
  expect(getIt<FcmTokenRepositoryPort>(), isA<FcmTokenRepositoryMock>());
  expect(
    getIt<ForwardAttributionRepositoryPort>(),
    isA<ForwardAttributionRepositoryMock>(),
  );
  expect(
    getIt<ForwardCandidateContextRepositoryPort>(),
    isA<ForwardCandidateContextRepositoryMock>(),
  );
  expect(getIt<ForwardEdgeRepositoryPort>(), isA<ForwardEdgeRepositoryMock>());
  expect(
    getIt<HelpOfferAdmissionRepositoryPort>(),
    isA<HelpOfferAdmissionRepositoryMock>(),
  );
  expect(getIt<HelpOfferRepositoryPort>(), isA<HelpOfferRepositoryMock>());
  expect(getIt<ImageObjectGcPort>(), isA<ImageObjectGcRepositoryMock>());
  expect(getIt<ImageRepositoryPort>(), isA<ImageRepositoryMock>());
  expect(getIt<InboxRepositoryPort>(), isA<InboxRepositoryMock>());
  expect(getIt<InvitationRepositoryPort>(), isA<InvitationRepositoryMock>());
  expect(getIt<EmailSenderPort>(), isA<LoggingEmailSender>());
  expect(getIt<UserTrustEdgeCase>(), isA<UserTrustEdgeCase>());
  await getIt.getAsync<PgNotificationService>();
}

Future<void> expectTestSupportRepositoryBindings(GetIt testOnly) async {
  const expectedMocks = {
    InviteGenealogyRepositoryPort: 'InviteGenealogyRepositoryMock',
    LineageMemoryReadPort: 'LineageMemoryReadRepositoryMock',
    MeritrankRepositoryPort: 'MeritrankRepositoryMock',
    MeritrankStatusPort: 'MeritrankStatusRepositoryMock',
    MutualFriendsRepositoryPort: 'MutualFriendsRepositoryMock',
    PairBlockQueryPort: 'PairBlockQueryRepositoryMock',
    PeopleTagsRepositoryPort: 'PeopleTagsRepositoryMock',
    PersonCapabilityEventRepositoryPort: 'PersonCapabilityEventRepositoryMock',
    PollingActRepositoryPort: 'PollingActRepositoryMock',
    PollingRepositoryPort: 'PollingRepositoryMock',
    RoutingMutePort: 'RoutingMuteRepositoryMock',
    TaskRepositoryPort: 'TaskRepositoryMock',
  };
  final testOnlyTypes = {
    for (final port in expectedMocks.keys)
      port: await _repositoryType(testOnly, port),
  };
  final liveTypes = {
    for (final port in expectedMocks.keys)
      port: await _repositoryType(getIt, port),
  };
  expect(
    testOnlyTypes.map((port, type) => MapEntry(port, type?.toString())),
    expectedMocks,
    reason: 'The test initializer must supply each repository mock.',
  );
  expect(
    liveTypes,
    testOnlyTypes,
    reason:
        'The running server test graph must resolve each test-support mock.',
  );
}

Future<Type?> _repositoryType(GetIt registry, Type port) async {
  if (port != TaskRepositoryPort) {
    return registry.maybeGet<Object>(type: port)?.runtimeType;
  }
  // TaskRepositoryMock is a lazy singleton with an async factory.
  if (!registry.isRegistered<TaskRepositoryPort>()) return null;
  return (await registry.getAsync<TaskRepositoryPort>()).runtimeType;
}
