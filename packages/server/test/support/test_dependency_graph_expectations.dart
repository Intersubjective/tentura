import 'package:test/test.dart';
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
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';
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
import 'mocks/user_trust_edge_repository_mock.dart';
import 'test_di.dart';

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
  expect(getIt<EmailSenderPort>(), isA<LoggingEmailSender>());
  expect(getIt<UserTrustEdgeCase>(), isA<UserTrustEdgeCase>());
  await getIt.getAsync<PgNotificationService>();
}
