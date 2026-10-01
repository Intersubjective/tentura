import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura_server/api/controllers/qa_integration_controller.dart';
import 'package:tentura_server/api/controllers/websocket/session/qa_realtime_socket_gate.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/email_auth_transaction_repository_port.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/meritrank_repository_port.dart';
import 'package:tentura_server/domain/port/session_repository_port.dart';
import 'package:tentura_server/domain/port/trust_maintenance_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_sweep_case.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/email_auth_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/domain/use_case/user_trust_edge_case.dart';
import 'package:tentura_server/env.dart';

import 'build_test_invitation_case.dart';
import 'fake_beacon_access_guard.dart';
import 'fake_user_block_repository.dart';
import 'test_attention_harness.dart';

/// A24a: builds the real [QaIntegrationController] for tests.
///
/// The controller's use-case collaborators are `final` classes (not mockable),
/// so they are built for real over mocked ports; none of them is touched by
/// `expireClosure`. Only the closure collaborators are passed in:
///
/// * [closureRepository] — the port the action uses to move the live epoch's
///   `closes_at` into the past;
/// * [sweep] — the real `ClosureFinalizeSweepCase` the action runs once.
///
/// Controller constructor contract for A24a: the existing positional
/// dependencies, followed by `ClosureRepositoryPort` then
/// `ClosureFinalizeSweepCase`.
QaIntegrationController buildTestQaIntegrationController({
  required Env env,
  required ClosureRepositoryPort closureRepository,
  required ClosureFinalizeSweepCase sweep,
}) {
  final userRepo = _MockUserRepository();
  final invitationRepo = _MockInvitationRepository();
  final friendshipLookup = _MockFriendshipLookup();
  final attention = TestAttentionHarness();
  final invitationCase = buildTestInvitationCase(
    invitationRepo: invitationRepo,
    userRepo: userRepo,
    beaconRepo: _MockBeaconRepository(),
    friendshipLookup: friendshipLookup,
    contactRepo: _MockUserContactRepository(),
    guard: FakeBeaconAccessGuard(),
    userBlockRepository: FakeUserBlockRepository(),
    attention: attention,
    env: env,
  );
  final credentialAuthCase = CredentialAuthCase(
    userRepo,
    _MockVerifiedContactRepository(),
    invitationRepo,
    invitationCase,
    attentionIntents: attention.intents,
    attention: attention.transactional,
    env: env,
    logger: Logger('QaControllerTestCredentialAuth'),
  );
  final sessionCase = SessionCase(
    _MockSessionRepository(),
    AuthCase(
      userRepo,
      invitationRepo,
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: env,
      logger: Logger('QaControllerTestAuth'),
    ),
    env: env,
    logger: Logger('QaControllerTestSession'),
  );
  final witnessWindow = _MockWitnessWindow();
  return QaIntegrationController(
    env,
    EmailAuthCase(
      _MockEmailAuthTransactionRepository(),
      _MockEmailSender(),
      credentialAuthCase,
      userRepo,
      sessionCase,
      env: env,
      logger: Logger('QaControllerTestEmailAuth'),
    ),
    userRepo,
    invitationCase,
    friendshipLookup,
    QaRealtimeSocketGate(),
    UserTrustEdgeCase(
      userRepo,
      _MockUserTrustEdgeRepository(),
      _MockTrustMaintenance(),
      witnessWindow: witnessWindow,
      env: env,
      logger: Logger('QaControllerTestTrustEdge'),
    ),
    _MockMeritrank(),
    witnessWindow,
    closureRepository,
    sweep,
  );
}

class _MockUserRepository extends Mock implements UserRepositoryPort {}

class _MockInvitationRepository extends Mock
    implements InvitationRepositoryPort {}

class _MockFriendshipLookup extends Mock
    implements VoteUserFriendshipLookupPort {}

class _MockBeaconRepository extends Mock implements BeaconRepositoryPort {}

class _MockUserContactRepository extends Mock
    implements UserContactRepositoryPort {}

class _MockVerifiedContactRepository extends Mock
    implements VerifiedContactRepositoryPort {}

class _MockSessionRepository extends Mock implements SessionRepositoryPort {}

class _MockEmailAuthTransactionRepository extends Mock
    implements EmailAuthTransactionRepositoryPort {}

class _MockEmailSender extends Mock implements EmailSenderPort {}

class _MockUserTrustEdgeRepository extends Mock
    implements UserTrustEdgeRepositoryPort {}

class _MockTrustMaintenance extends Mock implements TrustMaintenancePort {}

class _MockMeritrank extends Mock implements MeritrankRepositoryPort {}

class _MockWitnessWindow extends Mock implements WitnessWindowPort {}
