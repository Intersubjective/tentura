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
