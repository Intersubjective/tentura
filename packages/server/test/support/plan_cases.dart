import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_plan_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/plan_attention_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_plan_case.dart';
import 'package:tentura_server/domain/use_case/plan_attention_case.dart';
import 'package:tentura_server/domain/use_case/plan_step_sweep_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import 'fake_user_block_repository.dart';

/// Request plan («либретто», #220): the real plan use-case graph over one
/// database, for pg suites.
final class PlanCases {
  factory PlanCases(TenturaDb db, Env env) {
    final logger = Logger('PlanCasesPgTest');
    final room = BeaconRoomRepository(db);
    final attention = TransactionalAttentionCase(
      MutatingUnitOfWork(db),
      AttentionDispatchRepository(db, logger),
    );
    final intents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(
        room,
        db,
        HelpOfferRepository(db),
        CommitmentRepository(db),
      ),
      UserRepository(
        env,
        db,
        _NoopInviteGenealogyRepository(),
        InviteSeedPromptRepositoryMock(),
      ),
      BeaconAccessRepository(db),
      FakeUserBlockRepository(),
    );
    final repo = BeaconPlanRepository(db);
    final store = PlanAttentionRepository(db);
    final closure = ClosureRepository(db);
    final planAttention = PlanAttentionCase(
      repo,
      store,
      intents,
      attention,
      closure,
      BeaconRoomNotificationContextRepository(
        room,
        db,
        HelpOfferRepository(db),
        CommitmentRepository(db),
      ),
      env: env,
      logger: logger,
    );
    return PlanCases._(
      plan: BeaconPlanCase(
        repo,
        closure,
        attention,
        planAttention,
        env: env,
        logger: logger,
      ),
      attention: planAttention,
      sweep: PlanStepSweepCase(
        repo,
        store,
        closure,
        attention,
        intents,
        planAttention,
        env: env,
        logger: logger,
      ),
      transactional: attention,
    );
  }

  PlanCases._({
    required this.plan,
    required this.attention,
    required this.sweep,
    required this.transactional,
  });

  final BeaconPlanCase plan;
  final PlanAttentionCase attention;
  final PlanStepSweepCase sweep;
  final TransactionalAttentionCase transactional;
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
