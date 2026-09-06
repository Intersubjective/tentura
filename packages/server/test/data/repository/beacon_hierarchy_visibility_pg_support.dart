import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import '../../domain/use_case/forward_case_mocks.mocks.dart' as forward_mocks;
import '../../domain/use_case/help_offer_case_mocks.mocks.dart' as help_mocks;
import '../../domain/use_case/invitation_case_mocks.mocks.dart'
    as invitation_mocks;
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/recording_commitment_repository.dart';

/// Wires production use cases with a real [BeaconAccessGuard] so hierarchy-only
/// viewers hit the same `canReadContent` gates as production.
final class HierarchyOnlyViewerHarness {
  HierarchyOnlyViewerHarness({
    required BeaconAccessGuard access,
    required this.childBeaconId,
    required this.hierarchyOnlyViewerId,
  }) : _access = access;

  final BeaconAccessGuard _access;
  final String childBeaconId;
  final String hierarchyOnlyViewerId;

  static final _env = Env(environment: Environment.test);
  static final _logger = Logger('HierarchyOnlyViewerHarness');

  BeaconEntity _childBeacon() {
    final now = DateTime.utc(2026, 1, 1);
    return BeaconEntity(
      id: childBeaconId,
      title: 'Child request',
      author: const UserEntity(id: 'Uhierbob0001'),
      createdAt: now,
      updatedAt: now,
      status: BeaconStatus.open,
    );
  }

  HelpOfferCase buildHelpOfferCase() {
    final beaconRepo = help_mocks.MockBeaconRepositoryPort();
    when(
      beaconRepo.getBeaconById(beaconId: childBeaconId),
    ).thenAnswer((_) async => _childBeacon());
    return HelpOfferCase(
      help_mocks.MockHelpOfferRepositoryPort(),
      beaconRepo,
      RecordingCommitmentRepository(),
      help_mocks.MockInboxRepositoryPort(),
      CapabilityCase(
        help_mocks.MockPersonCapabilityEventRepositoryPort(),
        env: _env,
        logger: _logger,
      ),
      _access,
      env: _env,
      logger: _logger,
    );
  }

  ForwardCase buildForwardCase() => ForwardCase(
    forward_mocks.MockForwardEdgeRepositoryPort(),
    forward_mocks.MockForwardAttributionRepositoryPort(),
    forward_mocks.MockHelpOfferRepositoryPort(),
    forward_mocks.MockInboxRepositoryPort(),
    forward_mocks.MockCapabilityEvidencePort(),
    forward_mocks.MockBeaconRepositoryPort(),
    FakeUserBlockRepository(),
    forward_mocks.MockPersonVisibilityRepositoryPort(),
    _access,
    env: _env,
    logger: _logger,
  );

  InvitationCase buildInvitationCase() => InvitationCase(
    invitation_mocks.MockInvitationRepositoryPort(),
    invitation_mocks.MockUserRepositoryPort(),
    invitation_mocks.MockBeaconRepositoryPort(),
    invitation_mocks.MockVoteUserFriendshipLookupPort(),
    invitation_mocks.MockUserContactRepositoryPort(),
    _access,
    help_mocks.MockForwardEdgeRepositoryPort(),
    FakeUserBlockRepository(),
    env: _env,
    logger: _logger,
  );

  CoordinationCase buildCoordinationCase() => CoordinationCase(
    help_mocks.MockBeaconRepositoryPort(),
    help_mocks.MockHelpOfferRepositoryPort(),
    help_mocks.MockCoordinationRepositoryPort(),
    help_mocks.MockBeaconRoomRepositoryPort(),
    _FakeEvaluationRepository(),
    FakeUserBlockRepository(),
    RecordingCommitmentRepository(),
    CommitmentQueryCase(
      RecordingCommitmentRepository(),
      help_mocks.MockHelpOfferRepositoryPort(),
      env: _env,
      logger: _logger,
    ),
    FakeBeaconHierarchyRepository(),
    guard: _access,
    env: _env,
    logger: _logger,
  );
}

final class _FakeEvaluationRepository extends Fake
    implements EvaluationRepositoryPort {}
