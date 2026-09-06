import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_outbox_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/user_erasure_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_erasure_case.dart';
import 'package:tentura_server/env.dart';

class _CallOrder {
  final calls = <String>[];
}

class _TrackingImageGc extends Fake implements ImageObjectGcPort {
  _TrackingImageGc(this.order);

  final _CallOrder order;

  @override
  Future<void> enqueue({
    required String imageId,
    required String authorId,
  }) async {
    order.calls.add('imageGc.enqueue($authorId,$imageId)');
  }
}

class _FakeErasurePort extends Fake implements UserErasurePort {
  @override
  Future<List<OwnedPublishedBeaconRow>> listOwnedPublishedBeacons({
    required String userId,
  }) async =>
      const [];

  @override
  Future<List<String>> listOwnedDraftBeaconIds({required String userId}) async =>
      const [];

  @override
  Future<void> deleteUserScopedEvaluationAndCapabilityRows({
    required String userId,
  }) async {}

  @override
  Future<void> deleteOrdinaryRoomMessagesAuthoredByUser({
    required String userId,
  }) async {}

  @override
  Future<List<String>> deleteOwnedImageRows({required String userId}) async =>
      ['Iprofile1'];
}

class _FakeBeaconRepo extends Fake implements BeaconRepositoryPort {}

class _FakeUserRepo extends Fake implements UserRepositoryPort {
  _FakeUserRepo(this.order);

  final _CallOrder order;

  @override
  Future<void> deleteById({required String id}) async {
    order.calls.add('userRepo.deleteById($id)');
  }
}

class _FakeHierarchy extends Fake implements BeaconHierarchyRepositoryPort {
  @override
  Future<void> lockMutationScope() async {}
}

class _FakeOutbox extends Fake implements BeaconHierarchyOutboxPort {}

class _FakeUow extends Fake implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) async =>
      action();
}

class _FakeDispatch extends Fake implements AttentionDispatchPort {
  @override
  Future<void> record(AttentionDispatchIntent intent) async {}
}

void main() {
  late _CallOrder order;
  late _TrackingImageGc imageGc;
  late _FakeUserRepo userRepo;
  late UserErasureCase case_;

  setUp(() {
    order = _CallOrder();
    imageGc = _TrackingImageGc(order);
    userRepo = _FakeUserRepo(order);
    case_ = UserErasureCase(
      _FakeErasurePort(),
      _FakeBeaconRepo(),
      userRepo,
      _FakeHierarchy(),
      BeaconLifecycleEffectsCase(
        _FakeOutbox(),
        env: Env(environment: Environment.test),
        logger: Logger('UserErasureImageGcTest'),
      ),
      TransactionalAttentionCase(_FakeUow(), _FakeDispatch()),
      imageGc,
      env: Env(environment: Environment.test),
      logger: Logger('UserErasureImageGcTest'),
    );
  });

  test(
    'enqueues image GC only after the account erasure transaction commits',
    () async {
      expect(await case_.deleteById(id: 'Uauth'), isTrue);

      expect(order.calls, [
        'userRepo.deleteById(Uauth)',
        'imageGc.enqueue(Uauth,Iprofile1)',
      ]);
    },
  );
}
