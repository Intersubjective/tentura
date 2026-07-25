import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/user_case.dart';
import 'package:tentura_server/env.dart';

/// Records call order across both ports so tests can assert the account
/// deletion sequence without depending on a real database.
class _CallOrder {
  final calls = <String>[];
}

class _TrackingImageRepo extends Fake implements ImageRepositoryPort {
  _TrackingImageRepo(this.order);

  final _CallOrder order;
  Object? failure;

  @override
  Future<void> deleteAllOf({required String userId}) async {
    order.calls.add('imageRepo.deleteAllOf($userId)');
    if (failure != null) throw failure!;
  }
}

class _TrackingUserRepo extends Fake implements UserRepositoryPort {
  _TrackingUserRepo(this.order);

  final _CallOrder order;

  @override
  Future<void> deleteById({required String id}) async {
    order.calls.add('userRepo.deleteById($id)');
  }
}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {}

void main() {
  late _CallOrder order;
  late _TrackingImageRepo imageRepo;
  late _TrackingUserRepo userRepo;
  late UserCase case_;

  setUp(() {
    order = _CallOrder();
    imageRepo = _TrackingImageRepo(order);
    userRepo = _TrackingUserRepo(order);
    case_ = UserCase(
      imageRepo,
      userRepo,
      _FakeTaskRepo(),
      env: Env(environment: Environment.test),
      logger: Logger('UserCaseImageGcTest'),
    );
  });

  test(
    'enqueues every owned image for GC before deleting the user row',
    () async {
      expect(await case_.deleteById(id: 'Uauth'), isTrue);

      expect(order.calls, [
        'imageRepo.deleteAllOf(Uauth)',
        'userRepo.deleteById(Uauth)',
      ]);
    },
  );

  test(
    'never deletes the user row when image cleanup fails, so nothing is orphaned',
    () async {
      imageRepo.failure = StateError('gc enqueue failed');

      await expectLater(
        case_.deleteById(id: 'Uauth'),
        throwsA(isA<StateError>()),
      );

      expect(order.calls, ['imageRepo.deleteAllOf(Uauth)']);
    },
  );
}
