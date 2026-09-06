import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/image_object_gc_repository.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/user_erasure_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_case.dart';
import 'package:tentura_server/domain/use_case/user_erasure_case.dart';
import 'package:tentura_server/env.dart';

/// Wires the production account-erasure stack for disposable PG tests.
UserErasureTestStack buildUserErasureTestStack({
  required TenturaDb db,
  required UserRepository userRepository,
  required BeaconLifecycleEffectsCase lifecycleEffects,
  required TransactionalAttentionCase attention,
  Logger? logger,
}) {
  final log = logger ?? Logger('UserErasureTestStack');
  final beacons = BeaconRepository(db);
  final erasure = UserErasureRepository(db);
  final hierarchy = BeaconHierarchyRepository(db);
  final imageGc = ImageObjectGcRepository(db, _NoopRemoteStorage());
  final erasureCase = UserErasureCase(
    erasure,
    beacons,
    userRepository,
    hierarchy,
    lifecycleEffects,
    attention,
    imageGc,
    env: Env(environment: Environment.test),
    logger: log,
  );
  final userCase = UserCase(
    _NoopImageRepository(),
    userRepository,
    _NoopTaskRepository(),
    erasureCase,
    env: Env(environment: Environment.test),
    logger: log,
  );
  return UserErasureTestStack(
    userCase: userCase,
    erasureCase: erasureCase,
    imageGc: imageGc,
  );
}

final class UserErasureTestStack {
  const UserErasureTestStack({
    required this.userCase,
    required this.erasureCase,
    required this.imageGc,
  });

  final UserCase userCase;
  final UserErasureCase erasureCase;
  final ImageObjectGcRepository imageGc;
}

UserRepository buildDefaultUserRepository(TenturaDb db) => UserRepository(
  Env(environment: Environment.test),
  db,
  _NoopTrustEvidenceRepository(),
  _NoopInviteGenealogyRepository(),
  InviteSeedPromptRepositoryMock(),
);

final class _NoopImageRepository extends Fake
    implements ImageRepositoryPort {}

final class _NoopTaskRepository extends Fake implements TaskRepositoryPort {}

final class _NoopTrustEvidenceRepository extends Fake
    implements TrustEvidenceRepositoryPort {}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _NoopRemoteStorage extends Fake implements RemoteStoragePort {}
